#!/bin/bash

# Enhanced Certificate Renewal System for HAProxy Wildcard SSL
# Implements automated renewal with retry logic, exponential backoff, and comprehensive logging

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
EMAIL="${EMAIL:-}"
DNS_PLUGIN="${DNS_PLUGIN:-dns-cloudflare}"
CREDENTIALS_FILE="/etc/letsencrypt/dns-credentials/${DNS_PLUGIN#dns-}.ini"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"
LOG_FILE="/var/log/letsencrypt/renewal.log"
ERROR_LOG="/var/log/letsencrypt/renewal-errors.log"
RENEWAL_LOG="/var/log/letsencrypt/renewal-history.log"

# Retry configuration
MAX_RETRIES=5
INITIAL_RETRY_DELAY=300  # 5 minutes
MAX_RETRY_DELAY=3600     # 1 hour
BACKOFF_MULTIPLIER=2

# Renewal thresholds
RENEWAL_THRESHOLD_DAYS=30  # Renew if certificate expires within 30 days
FORCE_RENEWAL_DAYS=7       # Force renewal if certificate expires within 7 days

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Also log to specific files based on level
    case "$level" in
        "ERROR")
            echo "[$timestamp] $message" >> "$ERROR_LOG"
            ;;
        "RENEWAL")
            echo "[$timestamp] $message" >> "$RENEWAL_LOG"
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_renewal() {
    log "RENEWAL" "$@"
}

# Error handling with context
handle_error() {
    local exit_code=$?
    local context="${1:-Unknown error}"
    log_error "Command failed with exit code $exit_code: $context"
    return $exit_code
}

# Initialize logging directories
init_logging() {
    local log_dirs=(
        "$(dirname "$LOG_FILE")"
        "$(dirname "$ERROR_LOG")"
        "$(dirname "$RENEWAL_LOG")"
    )
    
    for dir in "${log_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Set appropriate permissions
    chmod 755 "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" "$ERROR_LOG" "$RENEWAL_LOG"
    chmod 644 "$LOG_FILE" "$ERROR_LOG" "$RENEWAL_LOG"
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating renewal environment..."
    
    # Check required environment variables
    if [[ -z "$EMAIL" ]]; then
        handle_error "EMAIL environment variable is required for certificate renewal"
        return 1
    fi
    
    # Check DNS credentials file
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        handle_error "DNS credentials file not found: $CREDENTIALS_FILE"
        return 1
    fi
    
    # Verify credentials file permissions
    local perms=$(stat -c "%a" "$CREDENTIALS_FILE" 2>/dev/null || echo "000")
    if [[ "$perms" != "600" ]]; then
        log_warn "DNS credentials file has permissions $perms, should be 600"
        chmod 600 "$CREDENTIALS_FILE" || handle_error "Failed to set credentials file permissions"
    fi
    
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1; then
        handle_error "Certbot command not found"
        return 1
    fi
    
    log_info "Environment validation completed successfully"
    return 0
}

# Check certificate expiration status
check_certificate_expiration() {
    local cert_file="$CERT_PATH/fullchain.pem"
    
    if [[ ! -f "$cert_file" ]]; then
        log_warn "Certificate file not found: $cert_file"
        return 2  # Certificate missing
    fi
    
    # Get certificate expiration date
    local expiry_date
    if ! expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2); then
        log_error "Failed to read certificate expiration date"
        return 1
    fi
    
    # Convert to epoch time
    local expiry_epoch
    if ! expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null); then
        log_error "Failed to parse certificate expiration date: $expiry_date"
        return 1
    fi
    
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_info "Certificate expires in $days_until_expiry days ($expiry_date)"
    
    # Return status based on expiration threshold
    if [[ $days_until_expiry -le $FORCE_RENEWAL_DAYS ]]; then
        log_warn "Certificate expires within $FORCE_RENEWAL_DAYS days - FORCE RENEWAL REQUIRED"
        return 3  # Force renewal
    elif [[ $days_until_expiry -le $RENEWAL_THRESHOLD_DAYS ]]; then
        log_info "Certificate expires within $RENEWAL_THRESHOLD_DAYS days - renewal recommended"
        return 4  # Renewal recommended
    else
        log_info "Certificate is valid for $days_until_expiry days - no renewal needed"
        return 0  # No renewal needed
    fi
}

# Execute certificate renewal with retry logic
execute_renewal() {
    local force_renewal="${1:-false}"
    local retry_count=0
    local retry_delay=$INITIAL_RETRY_DELAY
    
    log_renewal "Starting certificate renewal process (force: $force_renewal)"
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        local attempt=$((retry_count + 1))
        log_info "Renewal attempt $attempt/$MAX_RETRIES"
        
        # Build certbot renewal command
        local renewal_cmd=(
            "certbot" "renew"
            "--${DNS_PLUGIN}"
            "--${DNS_PLUGIN}-credentials" "$CREDENTIALS_FILE"
            "--non-interactive"
            "--quiet"
            "--no-random-sleep-on-renew"
        )
        
        # Add force renewal flag if needed
        if [[ "$force_renewal" == "true" ]]; then
            renewal_cmd+=("--force-renewal")
            log_info "Force renewal enabled"
        fi
        
        # Add post-hook for certificate combination
        renewal_cmd+=("--post-hook" "/scripts/combine-certs.sh")
        
        log_info "Executing renewal command: ${renewal_cmd[*]}"
        
        # Execute renewal with timeout
        local renewal_start=$(date +%s)
        if timeout 1800 "${renewal_cmd[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            local renewal_end=$(date +%s)
            local renewal_duration=$((renewal_end - renewal_start))
            
            log_renewal "Certificate renewal completed successfully in ${renewal_duration}s"
            
            # Verify the renewed certificate
            if verify_renewed_certificate; then
                log_renewal "Certificate verification successful"
                return 0
            else
                log_error "Certificate verification failed after renewal"
                retry_count=$((retry_count + 1))
            fi
        else
            local exit_code=$?
            log_error "Certificate renewal failed with exit code $exit_code (attempt $attempt/$MAX_RETRIES)"
            retry_count=$((retry_count + 1))
        fi
        
        # Apply exponential backoff if more retries are available
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log_info "Waiting ${retry_delay}s before retry (exponential backoff)..."
            sleep $retry_delay
            
            # Calculate next retry delay with cap
            retry_delay=$((retry_delay * BACKOFF_MULTIPLIER))
            if [[ $retry_delay -gt $MAX_RETRY_DELAY ]]; then
                retry_delay=$MAX_RETRY_DELAY
            fi
        fi
    done
    
    log_error "Certificate renewal failed after $MAX_RETRIES attempts"
    log_renewal "RENEWAL FAILED - Manual intervention required"
    return 1
}

# Verify renewed certificate
verify_renewed_certificate() {
    local cert_file="$CERT_PATH/fullchain.pem"
    local combined_cert="/etc/ssl/certs/live/${DOMAIN}/combined.pem"
    
    log_info "Verifying renewed certificate..."
    
    # Check if certificate file exists and is readable
    if [[ ! -f "$cert_file" ]] || [[ ! -r "$cert_file" ]]; then
        log_error "Certificate file not found or not readable: $cert_file"
        return 1
    fi
    
    # Verify certificate validity
    if ! openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
        log_error "Renewed certificate is invalid or expired"
        return 1
    fi
    
    # Check if combined certificate exists (created by post-hook)
    if [[ ! -f "$combined_cert" ]]; then
        log_error "Combined certificate not found: $combined_cert"
        return 1
    fi
    
    # Verify combined certificate
    if ! openssl x509 -in "$combined_cert" -noout -checkend 0 >/dev/null 2>&1; then
        log_error "Combined certificate is invalid"
        return 1
    fi
    
    # Get certificate details
    local subject
    local expiry_date
    subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    
    log_info "Certificate verification successful:"
    log_info "  Subject: $subject"
    log_info "  Expires: $expiry_date"
    
    return 0
}

# Reload HAProxy configuration with enhanced error handling
reload_haproxy() {
    log_info "Reloading HAProxy configuration..."
    
    local reload_success=false
    local reload_methods=()
    
    # Method 1: Direct process signal (if running on same system)
    if pgrep haproxy >/dev/null 2>&1; then
        reload_methods+=("process_signal")
    fi
    
    # Method 2: Docker container signal (if running in Docker)
    if command -v docker >/dev/null 2>&1 && docker ps --format "{{.Names}}" | grep -q "haproxy-proxy"; then
        reload_methods+=("docker_signal")
    fi
    
    # Method 3: Docker Compose restart (fallback)
    if command -v docker-compose >/dev/null 2>&1 && [[ -f "docker-compose.yml" ]]; then
        reload_methods+=("docker_compose")
    fi
    
    # Try each reload method
    for method in "${reload_methods[@]}"; do
        log_info "Attempting HAProxy reload using method: $method"
        
        case "$method" in
            "process_signal")
                if pkill -HUP haproxy 2>/dev/null; then
                    log_info "HAProxy reloaded successfully via process signal"
                    reload_success=true
                    break
                else
                    log_warn "Failed to reload HAProxy via process signal"
                fi
                ;;
            "docker_signal")
                if docker kill --signal=HUP haproxy-proxy 2>/dev/null; then
                    log_info "HAProxy reloaded successfully via Docker signal"
                    reload_success=true
                    break
                else
                    log_warn "Failed to reload HAProxy via Docker signal"
                fi
                ;;
            "docker_compose")
                if docker-compose restart haproxy 2>/dev/null; then
                    log_info "HAProxy restarted successfully via Docker Compose"
                    reload_success=true
                    break
                else
                    log_warn "Failed to restart HAProxy via Docker Compose"
                fi
                ;;
        esac
    done
    
    if $reload_success; then
        log_renewal "HAProxy configuration reloaded successfully"
        
        # Wait a moment and verify HAProxy is responding
        sleep 5
        if verify_haproxy_health; then
            log_info "HAProxy health check passed after reload"
        else
            log_warn "HAProxy health check failed after reload"
        fi
    else
        log_error "Failed to reload HAProxy configuration using all available methods"
        log_error "Manual HAProxy restart may be required"
        return 1
    fi
    
    return 0
}

# Verify HAProxy health after reload
verify_haproxy_health() {
    local health_check_url="http://localhost:8404/stats"
    
    # Try to connect to HAProxy stats endpoint
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 10 "$health_check_url" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=10 --tries=1 -O /dev/null "$health_check_url" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Fallback: check if HAProxy process is running
    if pgrep haproxy >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Main renewal function
perform_renewal() {
    local force_renewal="${1:-false}"
    
    log_renewal "=== Certificate Renewal Process Started ==="
    log_info "Domain: $DOMAIN"
    log_info "DNS Plugin: $DNS_PLUGIN"
    log_info "Force Renewal: $force_renewal"
    
    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        return 1
    fi
    
    # Check certificate expiration status
    local cert_status
    check_certificate_expiration
    cert_status=$?
    
    case $cert_status in
        0)
            if [[ "$force_renewal" != "true" ]]; then
                log_info "Certificate is valid and not due for renewal"
                log_renewal "=== Renewal Process Completed (No Action Required) ==="
                return 0
            else
                log_info "Force renewal requested despite valid certificate"
            fi
            ;;
        2)
            log_warn "Certificate missing - renewal required"
            force_renewal="true"
            ;;
        3)
            log_warn "Certificate expires soon - force renewal required"
            force_renewal="true"
            ;;
        4)
            log_info "Certificate renewal recommended"
            ;;
        *)
            log_error "Failed to check certificate status"
            return 1
            ;;
    esac
    
    # Execute renewal
    if execute_renewal "$force_renewal"; then
        log_renewal "Certificate renewal successful"
        
        # Reload HAProxy configuration
        if reload_haproxy; then
            log_renewal "HAProxy configuration reloaded successfully"
        else
            log_error "Failed to reload HAProxy configuration"
            # Don't fail the entire process if reload fails
        fi
        
        log_renewal "=== Certificate Renewal Process Completed Successfully ==="
        return 0
    else
        log_error "Certificate renewal failed"
        log_renewal "=== Certificate Renewal Process Failed ==="
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up renewal process..."
}

# Signal handlers
trap cleanup EXIT
trap 'log_info "Received SIGTERM, shutting down..."; exit 0' TERM
trap 'log_info "Received SIGINT, shutting down..."; exit 0' INT

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Certificate Renewal System for HAProxy Wildcard SSL

OPTIONS:
    -f, --force     Force certificate renewal regardless of expiration date
    -h, --help      Show this help message
    -v, --verbose   Enable verbose logging

ENVIRONMENT VARIABLES:
    DOMAIN          Domain name (default: colakdo.com)
    EMAIL           Email for Let's Encrypt registration
    DNS_PLUGIN      DNS plugin for certbot (default: dns-cloudflare)

EXAMPLES:
    $0                  # Normal renewal check
    $0 --force          # Force renewal
    $0 --verbose        # Verbose logging

EOF
}

# Main execution
main() {
    local force_renewal=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_renewal=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    init_logging
    
    # Set verbose logging if requested
    if [[ "$verbose" == "true" ]]; then
        set -x
    fi
    
    # Perform renewal
    perform_renewal "$force_renewal"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi