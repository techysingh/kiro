#!/bin/bash
"""
Comprehensive Error Recovery Manager for HAProxy Stack
Handles service failures, certificate issues, and system recovery
"""

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/haproxy/error-recovery.log"
RECOVERY_STATE_FILE="/var/log/haproxy/recovery-state.json"
MAX_RECOVERY_ATTEMPTS=3
RECOVERY_COOLDOWN=300  # 5 minutes between recovery attempts
HEALTH_CHECK_TIMEOUT=30
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# Service definitions
declare -A SERVICES=(
    ["haproxy"]="haproxy-proxy"
    ["certbot"]="certbot-ssl"
    ["syslog"]="haproxy-syslog"
    ["monitor"]="haproxy-monitor"
    ["maintenance"]="haproxy-maintenance"
    ["backend-discovery"]="haproxy-backend-discovery"
    ["config-watcher"]="haproxy-config-watcher"
)

# Critical services that require immediate attention
CRITICAL_SERVICES=("haproxy" "certbot" "maintenance")

# Logging function with severity levels
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Also log to syslog if available
    if command -v logger >/dev/null 2>&1; then
        logger -t "error-recovery" -p "daemon.$level" "$message"
    fi
}

# Send alert notification
send_alert() {
    local severity="$1"
    local subject="$2"
    local message="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "info" "Sending $severity alert: $subject"
    
    # Email notification
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        {
            echo "Timestamp: $timestamp"
            echo "Severity: $severity"
            echo "Subject: $subject"
            echo ""
            echo "Details:"
            echo "$message"
            echo ""
            echo "System: $(hostname)"
            echo "Stack: HAProxy Wildcard SSL"
        } | mail -s "[$severity] HAProxy Stack Alert: $subject" "$ALERT_EMAIL"
        
        log "info" "Email alert sent to $ALERT_EMAIL"
    fi
    
    # Webhook notification
    if [[ -n "$WEBHOOK_URL" ]] && command -v curl >/dev/null 2>&1; then
        local payload
        payload=$(cat <<EOF
{
    "timestamp": "$timestamp",
    "severity": "$severity",
    "subject": "$subject",
    "message": "$message",
    "system": "$(hostname)",
    "stack": "HAProxy Wildcard SSL",
    "recovery_manager": true
}
EOF
        )
        
        if curl -s -X POST -H "Content-Type: application/json" \
           -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1; then
            log "info" "Webhook alert sent successfully"
        else
            log "error" "Failed to send webhook alert"
        fi
    fi
}

# Initialize recovery state file
init_recovery_state() {
    if [[ ! -f "$RECOVERY_STATE_FILE" ]]; then
        cat > "$RECOVERY_STATE_FILE" << 'EOF'
{
    "last_recovery": null,
    "recovery_attempts": {},
    "failed_services": [],
    "system_status": "healthy"
}
EOF
        log "info" "Initialized recovery state file"
    fi
}

# Update recovery state
update_recovery_state() {
    local service="$1"
    local status="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create a temporary file for atomic updates
    local temp_file
    temp_file=$(mktemp)
    
    # Update the state using jq if available, otherwise use basic approach
    if command -v jq >/dev/null 2>&1; then
        jq --arg service "$service" \
           --arg status "$status" \
           --arg timestamp "$timestamp" \
           '.last_recovery = $timestamp |
            .recovery_attempts[$service] = (.recovery_attempts[$service] // 0) + 1 |
            if $status == "failed" then
                .failed_services |= (. + [$service] | unique)
            else
                .failed_services |= (. - [$service])
            end |
            .system_status = (if (.failed_services | length) > 0 then "degraded" else "healthy" end)' \
           "$RECOVERY_STATE_FILE" > "$temp_file"
    else
        # Fallback without jq
        cp "$RECOVERY_STATE_FILE" "$temp_file"
    fi
    
    mv "$temp_file" "$RECOVERY_STATE_FILE"
    log "debug" "Updated recovery state for $service: $status"
}

# Check if service is healthy
check_service_health() {
    local service="$1"
    local container_name="${SERVICES[$service]}"
    
    log "debug" "Checking health of service: $service ($container_name)"
    
    # Check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        log "warn" "Container $container_name is not running"
        return 1
    fi
    
    # Check container health status if available
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    
    case "$health_status" in
        "healthy")
            log "debug" "Service $service is healthy"
            return 0
            ;;
        "unhealthy")
            log "warn" "Service $service is unhealthy"
            return 1
            ;;
        "starting")
            log "info" "Service $service is starting, waiting..."
            sleep 10
            return 2  # Retry
            ;;
        "none")
            log "debug" "Service $service has no health check, assuming healthy if running"
            return 0
            ;;
        *)
            log "warn" "Service $service has unknown health status: $health_status"
            return 1
            ;;
    esac
}

# Restart a service
restart_service() {
    local service="$1"
    local container_name="${SERVICES[$service]}"
    
    log "info" "Attempting to restart service: $service ($container_name)"
    
    # Try graceful restart first
    if docker restart "$container_name" >/dev/null 2>&1; then
        log "info" "Service $service restarted successfully"
        
        # Wait for service to become healthy
        local attempts=0
        while [[ $attempts -lt 6 ]]; do  # Wait up to 60 seconds
            sleep 10
            if check_service_health "$service"; then
                log "info" "Service $service is healthy after restart"
                update_recovery_state "$service" "recovered"
                return 0
            fi
            ((attempts++))
        done
        
        log "warn" "Service $service restarted but not healthy after 60 seconds"
        return 1
    else
        log "error" "Failed to restart service $service"
        return 1
    fi
}

# Recover certificate issues
recover_certificate_issues() {
    log "info" "Checking for certificate issues"
    
    local cert_file="/etc/ssl/certs/live/colakdo.com/fullchain.pem"
    local key_file="/etc/ssl/certs/live/colakdo.com/privkey.pem"
    
    # Check if certificate files exist
    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        log "error" "Certificate files missing, attempting emergency certificate generation"
        send_alert "critical" "SSL Certificate Missing" "Certificate files not found. Attempting emergency recovery."
        
        # Try to generate emergency self-signed certificate
        if generate_emergency_certificate; then
            log "info" "Emergency certificate generated successfully"
            restart_service "haproxy"
            return 0
        else
            log "error" "Failed to generate emergency certificate"
            return 1
        fi
    fi
    
    # Check certificate expiration
    local expiry_date
    if expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2); then
        local expiry_epoch
        local current_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_left -le 0 ]]; then
            log "error" "Certificate has expired, attempting renewal"
            send_alert "critical" "SSL Certificate Expired" "Certificate expired $((days_left * -1)) days ago. Attempting renewal."
            
            # Force certificate renewal
            if force_certificate_renewal; then
                log "info" "Certificate renewed successfully"
                restart_service "haproxy"
                return 0
            else
                log "error" "Failed to renew expired certificate"
                return 1
            fi
        elif [[ $days_left -le 7 ]]; then
            log "warn" "Certificate expires in $days_left days, attempting renewal"
            send_alert "warning" "SSL Certificate Expiring Soon" "Certificate expires in $days_left days. Attempting renewal."
            
            # Try to renew certificate
            if force_certificate_renewal; then
                log "info" "Certificate renewed proactively"
                restart_service "haproxy"
            else
                log "warn" "Failed to renew certificate proactively"
            fi
        fi
    else
        log "warn" "Could not determine certificate expiration date"
    fi
    
    return 0
}

# Generate emergency self-signed certificate
generate_emergency_certificate() {
    log "info" "Generating emergency self-signed certificate"
    
    local cert_dir="/etc/ssl/certs/live/colakdo.com"
    mkdir -p "$cert_dir"
    
    # Generate self-signed certificate valid for 30 days
    if openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$cert_dir/privkey.pem" \
        -out "$cert_dir/fullchain.pem" \
        -days 30 \
        -subj "/C=US/ST=Emergency/L=Recovery/O=HAProxy/CN=*.colakdo.com" \
        -extensions v3_req \
        -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Emergency
L = Recovery
O = HAProxy Emergency
CN = *.colakdo.com

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.colakdo.com
DNS.2 = colakdo.com
EOF
        ) >/dev/null 2>&1; then
        
        # Create combined certificate file
        cat "$cert_dir/fullchain.pem" "$cert_dir/privkey.pem" > "$cert_dir/combined.pem"
        
        # Set proper permissions
        chmod 600 "$cert_dir"/*.pem
        
        log "info" "Emergency certificate generated successfully"
        send_alert "warning" "Emergency Certificate Generated" "Self-signed certificate created for 30 days. Please resolve certificate issues."
        return 0
    else
        log "error" "Failed to generate emergency certificate"
        return 1
    fi
}

# Force certificate renewal
force_certificate_renewal() {
    log "info" "Forcing certificate renewal"
    
    # Try to run certbot renewal
    if docker exec certbot-ssl certbot renew --force-renewal >/dev/null 2>&1; then
        log "info" "Certificate renewal successful"
        
        # Update combined certificate
        if docker exec certbot-ssl sh -c '
            cd /etc/letsencrypt/live/colakdo.com &&
            cat fullchain.pem privkey.pem > combined.pem &&
            chmod 600 combined.pem
        ' >/dev/null 2>&1; then
            log "info" "Combined certificate updated"
            return 0
        else
            log "warn" "Failed to update combined certificate"
            return 1
        fi
    else
        log "error" "Certificate renewal failed"
        return 1
    fi
}

# Recover HAProxy configuration issues
recover_haproxy_config() {
    log "info" "Checking HAProxy configuration"
    
    # Validate current configuration
    if docker exec haproxy-proxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        log "debug" "HAProxy configuration is valid"
        return 0
    else
        log "error" "HAProxy configuration is invalid, attempting recovery"
        send_alert "critical" "HAProxy Configuration Invalid" "HAProxy configuration validation failed. Attempting recovery."
        
        # Try to restore from backup
        if [[ -f "/usr/local/etc/haproxy/haproxy.cfg.backup" ]]; then
            log "info" "Restoring HAProxy configuration from backup"
            
            if cp "/usr/local/etc/haproxy/haproxy.cfg.backup" "/usr/local/etc/haproxy/haproxy.cfg"; then
                # Validate restored configuration
                if docker exec haproxy-proxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
                    log "info" "Configuration restored from backup successfully"
                    restart_service "haproxy"
                    return 0
                else
                    log "error" "Backup configuration is also invalid"
                fi
            else
                log "error" "Failed to restore configuration from backup"
            fi
        fi
        
        # Generate minimal working configuration
        log "info" "Generating minimal working HAProxy configuration"
        if generate_minimal_haproxy_config; then
            log "info" "Minimal configuration generated"
            restart_service "haproxy"
            return 0
        else
            log "error" "Failed to generate minimal configuration"
            return 1
        fi
    fi
}

# Generate minimal working HAProxy configuration
generate_minimal_haproxy_config() {
    local config_file="/usr/local/etc/haproxy/haproxy.cfg"
    local backup_file="${config_file}.emergency"
    
    log "info" "Creating minimal HAProxy configuration"
    
    cat > "$backup_file" << 'EOF'
# Emergency HAProxy Configuration
# Generated by error recovery manager

global
    daemon
    user haproxy
    group haproxy
    log 127.0.0.1:514 local0 info

defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend emergency_frontend
    bind *:80
    bind *:443
    mode http
    
    # Return maintenance page for all requests
    http-request deny deny_status 503
    errorfile 503 /usr/local/etc/haproxy/errors/503.http

# Stats frontend
frontend stats_frontend
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    monitor-uri /health
EOF
    
    # Validate the minimal configuration
    if docker exec haproxy-proxy haproxy -c -f "$backup_file" >/dev/null 2>&1; then
        mv "$backup_file" "$config_file"
        log "info" "Minimal configuration is valid and activated"
        send_alert "warning" "Emergency Configuration Activated" "HAProxy is running with minimal emergency configuration. Please restore proper configuration."
        return 0
    else
        log "error" "Even minimal configuration is invalid"
        rm -f "$backup_file"
        return 1
    fi
}

# Perform comprehensive system recovery
perform_system_recovery() {
    log "info" "Starting comprehensive system recovery"
    
    local failed_services=()
    local recovery_success=true
    
    # Check all services
    for service in "${!SERVICES[@]}"; do
        local health_result
        if ! health_result=$(check_service_health "$service"); then
            if [[ $health_result -eq 2 ]]; then
                # Service is starting, wait and recheck
                sleep 15
                if ! check_service_health "$service"; then
                    failed_services+=("$service")
                fi
            else
                failed_services+=("$service")
            fi
        fi
    done
    
    # Report failed services
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log "warn" "Found ${#failed_services[@]} failed services: ${failed_services[*]}"
        send_alert "warning" "Service Failures Detected" "Failed services: ${failed_services[*]}"
        
        # Attempt recovery for each failed service
        for service in "${failed_services[@]}"; do
            log "info" "Attempting recovery for service: $service"
            
            # Check recovery attempts
            local attempts
            attempts=$(get_recovery_attempts "$service")
            
            if [[ $attempts -ge $MAX_RECOVERY_ATTEMPTS ]]; then
                log "error" "Service $service has exceeded maximum recovery attempts ($MAX_RECOVERY_ATTEMPTS)"
                send_alert "critical" "Service Recovery Failed" "Service $service has failed $attempts times and exceeded recovery limits."
                recovery_success=false
                continue
            fi
            
            # Attempt restart
            if restart_service "$service"; then
                log "info" "Successfully recovered service: $service"
            else
                log "error" "Failed to recover service: $service"
                update_recovery_state "$service" "failed"
                recovery_success=false
                
                # If it's a critical service, send immediate alert
                if [[ " ${CRITICAL_SERVICES[*]} " =~ " $service " ]]; then
                    send_alert "critical" "Critical Service Failure" "Critical service $service has failed and could not be recovered."
                fi
            fi
        done
    else
        log "info" "All services are healthy"
    fi
    
    # Perform specific recovery checks
    if ! recover_certificate_issues; then
        log "error" "Certificate recovery failed"
        recovery_success=false
    fi
    
    if ! recover_haproxy_config; then
        log "error" "HAProxy configuration recovery failed"
        recovery_success=false
    fi
    
    # Update system status
    if $recovery_success; then
        log "info" "System recovery completed successfully"
        update_recovery_state "system" "healthy"
    else
        log "error" "System recovery completed with errors"
        update_recovery_state "system" "degraded"
        send_alert "critical" "System Recovery Incomplete" "System recovery completed but some issues remain unresolved."
    fi
    
    return $([[ $recovery_success == true ]] && echo 0 || echo 1)
}

# Get recovery attempts for a service
get_recovery_attempts() {
    local service="$1"
    
    if command -v jq >/dev/null 2>&1 && [[ -f "$RECOVERY_STATE_FILE" ]]; then
        jq -r --arg service "$service" '.recovery_attempts[$service] // 0' "$RECOVERY_STATE_FILE"
    else
        echo "0"
    fi
}

# Check if recovery is in cooldown period
is_recovery_in_cooldown() {
    if [[ ! -f "$RECOVERY_STATE_FILE" ]]; then
        return 1  # No cooldown if no state file
    fi
    
    local last_recovery
    if command -v jq >/dev/null 2>&1; then
        last_recovery=$(jq -r '.last_recovery // empty' "$RECOVERY_STATE_FILE")
    else
        return 1  # No cooldown if jq not available
    fi
    
    if [[ -z "$last_recovery" || "$last_recovery" == "null" ]]; then
        return 1  # No previous recovery
    fi
    
    local last_recovery_epoch
    local current_epoch
    last_recovery_epoch=$(date -d "$last_recovery" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    local time_diff=$((current_epoch - last_recovery_epoch))
    
    if [[ $time_diff -lt $RECOVERY_COOLDOWN ]]; then
        log "info" "Recovery is in cooldown period (${time_diff}s < ${RECOVERY_COOLDOWN}s)"
        return 0  # In cooldown
    else
        return 1  # Not in cooldown
    fi
}

# Main recovery function
main() {
    log "info" "Error Recovery Manager started"
    
    # Initialize recovery state
    init_recovery_state
    
    # Check if we're in cooldown period
    if is_recovery_in_cooldown; then
        log "info" "Skipping recovery due to cooldown period"
        exit 0
    fi
    
    # Perform system recovery
    if perform_system_recovery; then
        log "info" "System recovery completed successfully"
        exit 0
    else
        log "error" "System recovery completed with errors"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --check-only)
        # Only check service health, don't perform recovery
        log "info" "Performing health check only"
        failed_count=0
        for service in "${!SERVICES[@]}"; do
            if ! check_service_health "$service"; then
                ((failed_count++))
            fi
        done
        
        if [[ $failed_count -eq 0 ]]; then
            log "info" "All services are healthy"
            exit 0
        else
            log "warn" "$failed_count services are unhealthy"
            exit 1
        fi
        ;;
    --force)
        # Force recovery even if in cooldown
        log "info" "Forcing recovery (ignoring cooldown)"
        init_recovery_state
        if perform_system_recovery; then
            exit 0
        else
            exit 1
        fi
        ;;
    --status)
        # Show current system status
        if [[ -f "$RECOVERY_STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
            echo "System Status:"
            jq '.' "$RECOVERY_STATE_FILE"
        else
            echo "No status information available"
        fi
        exit 0
        ;;
    --help|-h)
        cat << 'EOF'
Error Recovery Manager for HAProxy Stack

Usage: error-recovery-manager.sh [OPTIONS]

Options:
    --check-only    Only check service health, don't perform recovery
    --force         Force recovery even if in cooldown period
    --status        Show current system status
    --help, -h      Show this help message

Environment Variables:
    ALERT_EMAIL     Email address for critical alerts
    WEBHOOK_URL     Webhook URL for notifications
    LOG_FILE        Log file path (default: /var/log/haproxy/error-recovery.log)

The script automatically:
- Monitors all HAProxy stack services
- Restarts failed services
- Recovers from certificate issues
- Fixes HAProxy configuration problems
- Sends alerts for critical issues
- Maintains recovery state and cooldown periods

EOF
        exit 0
        ;;
    *)
        main
        ;;
esac