#!/bin/bash

# Certbot Manager Script for Wildcard SSL Certificates
# Handles initial certificate generation and automated renewal

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
EMAIL="${EMAIL:-}"
DNS_PLUGIN="${DNS_PLUGIN:-dns-cloudflare}"
CREDENTIALS_FILE="/etc/letsencrypt/dns-credentials/${DNS_PLUGIN#dns-}.ini"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"
LOG_FILE="/var/log/letsencrypt/certbot.log"
MAX_RETRIES=3
RETRY_DELAY=300  # 5 minutes

# DNS Provider specific configurations
declare -A DNS_PROVIDERS=(
    ["dns-cloudflare"]="certbot/dns-cloudflare"
    ["dns-route53"]="certbot/dns-route53"
    ["dns-digitalocean"]="certbot/dns-digitalocean"
    ["dns-google"]="certbot/dns-google"
    ["dns-ovh"]="certbot/dns-ovh"
)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    log "ERROR: Command failed with exit code $exit_code"
    log "ERROR: $1"
    return $exit_code
}

# Validate environment and prerequisites
validate_environment() {
    log "Validating environment..."
    
    # Check required environment variables
    if [[ -z "$EMAIL" ]]; then
        handle_error "EMAIL environment variable is required"
        return 1
    fi
    
    # Validate DNS plugin
    if [[ -z "${DNS_PROVIDERS[$DNS_PLUGIN]:-}" ]]; then
        handle_error "Unsupported DNS plugin: $DNS_PLUGIN. Supported: ${!DNS_PROVIDERS[*]}"
        return 1
    fi
    
    # Check DNS credentials file exists
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        handle_error "DNS credentials file not found: $CREDENTIALS_FILE"
        log "Available credential files:"
        ls -la /etc/letsencrypt/dns-credentials/ || true
        return 1
    fi
    
    # Check credentials file permissions
    local perms=$(stat -c "%a" "$CREDENTIALS_FILE" 2>/dev/null || echo "000")
    if [[ "$perms" != "600" ]]; then
        log "WARNING: DNS credentials file has permissions $perms, should be 600"
        chmod 600 "$CREDENTIALS_FILE" || handle_error "Failed to set credentials file permissions"
    fi
    
    # Validate credentials file content
    if [[ ! -s "$CREDENTIALS_FILE" ]]; then
        handle_error "DNS credentials file is empty: $CREDENTIALS_FILE"
        return 1
    fi
    
    log "Environment validation completed successfully"
    log "Using DNS plugin: $DNS_PLUGIN"
    log "Credentials file: $CREDENTIALS_FILE"
}

# Install required packages
install_dependencies() {
    log "Installing dependencies..."
    apk add --no-cache openssl curl jq || handle_error "Failed to install dependencies"
    log "Dependencies installed successfully"
}

# Generate initial certificate with retry logic
generate_initial_certificate() {
    log "Checking for existing certificate..."
    
    if [[ -f "$CERT_PATH/fullchain.pem" ]]; then
        log "Certificate already exists, checking validity..."
        
        # Check if certificate is valid and not expiring soon (30 days)
        if openssl x509 -checkend 2592000 -noout -in "$CERT_PATH/fullchain.pem" >/dev/null 2>&1; then
            log "Existing certificate is valid and not expiring soon"
            return 0
        else
            log "Existing certificate is expiring soon or invalid, will regenerate"
        fi
    fi
    
    log "Generating initial wildcard certificate for *.${DOMAIN} and ${DOMAIN}..."
    
    local retry_count=0
    local backoff_delay=$RETRY_DELAY
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log "Certificate generation attempt $((retry_count + 1))/$MAX_RETRIES"
        
        # Build certbot command with proper arguments
        local certbot_cmd=(
            "certbot" "certonly"
            "--${DNS_PLUGIN}"
            "--${DNS_PLUGIN}-credentials" "$CREDENTIALS_FILE"
            "--email" "$EMAIL"
            "--agree-tos"
            "--no-eff-email"
            "--non-interactive"
            "--expand"
            "--domains" "*.${DOMAIN},${DOMAIN}"
            "--cert-name" "$DOMAIN"
            "--verbose"
            "--keep-until-expiring"
        )
        
        log "Executing: ${certbot_cmd[*]}"
        
        if "${certbot_cmd[@]}"; then
            
            log "Certificate generated successfully!"
            
            # Combine certificates for HAProxy
            if /scripts/combine-certs.sh; then
                log "Certificate combination completed successfully"
                return 0
            else
                handle_error "Failed to combine certificates"
                return 1
            fi
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log "Certificate generation failed, retrying in ${backoff_delay} seconds..."
                sleep $backoff_delay
                backoff_delay=$((backoff_delay * 2))  # Exponential backoff
            else
                handle_error "Certificate generation failed after $MAX_RETRIES attempts"
                return 1
            fi
        fi
    done
}

# Setup automated renewal system
setup_renewal_system() {
    log "Setting up automated certificate renewal system..."
    
    # Install and configure cron-based renewal
    if /scripts/setup-renewal-cron.sh --install; then
        log "Automated renewal system configured successfully"
    else
        log "WARNING: Failed to setup automated renewal system"
        log "Falling back to daemon-based renewal"
        return 1
    fi
}

# Fallback renewal daemon (used if cron setup fails)
renewal_daemon() {
    log "Starting fallback certificate renewal daemon..."
    
    while true; do
        log "Running scheduled certificate renewal check..."
        
        # Use the enhanced renewal script
        if /scripts/certificate-renewal.sh; then
            log "Renewal check completed successfully"
        else
            log "ERROR: Renewal check failed, will retry in next cycle"
        fi
        
        log "Sleeping for 12 hours until next renewal check..."
        sleep 43200  # 12 hours
    done
}

# Cleanup function for graceful shutdown
cleanup() {
    log "Received shutdown signal, cleaning up..."
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
main() {
    log "Starting Certbot Manager for domain: $DOMAIN"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Validate environment
    validate_environment || exit 1
    
    # Install dependencies
    install_dependencies || exit 1
    
    # Generate initial certificate
    generate_initial_certificate || exit 1
    
    # Setup automated renewal system
    if ! setup_renewal_system; then
        log "Automated renewal setup failed, using fallback daemon"
        renewal_daemon
    else
        log "Automated renewal system active, keeping container alive..."
        # Keep container running to maintain cron jobs
        while true; do
            sleep 3600  # Sleep for 1 hour
            
            # Periodic health check
            if [[ -f "$CERT_PATH/fullchain.pem" ]]; then
                log "Certificate health check: OK"
            else
                log "WARNING: Certificate file missing, may need regeneration"
            fi
        done
    fi
}

# Execute main function
main "$@"