#!/bin/bash
"""
Centralized Error Logging and Alerting System
Provides structured error logging with severity levels and alerting
"""

set -euo pipefail

# Configuration
LOG_DIR="/var/log/haproxy"
ERROR_LOG="$LOG_DIR/errors.log"
ALERT_LOG="$LOG_DIR/alerts.log"
STRUCTURED_LOG="$LOG_DIR/structured-errors.json"
MAX_LOG_SIZE="100M"
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
PAGERDUTY_KEY="${PAGERDUTY_KEY:-}"

# Severity levels
declare -A SEVERITY_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["NOTICE"]=2
    ["WARNING"]=3
    ["ERROR"]=4
    ["CRITICAL"]=5
    ["ALERT"]=6
    ["EMERGENCY"]=7
)

# Alert thresholds (minimum severity level to trigger alerts)
EMAIL_THRESHOLD=4    # ERROR and above
WEBHOOK_THRESHOLD=3  # WARNING and above
SLACK_THRESHOLD=4    # ERROR and above
PAGERDUTY_THRESHOLD=5 # CRITICAL and above

# Create log directory
mkdir -p "$LOG_DIR"

# Logging function with structured output
log_error() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="${4:-}"
    local error_code="${5:-0}"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname
    hostname=$(hostname)
    local pid=$$
    
    # Validate severity level
    if [[ ! "${SEVERITY_LEVELS[$severity]:-}" ]]; then
        severity="ERROR"
    fi
    
    local severity_num="${SEVERITY_LEVELS[$severity]}"
    
    # Create structured log entry
    local structured_entry
    structured_entry=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "pid": $pid,
    "severity": "$severity",
    "severity_num": $severity_num,
    "component": "$component",
    "message": "$message",
    "details": "$details",
    "error_code": $error_code,
    "stack": "haproxy-wildcard-ssl"
}
EOF
    )
    
    # Write to structured log
    echo "$structured_entry" >> "$STRUCTURED_LOG"
    
    # Write to traditional error log
    echo "[$timestamp] [$severity] [$component] $message" >> "$ERROR_LOG"
    
    # Write details if provided
    if [[ -n "$details" ]]; then
        echo "[$timestamp] [$severity] [$component] Details: $details" >> "$ERROR_LOG"
    fi
    
    # Also output to stderr for immediate visibility
    echo "[$severity] [$component] $message" >&2
    
    # Send to syslog if available
    if command -v logger >/dev/null 2>&1; then
        local syslog_priority
        case "$severity" in
            "DEBUG") syslog_priority="daemon.debug" ;;
            "INFO") syslog_priority="daemon.info" ;;
            "NOTICE") syslog_priority="daemon.notice" ;;
            "WARNING") syslog_priority="daemon.warning" ;;
            "ERROR") syslog_priority="daemon.err" ;;
            "CRITICAL") syslog_priority="daemon.crit" ;;
            "ALERT") syslog_priority="daemon.alert" ;;
            "EMERGENCY") syslog_priority="daemon.emerg" ;;
            *) syslog_priority="daemon.err" ;;
        esac
        
        logger -t "haproxy-stack" -p "$syslog_priority" "[$component] $message"
    fi
    
    # Trigger alerts if severity meets threshold
    if [[ $severity_num -ge $EMAIL_THRESHOLD ]]; then
        send_email_alert "$severity" "$component" "$message" "$details"
    fi
    
    if [[ $severity_num -ge $WEBHOOK_THRESHOLD ]]; then
        send_webhook_alert "$severity" "$component" "$message" "$details"
    fi
    
    if [[ $severity_num -ge $SLACK_THRESHOLD ]]; then
        send_slack_alert "$severity" "$component" "$message" "$details"
    fi
    
    if [[ $severity_num -ge $PAGERDUTY_THRESHOLD ]]; then
        send_pagerduty_alert "$severity" "$component" "$message" "$details"
    fi
    
    # Log rotation check
    check_log_rotation
}

# Send email alert
send_email_alert() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="$4"
    
    if [[ -z "$ALERT_EMAIL" ]] || ! command -v mail >/dev/null 2>&1; then
        return 0
    fi
    
    local subject="[$severity] HAProxy Stack Alert: $component"
    local body
    body=$(cat <<EOF
HAProxy Stack Alert

Timestamp: $(date)
Hostname: $(hostname)
Severity: $severity
Component: $component
Message: $message

Details:
$details

Stack: HAProxy Wildcard SSL
Environment: $(whoami)@$(hostname)

This is an automated alert from the HAProxy error logging system.
EOF
    )
    
    if echo "$body" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null; then
        echo "[$severity] Email alert sent to $ALERT_EMAIL" >> "$ALERT_LOG"
    else
        echo "[$severity] Failed to send email alert to $ALERT_EMAIL" >> "$ALERT_LOG"
    fi
}

# Send webhook alert
send_webhook_alert() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="$4"
    
    if [[ -z "$WEBHOOK_URL" ]] || ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    
    local payload
    payload=$(cat <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "severity": "$severity",
    "component": "$component",
    "message": "$message",
    "details": "$details",
    "stack": "haproxy-wildcard-ssl",
    "alert_type": "error_log"
}
EOF
    )
    
    if curl -s -X POST -H "Content-Type: application/json" \
       -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1; then
        echo "[$severity] Webhook alert sent successfully" >> "$ALERT_LOG"
    else
        echo "[$severity] Failed to send webhook alert" >> "$ALERT_LOG"
    fi
}

# Send Slack alert
send_slack_alert() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="$4"
    
    if [[ -z "$SLACK_WEBHOOK" ]] || ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    
    # Choose color based on severity
    local color
    case "$severity" in
        "WARNING") color="warning" ;;
        "ERROR") color="danger" ;;
        "CRITICAL"|"ALERT"|"EMERGENCY") color="danger" ;;
        *) color="good" ;;
    esac
    
    local payload
    payload=$(cat <<EOF
{
    "username": "HAProxy Stack Monitor",
    "icon_emoji": ":warning:",
    "attachments": [
        {
            "color": "$color",
            "title": "$severity Alert: $component",
            "text": "$message",
            "fields": [
                {
                    "title": "Hostname",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date)",
                    "short": true
                },
                {
                    "title": "Details",
                    "value": "$details",
                    "short": false
                }
            ],
            "footer": "HAProxy Wildcard SSL Stack",
            "ts": $(date +%s)
        }
    ]
}
EOF
    )
    
    if curl -s -X POST -H "Content-Type: application/json" \
       -d "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1; then
        echo "[$severity] Slack alert sent successfully" >> "$ALERT_LOG"
    else
        echo "[$severity] Failed to send Slack alert" >> "$ALERT_LOG"
    fi
}

# Send PagerDuty alert
send_pagerduty_alert() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="$4"
    
    if [[ -z "$PAGERDUTY_KEY" ]] || ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    
    local event_action="trigger"
    local dedup_key="haproxy-${component}-$(date +%Y%m%d)"
    
    local payload
    payload=$(cat <<EOF
{
    "routing_key": "$PAGERDUTY_KEY",
    "event_action": "$event_action",
    "dedup_key": "$dedup_key",
    "payload": {
        "summary": "$severity: $component - $message",
        "source": "$(hostname)",
        "severity": "$(echo "$severity" | tr '[:upper:]' '[:lower:]')",
        "component": "$component",
        "group": "haproxy-stack",
        "class": "infrastructure",
        "custom_details": {
            "message": "$message",
            "details": "$details",
            "hostname": "$(hostname)",
            "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
            "stack": "haproxy-wildcard-ssl"
        }
    }
}
EOF
    )
    
    if curl -s -X POST -H "Content-Type: application/json" \
       -d "$payload" "https://events.pagerduty.com/v2/enqueue" >/dev/null 2>&1; then
        echo "[$severity] PagerDuty alert sent successfully" >> "$ALERT_LOG"
    else
        echo "[$severity] Failed to send PagerDuty alert" >> "$ALERT_LOG"
    fi
}

# Check and perform log rotation if needed
check_log_rotation() {
    local log_files=("$ERROR_LOG" "$ALERT_LOG" "$STRUCTURED_LOG")
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            local file_size
            file_size=$(stat -c%s "$log_file" 2>/dev/null || echo "0")
            local max_size_bytes
            max_size_bytes=$(echo "$MAX_LOG_SIZE" | sed 's/M/*1024*1024/g' | bc 2>/dev/null || echo "104857600")
            
            if [[ $file_size -gt $max_size_bytes ]]; then
                rotate_log_file "$log_file"
            fi
        fi
    done
}

# Rotate a log file
rotate_log_file() {
    local log_file="$1"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local rotated_file="${log_file}.${timestamp}"
    
    if mv "$log_file" "$rotated_file" 2>/dev/null; then
        # Compress the rotated file
        if command -v gzip >/dev/null 2>&1; then
            gzip "$rotated_file" &
        fi
        
        # Create new log file
        touch "$log_file"
        chmod 644 "$log_file"
        
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [INFO] [error-logger] Log rotated: $log_file -> $rotated_file" >> "$log_file"
        
        # Clean up old rotated files (keep last 10)
        find "$(dirname "$log_file")" -name "$(basename "$log_file").*" -type f | \
            sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi
}

# Query error logs
query_errors() {
    local severity_filter="${1:-}"
    local component_filter="${2:-}"
    local time_filter="${3:-1h}"
    local count="${4:-50}"
    
    echo "Querying error logs..."
    echo "Severity: ${severity_filter:-all}"
    echo "Component: ${component_filter:-all}"
    echo "Time: last $time_filter"
    echo "Count: $count"
    echo "---"
    
    # Convert time filter to seconds
    local seconds
    case "$time_filter" in
        *h) seconds=$((${time_filter%h} * 3600)) ;;
        *m) seconds=$((${time_filter%m} * 60)) ;;
        *d) seconds=$((${time_filter%d} * 86400)) ;;
        *) seconds=3600 ;;  # Default to 1 hour
    esac
    
    local cutoff_time
    cutoff_time=$(date -d "$seconds seconds ago" +"%Y-%m-%d %H:%M:%S")
    
    # Query structured log if available and jq is present
    if [[ -f "$STRUCTURED_LOG" ]] && command -v jq >/dev/null 2>&1; then
        local jq_filter=".timestamp >= \"$cutoff_time\""
        
        if [[ -n "$severity_filter" ]]; then
            jq_filter="$jq_filter and .severity == \"$severity_filter\""
        fi
        
        if [[ -n "$component_filter" ]]; then
            jq_filter="$jq_filter and .component == \"$component_filter\""
        fi
        
        jq -r "select($jq_filter) | \"\(.timestamp) [\(.severity)] [\(.component)] \(.message)\"" \
           "$STRUCTURED_LOG" | tail -n "$count"
    else
        # Fallback to traditional log
        local grep_pattern=""
        if [[ -n "$severity_filter" ]]; then
            grep_pattern="\\[$severity_filter\\]"
        fi
        
        if [[ -n "$component_filter" ]]; then
            if [[ -n "$grep_pattern" ]]; then
                grep_pattern="$grep_pattern.*\\[$component_filter\\]"
            else
                grep_pattern="\\[$component_filter\\]"
            fi
        fi
        
        if [[ -n "$grep_pattern" ]]; then
            grep "$grep_pattern" "$ERROR_LOG" | tail -n "$count"
        else
            tail -n "$count" "$ERROR_LOG"
        fi
    fi
}

# Generate error report
generate_error_report() {
    local output_file="${1:-/tmp/error-report-$(date +%Y%m%d_%H%M%S).txt}"
    
    echo "Generating error report: $output_file"
    
    {
        echo "HAProxy Stack Error Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "=========================="
        echo
        
        echo "Error Summary (Last 24 hours):"
        echo "------------------------------"
        if command -v jq >/dev/null 2>&1 && [[ -f "$STRUCTURED_LOG" ]]; then
            local cutoff
            cutoff=$(date -d "24 hours ago" -u +"%Y-%m-%dT%H:%M:%SZ")
            
            echo "By Severity:"
            jq -r "select(.timestamp >= \"$cutoff\") | .severity" "$STRUCTURED_LOG" | \
                sort | uniq -c | sort -nr
            
            echo
            echo "By Component:"
            jq -r "select(.timestamp >= \"$cutoff\") | .component" "$STRUCTURED_LOG" | \
                sort | uniq -c | sort -nr
            
            echo
            echo "Recent Critical Errors:"
            jq -r "select(.timestamp >= \"$cutoff\" and .severity_num >= 5) | \"\(.timestamp) [\(.severity)] [\(.component)] \(.message)\"" \
               "$STRUCTURED_LOG" | tail -20
        else
            echo "Structured logging not available, showing recent errors:"
            tail -50 "$ERROR_LOG"
        fi
        
        echo
        echo "System Status:"
        echo "-------------"
        echo "Disk Usage: $(df -h /var/log/haproxy | awk 'NR==2 {print $5}')"
        echo "Memory Usage: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        
        echo
        echo "Log File Sizes:"
        echo "--------------"
        ls -lh "$LOG_DIR"/*.log 2>/dev/null || echo "No log files found"
        
    } > "$output_file"
    
    echo "Error report generated: $output_file"
}

# Main function
main() {
    case "${1:-log}" in
        "log")
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 log <severity> <component> <message> [details] [error_code]"
                echo "Severities: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY"
                exit 1
            fi
            log_error "$2" "$3" "$4" "${5:-}" "${6:-0}"
            ;;
        "query")
            query_errors "$2" "$3" "$4" "$5"
            ;;
        "report")
            generate_error_report "$2"
            ;;
        "test")
            echo "Testing error logging system..."
            log_error "INFO" "test" "Test info message" "This is a test"
            log_error "WARNING" "test" "Test warning message" "This is a test warning"
            log_error "ERROR" "test" "Test error message" "This is a test error"
            echo "Test completed. Check logs in $LOG_DIR"
            ;;
        "help"|"-h"|"--help")
            cat << 'EOF'
Error Logger for HAProxy Stack

Usage: error-logger.sh <command> [options]

Commands:
    log <severity> <component> <message> [details] [error_code]
        Log an error with specified severity and details
        
    query [severity] [component] [time] [count]
        Query error logs with optional filters
        
    report [output_file]
        Generate comprehensive error report
        
    test
        Test the error logging system
        
    help
        Show this help message

Severities:
    DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY

Environment Variables:
    ALERT_EMAIL     Email address for alerts
    WEBHOOK_URL     Generic webhook URL
    SLACK_WEBHOOK   Slack webhook URL
    PAGERDUTY_KEY   PagerDuty integration key

Examples:
    error-logger.sh log ERROR haproxy "Configuration validation failed" "Syntax error on line 42"
    error-logger.sh query ERROR haproxy 1h 20
    error-logger.sh report /tmp/my-report.txt

EOF
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use 'error-logger.sh help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"