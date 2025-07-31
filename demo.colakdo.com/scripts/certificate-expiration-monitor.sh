#!/bin/bash

#---------------------------------------------------------------------
# Certificate Expiration Monitoring Script
# Monitors SSL certificate expiration and sends alerts
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
CERT_PATH="${CERT_PATH:-/etc/ssl/certs/live/${DOMAIN}}"
LOG_FILE="${LOG_FILE:-/var/log/haproxy/cert-monitor.log}"
WARNING_DAYS="${WARNING_DAYS:-30}"
CRITICAL_DAYS="${CRITICAL_DAYS:-7}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Check if certificate file exists
check_cert_exists() {
    local cert_file="$CERT_PATH/cert.pem"
    if [[ ! -f "$cert_file" ]]; then
        log_message "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    return 0
}

# Get certificate expiration date
get_cert_expiration() {
    local cert_file="$CERT_PATH/cert.pem"
    openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2
}

# Calculate days until expiration
days_until_expiration() {
    local expiry_date="$1"
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local seconds_diff=$((expiry_epoch - current_epoch))
    local days_diff=$((seconds_diff / 86400))
    echo "$days_diff"
}

# Send alert notification
send_alert() {
    local level="$1"
    local message="$2"
    local days_left="$3"
    
    log_message "$level" "$message"
    
    # Email notification
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "[$level] SSL Certificate Alert - $DOMAIN" "$ALERT_EMAIL"
        log_message "INFO" "Email alert sent to $ALERT_EMAIL"
    fi
    
    # Webhook notification
    if [[ -n "$WEBHOOK_URL" ]] && command -v curl >/dev/null 2>&1; then
        local payload=$(cat <<EOF
{
    "text": "[$level] SSL Certificate Alert",
    "attachments": [
        {
            "color": "$([[ "$level" == "CRITICAL" ]] && echo "danger" || echo "warning")",
            "fields": [
                {
                    "title": "Domain",
                    "value": "$DOMAIN",
                    "short": true
                },
                {
                    "title": "Days Until Expiration",
                    "value": "$days_left",
                    "short": true
                },
                {
                    "title": "Message",
                    "value": "$message",
                    "short": false
                }
            ]
        }
    ]
}
EOF
        )
        
        if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" >/dev/null; then
            log_message "INFO" "Webhook alert sent successfully"
        else
            log_message "ERROR" "Failed to send webhook alert"
        fi
    fi
}

# Get certificate information
get_cert_info() {
    local cert_file="$CERT_PATH/cert.pem"
    
    echo "Certificate Information for $DOMAIN:"
    echo "======================================"
    
    # Subject
    echo "Subject: $(openssl x509 -in "$cert_file" -noout -subject | cut -d= -f2-)"
    
    # Issuer
    echo "Issuer: $(openssl x509 -in "$cert_file" -noout -issuer | cut -d= -f2-)"
    
    # Serial Number
    echo "Serial: $(openssl x509 -in "$cert_file" -noout -serial | cut -d= -f2)"
    
    # Valid dates
    echo "Valid From: $(openssl x509 -in "$cert_file" -noout -startdate | cut -d= -f2)"
    echo "Valid Until: $(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)"
    
    # Subject Alternative Names
    local san=$(openssl x509 -in "$cert_file" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//')
    if [[ -n "$san" ]]; then
        echo "SAN: $san"
    fi
    
    # Fingerprint
    echo "SHA256 Fingerprint: $(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d= -f2)"
    
    echo "======================================"
}

# Main monitoring function
monitor_certificate() {
    log_message "INFO" "Starting certificate expiration check for $DOMAIN"
    
    # Check if certificate exists
    if ! check_cert_exists; then
        send_alert "CRITICAL" "Certificate file not found for domain $DOMAIN" "N/A"
        return 1
    fi
    
    # Get expiration date
    local expiry_date
    if ! expiry_date=$(get_cert_expiration); then
        send_alert "CRITICAL" "Failed to read certificate expiration date for $DOMAIN" "N/A"
        return 1
    fi
    
    # Calculate days until expiration
    local days_left
    if ! days_left=$(days_until_expiration "$expiry_date"); then
        send_alert "CRITICAL" "Failed to calculate certificate expiration for $DOMAIN" "N/A"
        return 1
    fi
    
    log_message "INFO" "Certificate for $DOMAIN expires in $days_left days ($expiry_date)"
    
    # Check expiration thresholds
    if [[ $days_left -le $CRITICAL_DAYS ]]; then
        send_alert "CRITICAL" "Certificate for $DOMAIN expires in $days_left days! Immediate action required." "$days_left"
        return 2
    elif [[ $days_left -le $WARNING_DAYS ]]; then
        send_alert "WARNING" "Certificate for $DOMAIN expires in $days_left days. Renewal recommended." "$days_left"
        return 1
    else
        log_message "INFO" "Certificate for $DOMAIN is valid for $days_left more days"
        return 0
    fi
}

# Health check function for container health checks
health_check() {
    if check_cert_exists; then
        local expiry_date=$(get_cert_expiration)
        local days_left=$(days_until_expiration "$expiry_date")
        
        if [[ $days_left -le 0 ]]; then
            echo "UNHEALTHY: Certificate expired"
            return 1
        elif [[ $days_left -le $CRITICAL_DAYS ]]; then
            echo "UNHEALTHY: Certificate expires in $days_left days"
            return 1
        else
            echo "HEALTHY: Certificate valid for $days_left days"
            return 0
        fi
    else
        echo "UNHEALTHY: Certificate not found"
        return 1
    fi
}

# JSON status output for monitoring systems
json_status() {
    local status="unknown"
    local days_left="N/A"
    local expiry_date="N/A"
    local message="Certificate status unknown"
    
    if check_cert_exists; then
        expiry_date=$(get_cert_expiration)
        days_left=$(days_until_expiration "$expiry_date")
        
        if [[ $days_left -le 0 ]]; then
            status="expired"
            message="Certificate has expired"
        elif [[ $days_left -le $CRITICAL_DAYS ]]; then
            status="critical"
            message="Certificate expires soon"
        elif [[ $days_left -le $WARNING_DAYS ]]; then
            status="warning"
            message="Certificate renewal recommended"
        else
            status="healthy"
            message="Certificate is valid"
        fi
    else
        status="missing"
        message="Certificate file not found"
    fi
    
    cat <<EOF
{
    "domain": "$DOMAIN",
    "status": "$status",
    "days_until_expiration": $days_left,
    "expiry_date": "$expiry_date",
    "message": "$message",
    "timestamp": "$(date -Iseconds)",
    "warning_threshold": $WARNING_DAYS,
    "critical_threshold": $CRITICAL_DAYS
}
EOF
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
    monitor     Run certificate expiration monitoring (default)
    info        Display certificate information
    health      Check certificate health (for container health checks)
    json        Output status in JSON format
    help        Show this help message

Environment Variables:
    DOMAIN              Domain to monitor (default: colakdo.com)
    CERT_PATH           Path to certificate directory
    LOG_FILE            Log file path
    WARNING_DAYS        Warning threshold in days (default: 30)
    CRITICAL_DAYS       Critical threshold in days (default: 7)
    ALERT_EMAIL         Email address for alerts
    WEBHOOK_URL         Webhook URL for notifications

Examples:
    $0 monitor          # Run monitoring check
    $0 info             # Show certificate details
    $0 health           # Health check for containers
    $0 json             # JSON status output
EOF
}

# Main script logic
main() {
    local command="${1:-monitor}"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$command" in
        monitor)
            monitor_certificate
            ;;
        info)
            get_cert_info
            ;;
        health)
            health_check
            ;;
        json)
            json_status
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"