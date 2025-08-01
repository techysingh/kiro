#!/bin/bash
"""
Certificate Fallback Manager
Handles certificate failures and provides fallback mechanisms
"""

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-colakdo.com}"
CERT_DIR="/etc/ssl/certs/live/$DOMAIN"
BACKUP_CERT_DIR="/etc/ssl/certs/backup"
EMERGENCY_CERT_DIR="/etc/ssl/certs/emergency"
LOG_FILE="/var/log/haproxy/certificate-fallback.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# Certificate validity thresholds (in days)
CRITICAL_THRESHOLD=1
WARNING_THRESHOLD=7
RENEWAL_THRESHOLD=30

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Log to centralized error logger for critical issues
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" ]]; then
        if [[ -x "/scripts/error-logger.sh" ]]; then
            /scripts/error-logger.sh log "$level" "certificate-fallback" "$message"
        fi
    fi
}

# Send alert notification
send_alert() {
    local severity="$1"
    local subject="$2"
    local message="$3"
    
    log "info" "Sending $severity alert: $subject"
    
    # Use centralized error logger if available
    if [[ -x "/scripts/error-logger.sh" ]]; then
        /scripts/error-logger.sh log "$severity" "certificate-fallback" "$subject" "$message"
    fi
}

# Check certificate validity
check_certificate_validity() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        log "error" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Check if certificate is readable
    if ! openssl x509 -in "$cert_file" -noout >/dev/null 2>&1; then
        log "error" "Certificate file is not readable or corrupted: $cert_file"
        return 1
    fi
    
    # Check certificate expiration
    local expiry_date
    if ! expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2); then
        log "error" "Cannot determine certificate expiration date"
        return 1
    fi
    
    local expiry_epoch
    local current_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log "debug" "Certificate expires in $days_left days"
    
    if [[ $days_left -le 0 ]]; then
        log "critical" "Certificate has expired $((days_left * -1)) days ago"
        return 2  # Expired
    elif [[ $days_left -le $CRITICAL_THRESHOLD ]]; then
        log "critical" "Certificate expires in $days_left days (critical threshold: $CRITICAL_THRESHOLD)"
        return 3  # Critical
    elif [[ $days_left -le $WARNING_THRESHOLD ]]; then
        log "warning" "Certificate expires in $days_left days (warning threshold: $WARNING_THRESHOLD)"
        return 4  # Warning
    else
        log "debug" "Certificate is valid for $days_left days"
        return 0  # Valid
    fi
}

# Create backup of current certificate
create_certificate_backup() {
    local source_dir="$1"
    local backup_name="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    log "info" "Creating certificate backup: $backup_name"
    
    mkdir -p "$BACKUP_CERT_DIR"
    local backup_dir="$BACKUP_CERT_DIR/$backup_name"
    
    if cp -r "$source_dir" "$backup_dir" 2>/dev/null; then
        log "info" "Certificate backup created successfully: $backup_dir"
        
        # Keep only the last 10 backups
        find "$BACKUP_CERT_DIR" -maxdepth 1 -type d -name "20*" | \
            sort -r | tail -n +11 | xargs rm -rf 2>/dev/null || true
        
        return 0
    else
        log "error" "Failed to create certificate backup"
        return 1
    fi
}

# Restore certificate from backup
restore_certificate_from_backup() {
    local backup_name="$1"
    local backup_dir="$BACKUP_CERT_DIR/$backup_name"
    
    log "info" "Attempting to restore certificate from backup: $backup_name"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "error" "Backup directory not found: $backup_dir"
        return 1
    fi
    
    # Validate backup certificate before restoring
    local backup_cert="$backup_dir/fullchain.pem"
    if ! check_certificate_validity "$backup_cert"; then
        log "error" "Backup certificate is not valid: $backup_cert"
        return 1
    fi
    
    # Create backup of current state before restoring
    if [[ -d "$CERT_DIR" ]]; then
        create_certificate_backup "$CERT_DIR" "pre-restore-$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Restore from backup
    if cp -r "$backup_dir"/* "$CERT_DIR/" 2>/dev/null; then
        # Update combined certificate
        if create_combined_certificate; then
            log "info" "Certificate restored successfully from backup: $backup_name"
            send_alert "warning" "Certificate Restored from Backup" "Certificate restored from backup $backup_name due to issues with current certificate."
            return 0
        else
            log "error" "Failed to create combined certificate after restore"
            return 1
        fi
    else
        log "error" "Failed to restore certificate from backup"
        return 1
    fi
}

# Generate emergency self-signed certificate
generate_emergency_certificate() {
    log "info" "Generating emergency self-signed certificate"
    
    mkdir -p "$EMERGENCY_CERT_DIR"
    
    # Generate self-signed certificate valid for 30 days
    local temp_key="$EMERGENCY_CERT_DIR/privkey.pem"
    local temp_cert="$EMERGENCY_CERT_DIR/fullchain.pem"
    
    if openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$temp_key" \
        -out "$temp_cert" \
        -days 30 \
        -subj "/C=US/ST=Emergency/L=Recovery/O=HAProxy Emergency/CN=*.$DOMAIN" \
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
CN = *.$DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.$DOMAIN
DNS.2 = $DOMAIN
EOF
        ) >/dev/null 2>&1; then
        
        # Set proper permissions
        chmod 600 "$temp_key" "$temp_cert"
        
        log "info" "Emergency certificate generated successfully"
        return 0
    else
        log "error" "Failed to generate emergency certificate"
        return 1
    fi
}

# Deploy emergency certificate
deploy_emergency_certificate() {
    log "info" "Deploying emergency certificate"
    
    if [[ ! -f "$EMERGENCY_CERT_DIR/fullchain.pem" ]] || [[ ! -f "$EMERGENCY_CERT_DIR/privkey.pem" ]]; then
        if ! generate_emergency_certificate; then
            log "error" "Cannot generate emergency certificate"
            return 1
        fi
    fi
    
    # Create backup of current certificate if it exists
    if [[ -d "$CERT_DIR" ]]; then
        create_certificate_backup "$CERT_DIR" "pre-emergency-$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Deploy emergency certificate
    mkdir -p "$CERT_DIR"
    if cp "$EMERGENCY_CERT_DIR"/* "$CERT_DIR/" 2>/dev/null; then
        # Create combined certificate
        if create_combined_certificate; then
            log "info" "Emergency certificate deployed successfully"
            send_alert "critical" "Emergency Certificate Deployed" "Self-signed emergency certificate deployed due to certificate failure. Valid for 30 days. Please resolve certificate issues immediately."
            return 0
        else
            log "error" "Failed to create combined certificate for emergency cert"
            return 1
        fi
    else
        log "error" "Failed to deploy emergency certificate"
        return 1
    fi
}

# Create combined certificate file
create_combined_certificate() {
    local cert_file="$CERT_DIR/fullchain.pem"
    local key_file="$CERT_DIR/privkey.pem"
    local combined_file="$CERT_DIR/combined.pem"
    
    if [[ -f "$cert_file" ]] && [[ -f "$key_file" ]]; then
        if cat "$cert_file" "$key_file" > "$combined_file" 2>/dev/null; then
            chmod 600 "$combined_file"
            log "debug" "Combined certificate created successfully"
            return 0
        else
            log "error" "Failed to create combined certificate"
            return 1
        fi
    else
        log "error" "Certificate or key file missing for combined certificate"
        return 1
    fi
}

# Attempt certificate renewal
attempt_certificate_renewal() {
    log "info" "Attempting certificate renewal"
    
    # Try to renew using certbot
    if docker exec certbot-ssl certbot renew --force-renewal >/dev/null 2>&1; then
        log "info" "Certificate renewal successful"
        
        # Update combined certificate
        if create_combined_certificate; then
            log "info" "Combined certificate updated after renewal"
            send_alert "info" "Certificate Renewed Successfully" "Certificate for $DOMAIN has been renewed successfully."
            return 0
        else
            log "warning" "Certificate renewed but failed to update combined certificate"
            return 1
        fi
    else
        log "error" "Certificate renewal failed"
        return 1
    fi
}

# Find best available backup
find_best_backup() {
    log "info" "Searching for best available backup certificate"
    
    if [[ ! -d "$BACKUP_CERT_DIR" ]]; then
        log "warning" "No backup directory found"
        return 1
    fi
    
    local best_backup=""
    local best_days=-1
    
    # Check all backups
    for backup_dir in "$BACKUP_CERT_DIR"/*/; do
        if [[ -d "$backup_dir" ]]; then
            local backup_cert="$backup_dir/fullchain.pem"
            if [[ -f "$backup_cert" ]]; then
                # Check validity
                local validity_result
                if validity_result=$(check_certificate_validity "$backup_cert"); then
                    local expiry_date
                    expiry_date=$(openssl x509 -in "$backup_cert" -noout -enddate 2>/dev/null | cut -d= -f2)
                    local expiry_epoch
                    local current_epoch
                    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
                    current_epoch=$(date +%s)
                    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                    
                    if [[ $days_left -gt $best_days ]]; then
                        best_backup=$(basename "$backup_dir")
                        best_days=$days_left
                    fi
                fi
            fi
        fi
    done
    
    if [[ -n "$best_backup" ]]; then
        log "info" "Best backup found: $best_backup (valid for $best_days days)"
        echo "$best_backup"
        return 0
    else
        log "warning" "No valid backup certificates found"
        return 1
    fi
}

# Comprehensive certificate recovery
perform_certificate_recovery() {
    log "info" "Starting comprehensive certificate recovery"
    
    local recovery_success=false
    
    # Step 1: Try certificate renewal
    log "info" "Step 1: Attempting certificate renewal"
    if attempt_certificate_renewal; then
        log "info" "Certificate renewal successful"
        recovery_success=true
    else
        log "warning" "Certificate renewal failed, trying backup restore"
        
        # Step 2: Try to restore from backup
        log "info" "Step 2: Attempting backup restore"
        local best_backup
        if best_backup=$(find_best_backup); then
            if restore_certificate_from_backup "$best_backup"; then
                log "info" "Certificate restored from backup successfully"
                recovery_success=true
            else
                log "error" "Failed to restore from backup"
            fi
        else
            log "warning" "No suitable backup found"
        fi
        
        # Step 3: Deploy emergency certificate as last resort
        if ! $recovery_success; then
            log "info" "Step 3: Deploying emergency certificate as last resort"
            if deploy_emergency_certificate; then
                log "info" "Emergency certificate deployed successfully"
                recovery_success=true
            else
                log "error" "Failed to deploy emergency certificate"
            fi
        fi
    fi
    
    # Step 4: Restart HAProxy if recovery was successful
    if $recovery_success; then
        log "info" "Certificate recovery successful, restarting HAProxy"
        if docker restart haproxy-proxy >/dev/null 2>&1; then
            log "info" "HAProxy restarted successfully"
            
            # Wait for HAProxy to become healthy
            local attempts=0
            while [[ $attempts -lt 12 ]]; do  # Wait up to 60 seconds
                sleep 5
                if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
                    log "info" "HAProxy is healthy after certificate recovery"
                    return 0
                fi
                ((attempts++))
            done
            
            log "warning" "HAProxy restarted but health check failed"
            return 1
        else
            log "error" "Failed to restart HAProxy after certificate recovery"
            return 1
        fi
    else
        log "error" "Certificate recovery failed completely"
        send_alert "emergency" "Certificate Recovery Failed" "All certificate recovery attempts have failed. Manual intervention required immediately."
        return 1
    fi
}

# Monitor certificate and trigger recovery if needed
monitor_and_recover() {
    log "info" "Starting certificate monitoring and recovery"
    
    local cert_file="$CERT_DIR/fullchain.pem"
    local recovery_needed=false
    local recovery_reason=""
    
    # Check if certificate exists
    if [[ ! -f "$cert_file" ]]; then
        log "critical" "Certificate file missing: $cert_file"
        recovery_needed=true
        recovery_reason="Certificate file missing"
    else
        # Check certificate validity
        local validity_result
        validity_result=$(check_certificate_validity "$cert_file")
        local validity_code=$?
        
        case $validity_code in
            0)
                log "info" "Certificate is valid"
                ;;
            2)
                log "critical" "Certificate has expired"
                recovery_needed=true
                recovery_reason="Certificate expired"
                ;;
            3)
                log "critical" "Certificate expires within critical threshold"
                recovery_needed=true
                recovery_reason="Certificate expires soon (critical)"
                ;;
            4)
                log "warning" "Certificate expires within warning threshold"
                # Try renewal but don't force recovery
                attempt_certificate_renewal || true
                ;;
            *)
                log "error" "Certificate validation failed"
                recovery_needed=true
                recovery_reason="Certificate validation failed"
                ;;
        esac
    fi
    
    # Perform recovery if needed
    if $recovery_needed; then
        log "info" "Certificate recovery needed: $recovery_reason"
        send_alert "critical" "Certificate Recovery Initiated" "Certificate recovery initiated due to: $recovery_reason"
        
        if perform_certificate_recovery; then
            log "info" "Certificate recovery completed successfully"
            send_alert "info" "Certificate Recovery Successful" "Certificate recovery completed successfully."
            return 0
        else
            log "error" "Certificate recovery failed"
            return 1
        fi
    else
        log "info" "Certificate monitoring completed, no recovery needed"
        return 0
    fi
}

# List available backups
list_backups() {
    echo "Available certificate backups:"
    echo "=============================="
    
    if [[ ! -d "$BACKUP_CERT_DIR" ]]; then
        echo "No backup directory found"
        return 1
    fi
    
    local found_backups=false
    
    for backup_dir in "$BACKUP_CERT_DIR"/*/; do
        if [[ -d "$backup_dir" ]]; then
            local backup_name
            backup_name=$(basename "$backup_dir")
            local backup_cert="$backup_dir/fullchain.pem"
            
            if [[ -f "$backup_cert" ]]; then
                found_backups=true
                local status="INVALID"
                local days_left="N/A"
                
                if check_certificate_validity "$backup_cert" >/dev/null 2>&1; then
                    local expiry_date
                    expiry_date=$(openssl x509 -in "$backup_cert" -noout -enddate 2>/dev/null | cut -d= -f2)
                    local expiry_epoch
                    local current_epoch
                    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
                    current_epoch=$(date +%s)
                    days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                    
                    if [[ $days_left -gt 0 ]]; then
                        status="VALID"
                    else
                        status="EXPIRED"
                    fi
                fi
                
                printf "%-25s %-10s %s days\n" "$backup_name" "$status" "$days_left"
            fi
        fi
    done
    
    if ! $found_backups; then
        echo "No backups found"
        return 1
    fi
    
    return 0
}

# Main function
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_and_recover
            ;;
        "recover")
            perform_certificate_recovery
            ;;
        "backup")
            if [[ -d "$CERT_DIR" ]]; then
                create_certificate_backup "$CERT_DIR"
            else
                log "error" "No certificate directory to backup: $CERT_DIR"
                exit 1
            fi
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 restore <backup_name>"
                echo "Available backups:"
                list_backups
                exit 1
            fi
            restore_certificate_from_backup "$2"
            ;;
        "emergency")
            deploy_emergency_certificate
            ;;
        "list")
            list_backups
            ;;
        "renew")
            attempt_certificate_renewal
            ;;
        "status")
            local cert_file="$CERT_DIR/fullchain.pem"
            if [[ -f "$cert_file" ]]; then
                echo "Certificate Status for $DOMAIN:"
                echo "==============================="
                openssl x509 -in "$cert_file" -noout -subject -issuer -dates
                echo
                check_certificate_validity "$cert_file"
            else
                echo "No certificate found: $cert_file"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            cat << 'EOF'
Certificate Fallback Manager

Usage: certificate-fallback-manager.sh <command>

Commands:
    monitor     Monitor certificate and recover if needed (default)
    recover     Perform comprehensive certificate recovery
    backup      Create backup of current certificate
    restore     Restore certificate from backup
    emergency   Deploy emergency self-signed certificate
    list        List available certificate backups
    renew       Attempt certificate renewal
    status      Show current certificate status
    help        Show this help message

Environment Variables:
    DOMAIN          Domain name (default: colakdo.com)
    ALERT_EMAIL     Email address for alerts
    WEBHOOK_URL     Webhook URL for notifications

The script automatically:
- Monitors certificate validity
- Creates backups before changes
- Attempts renewal when needed
- Restores from backups if renewal fails
- Deploys emergency certificates as last resort
- Sends alerts for critical issues

EOF
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use 'certificate-fallback-manager.sh help' for usage information"
            exit 1
            ;;
    esac
}

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

main "$@"