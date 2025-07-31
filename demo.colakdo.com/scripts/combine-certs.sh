#!/bin/bash

# Script to combine Let's Encrypt certificates for HAProxy
# HAProxy requires cert + private key in a single file

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
OUTPUT_DIR="/etc/ssl/certs/live/${DOMAIN}"
LOG_FILE="/var/log/letsencrypt/combine-certs.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    log "ERROR: $1"
    return $exit_code
}

# Main certificate combination function
combine_certificates() {
    log "Starting certificate combination for domain: $DOMAIN"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    # Check if certificates exist
    if [[ ! -f "$CERT_DIR/fullchain.pem" ]]; then
        handle_error "Certificate file not found: $CERT_DIR/fullchain.pem"
        return 1
    fi
    
    if [[ ! -f "$CERT_DIR/privkey.pem" ]]; then
        handle_error "Private key file not found: $CERT_DIR/privkey.pem"
        return 1
    fi
    
    # Check if certificate files are readable
    if [[ ! -r "$CERT_DIR/fullchain.pem" ]]; then
        handle_error "Cannot read certificate file: $CERT_DIR/fullchain.pem"
        return 1
    fi
    
    if [[ ! -r "$CERT_DIR/privkey.pem" ]]; then
        handle_error "Cannot read private key file: $CERT_DIR/privkey.pem"
        return 1
    fi
    
    # Verify certificate validity before combining
    if ! openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1; then
        handle_error "Certificate is invalid or expired: $CERT_DIR/fullchain.pem"
        return 1
    fi
    
    # Verify private key
    if ! openssl rsa -in "$CERT_DIR/privkey.pem" -check -noout >/dev/null 2>&1; then
        handle_error "Private key is invalid: $CERT_DIR/privkey.pem"
        return 1
    fi
    
    # Verify that certificate and private key match
    local cert_modulus
    local key_modulus
    
    cert_modulus=$(openssl x509 -noout -modulus -in "$CERT_DIR/fullchain.pem" | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$CERT_DIR/privkey.pem" | openssl md5)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        handle_error "Certificate and private key do not match"
        return 1
    fi
    
    log "Certificate validation successful"
    
    # Create temporary combined file
    local temp_combined="$OUTPUT_DIR/combined.pem.tmp"
    
    # Combine certificate and private key for HAProxy
    log "Combining certificate and private key..."
    if ! cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem" > "$temp_combined"; then
        handle_error "Failed to combine certificate files"
        return 1
    fi
    
    # Verify the combined certificate
    if ! openssl x509 -in "$temp_combined" -text -noout >/dev/null 2>&1; then
        handle_error "Combined certificate verification failed"
        rm -f "$temp_combined"
        return 1
    fi
    
    # Set appropriate permissions
    chmod 600 "$temp_combined"
    
    # Atomically move the temporary file to the final location
    if ! mv "$temp_combined" "$OUTPUT_DIR/combined.pem"; then
        handle_error "Failed to move combined certificate to final location"
        rm -f "$temp_combined"
        return 1
    fi
    
    log "Certificate combination successful!"
    log "Combined certificate created at: $OUTPUT_DIR/combined.pem"
    
    # Show certificate details
    log "Certificate details:"
    openssl x509 -in "$OUTPUT_DIR/combined.pem" -text -noout | grep -E "(Subject:|DNS:|Not Before|Not After)" | while read -r line; do
        log "  $line"
    done
    
    # Get certificate expiration date
    local expiry_date
    expiry_date=$(openssl x509 -in "$OUTPUT_DIR/combined.pem" -noout -enddate | cut -d= -f2)
    log "Certificate expires: $expiry_date"
    
    return 0
}

# Signal HAProxy to reload configuration
reload_haproxy() {
    log "Attempting to reload HAProxy configuration..."
    
    # Try multiple methods to reload HAProxy
    local reload_success=false
    
    # Method 1: Send HUP signal to HAProxy process
    if pgrep haproxy >/dev/null 2>&1; then
        if pkill -HUP haproxy 2>/dev/null; then
            log "HAProxy configuration reloaded successfully via HUP signal"
            reload_success=true
        else
            log "WARNING: Failed to send HUP signal to HAProxy"
        fi
    else
        log "HAProxy process not found, skipping reload"
    fi
    
    # Method 2: Try Docker container reload if available
    if ! $reload_success && command -v docker >/dev/null 2>&1; then
        if docker ps --format "table {{.Names}}" | grep -q "haproxy-proxy"; then
            if docker kill --signal=HUP haproxy-proxy 2>/dev/null; then
                log "HAProxy configuration reloaded successfully via Docker signal"
                reload_success=true
            else
                log "WARNING: Failed to send HUP signal to HAProxy container"
            fi
        fi
    fi
    
    if ! $reload_success; then
        log "WARNING: Could not reload HAProxy configuration automatically"
        log "You may need to manually restart HAProxy to use the new certificate"
    fi
}

# Cleanup function
cleanup() {
    # Remove any temporary files
    rm -f "$OUTPUT_DIR/combined.pem.tmp"
}

# Set up signal handlers
trap cleanup EXIT

# Main execution
main() {
    log "Starting certificate combination process"
    
    if combine_certificates; then
        reload_haproxy
        log "Certificate setup completed successfully!"
        return 0
    else
        handle_error "Certificate combination failed"
        return 1
    fi
}

# Execute main function
main "$@"