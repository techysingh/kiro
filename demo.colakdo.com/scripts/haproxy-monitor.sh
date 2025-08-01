#!/bin/bash
"""
HAProxy Backend Health Monitoring Script
Monitors backend health, provides alerts, and manages failover
"""

set -euo pipefail

# Configuration
STATS_URL="http://localhost:8404/stats"
STATS_CSV_URL="http://localhost:8404/stats;csv"
LOG_FILE="/var/log/haproxy/monitor.log"
ALERT_THRESHOLD=2  # Number of failed backends before alert
CHECK_INTERVAL=30  # Seconds between checks

# Logging function
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

# Check if HAProxy stats are accessible
check_stats_access() {
    if curl -s --max-time 5 "$STATS_URL" >/dev/null 2>&1; then
        return 0
    else
        log "ERROR: Cannot access HAProxy stats at $STATS_URL"
        return 1
    fi
}

# Get backend status from HAProxy stats
get_backend_status() {
    local csv_data
    csv_data=$(curl -s --max-time 10 "$STATS_CSV_URL" 2>/dev/null || echo "")
    
    if [[ -z "$csv_data" ]]; then
        log "ERROR: Failed to retrieve HAProxy stats CSV data"
        return 1
    fi
    
    # Parse CSV data for backend information
    # Format: pxname,svname,qcur,qmax,scur,smax,slim,stot,bin,bout,dreq,dresp,ereq,econ,eresp,wretr,wredis,status,weight,act,bck,chkfail,chkdown,lastchg,downtime,qlimit,pid,iid,sid,throttle,lbtot,tracked,type,rate,rate_lim,rate_max,check_status,check_code,check_duration,hrsp_1xx,hrsp_2xx,hrsp_3xx,hrsp_4xx,hrsp_5xx,hrsp_other,hanafail,req_rate,req_rate_max,req_tot,cli_abrt,srv_abrt,comp_in,comp_out,comp_byp,comp_rsp,lastsess,last_chk,last_agt,qtime,ctime,rtime,ttime
    
    echo "$csv_data" | awk -F',' '
    NR > 1 && $2 != "BACKEND" && $2 != "FRONTEND" {
        backend = $1
        server = $2
        status = $18
        weight = $19
        active = $20
        backup = $21
        check_status = $37
        check_code = $38
        last_check = $50
        
        if (server != "" && server != "BACKEND" && server != "FRONTEND") {
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", backend, server, status, weight, active, backup, check_status, check_code, last_check
        }
    }'
}

# Analyze backend health
analyze_backend_health() {
    local status_data="$1"
    local total_backends=0
    local healthy_backends=0
    local unhealthy_backends=0
    local backup_active=0
    
    declare -A backend_health
    declare -A backend_issues
    
    while IFS=',' read -r backend server status weight active backup check_status check_code last_check; do
        if [[ -n "$backend" && -n "$server" ]]; then
            total_backends=$((total_backends + 1))
            
            # Analyze server status
            case "$status" in
                "UP")
                    healthy_backends=$((healthy_backends + 1))
                    backend_health["$backend,$server"]="HEALTHY"
                    ;;
                "DOWN")
                    unhealthy_backends=$((unhealthy_backends + 1))
                    backend_health["$backend,$server"]="DOWN"
                    backend_issues["$backend,$server"]="Server is DOWN - Check: $check_status ($check_code)"
                    ;;
                "NOLB")
                    backend_health["$backend,$server"]="NO_LOAD_BALANCE"
                    backend_issues["$backend,$server"]="Server not participating in load balancing"
                    ;;
                "MAINT")
                    backend_health["$backend,$server"]="MAINTENANCE"
                    ;;
                *)
                    backend_health["$backend,$server"]="UNKNOWN"
                    backend_issues["$backend,$server"]="Unknown status: $status"
                    ;;
            esac
            
            # Check if backup server is active
            if [[ "$backup" == "1" && "$status" == "UP" ]]; then
                backup_active=$((backup_active + 1))
            fi
        fi
    done <<< "$status_data"
    
    # Generate health report
    log "=== Backend Health Report ==="
    log "Total backends: $total_backends"
    log "Healthy backends: $healthy_backends"
    log "Unhealthy backends: $unhealthy_backends"
    log "Backup servers active: $backup_active"
    
    # Report individual backend status
    for key in "${!backend_health[@]}"; do
        IFS=',' read -r backend server <<< "$key"
        local health="${backend_health[$key]}"
        
        if [[ "$health" != "HEALTHY" ]]; then
            local issue="${backend_issues[$key]:-No specific issue}"
            log "ISSUE: $backend/$server - Status: $health - $issue"
        fi
    done
    
    # Check for critical conditions
    if [[ $unhealthy_backends -ge $ALERT_THRESHOLD ]]; then
        log "ALERT: $unhealthy_backends backends are unhealthy (threshold: $ALERT_THRESHOLD)"
        send_alert "HIGH" "$unhealthy_backends backends are unhealthy"
    fi
    
    if [[ $backup_active -gt 0 ]]; then
        log "WARNING: $backup_active backup servers are active (primary servers may be down)"
        send_alert "MEDIUM" "$backup_active backup servers are active"
    fi
    
    if [[ $healthy_backends -eq 0 && $total_backends -gt 0 ]]; then
        log "CRITICAL: No healthy backends available!"
        send_alert "CRITICAL" "No healthy backends available"
    fi
}

# Send alert and trigger recovery if needed
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log alert
    log "ALERT [$severity]: $message"
    
    # Write to alert log file
    echo "[$timestamp] [$severity] $message" >> "/var/log/haproxy/alerts.log"
    
    # Email notification
    if [[ -n "${ALERT_EMAIL:-}" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "[$severity] HAProxy Alert - $(hostname)" "$ALERT_EMAIL"
        log "Email alert sent to $ALERT_EMAIL"
    fi
    
    # Webhook notification
    if [[ -n "${WEBHOOK_URL:-}" ]]; then
        local payload=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "severity": "$severity",
    "message": "$message",
    "hostname": "$(hostname)",
    "service": "haproxy-monitor",
    "alert_type": "backend_health"
}
EOF
        )
        
        if curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1; then
            log "Webhook alert sent successfully"
        else
            log "Failed to send webhook alert"
        fi
    fi
    
    # Trigger error recovery for critical alerts
    if [[ "$severity" == "CRITICAL" ]]; then
        log "Triggering error recovery due to critical alert"
        if [[ -x "/scripts/error-recovery-manager.sh" ]]; then
            /scripts/error-recovery-manager.sh --force &
            log "Error recovery manager triggered"
        else
            log "Error recovery manager not found or not executable"
        fi
    fi
}

# Get HAProxy process information
get_haproxy_info() {
    local haproxy_pid
    haproxy_pid=$(pgrep -f "haproxy.*master" || echo "")
    
    if [[ -n "$haproxy_pid" ]]; then
        local cpu_usage
        local memory_usage
        cpu_usage=$(ps -p "$haproxy_pid" -o %cpu --no-headers 2>/dev/null || echo "N/A")
        memory_usage=$(ps -p "$haproxy_pid" -o %mem --no-headers 2>/dev/null || echo "N/A")
        
        log "HAProxy Process Info - PID: $haproxy_pid, CPU: ${cpu_usage}%, Memory: ${memory_usage}%"
    else
        log "WARNING: HAProxy master process not found"
        send_alert "HIGH" "HAProxy master process not found"
    fi
}

# Check certificate expiration
check_certificate_expiration() {
    local cert_file="/etc/ssl/certs/live/colakdo.com/fullchain.pem"
    
    if [[ -f "$cert_file" ]]; then
        local expiry_date
        local days_until_expiry
        
        expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
        
        if [[ -n "$expiry_date" ]]; then
            local expiry_epoch
            local current_epoch
            expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            current_epoch=$(date +%s)
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            log "SSL Certificate expires in $days_until_expiry days ($expiry_date)"
            
            if [[ $days_until_expiry -le 7 ]]; then
                send_alert "CRITICAL" "SSL certificate expires in $days_until_expiry days"
            elif [[ $days_until_expiry -le 30 ]]; then
                send_alert "HIGH" "SSL certificate expires in $days_until_expiry days"
            fi
        else
            log "WARNING: Could not determine certificate expiration date"
        fi
    else
        log "WARNING: Certificate file not found: $cert_file"
        send_alert "HIGH" "SSL certificate file not found"
    fi
}

# Main monitoring function
main_monitor() {
    log "Starting HAProxy health monitoring"
    
    # Check HAProxy stats access
    if ! check_stats_access; then
        send_alert "CRITICAL" "Cannot access HAProxy stats interface"
        return 1
    fi
    
    # Get backend status
    local status_data
    if status_data=$(get_backend_status); then
        analyze_backend_health "$status_data"
    else
        log "ERROR: Failed to get backend status"
        send_alert "HIGH" "Failed to retrieve backend status from HAProxy"
        return 1
    fi
    
    # Get HAProxy process information
    get_haproxy_info
    
    # Check certificate expiration
    check_certificate_expiration
    
    log "Health monitoring check completed"
}

# Continuous monitoring mode
continuous_monitor() {
    log "Starting continuous monitoring mode (interval: ${CHECK_INTERVAL}s)"
    
    while true; do
        main_monitor
        sleep "$CHECK_INTERVAL"
    done
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Handle script arguments
case "${1:-}" in
    --continuous)
        continuous_monitor
        ;;
    --once)
        main_monitor
        ;;
    --status-only)
        get_backend_status
        ;;
    --help|-h)
        echo "Usage: $0 [--continuous|--once|--status-only|--help]"
        echo "  --continuous: Run continuous monitoring"
        echo "  --once: Run single monitoring check"
        echo "  --status-only: Only show backend status"
        echo "  --help: Show this help message"
        ;;
    *)
        main_monitor
        ;;
esac