#!/bin/bash

#---------------------------------------------------------------------
# HAProxy Configuration Validation Script
# Validates HAProxy configuration files with comprehensive checks
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
CONFIG_FILE="${1:-/usr/local/etc/haproxy/haproxy.cfg}"
BACKUP_DIR="${BACKUP_DIR:-/usr/local/etc/haproxy/backups}"
LOG_FILE="${LOG_FILE:-./logs/validation.log}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = "true" ]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
    esac
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [CONFIG_FILE]

HAProxy Configuration Validation Script

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -c, --check-only    Only validate, don't create backup
    -b, --backup        Create backup before validation
    -r, --reload        Reload HAProxy after successful validation
    --syntax-only       Only perform syntax validation
    --full-check        Perform comprehensive validation (default)

ARGUMENTS:
    CONFIG_FILE         Path to HAProxy configuration file
                       (default: /usr/local/etc/haproxy/haproxy.cfg)

EXAMPLES:
    $0                                  # Validate default config
    $0 -v -r /path/to/haproxy.cfg      # Verbose validation with reload
    $0 --syntax-only                   # Quick syntax check only
    $0 --backup --reload               # Backup, validate, and reload

EOF
}

# Parse command line arguments
BACKUP_ENABLED=false
RELOAD_ENABLED=false
SYNTAX_ONLY=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -b|--backup)
            BACKUP_ENABLED=true
            shift
            ;;
        -r|--reload)
            RELOAD_ENABLED=true
            shift
            ;;
        --syntax-only)
            SYNTAX_ONLY=true
            shift
            ;;
        --full-check)
            SYNTAX_ONLY=false
            shift
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            CONFIG_FILE="$1"
            shift
            ;;
    esac
done

# Initialize logging
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
    # Fallback to current directory if we can't create log directory
    LOG_FILE="./validation.log"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
fi
log "INFO" "Starting HAProxy configuration validation"
log "DEBUG" "Config file: $CONFIG_FILE"
log "DEBUG" "Backup enabled: $BACKUP_ENABLED"
log "DEBUG" "Reload enabled: $RELOAD_ENABLED"
log "DEBUG" "Syntax only: $SYNTAX_ONLY"

# Validation functions
validate_file_exists() {
    log "DEBUG" "Checking if configuration file exists"
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    log "INFO" "Configuration file found: $CONFIG_FILE"
    return 0
}

validate_file_readable() {
    log "DEBUG" "Checking if configuration file is readable"
    if [ ! -r "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file is not readable: $CONFIG_FILE"
        return 1
    fi
    log "DEBUG" "Configuration file is readable"
    return 0
}

validate_syntax() {
    log "INFO" "Performing HAProxy syntax validation"
    
    # Use haproxy binary to validate syntax
    if command -v haproxy >/dev/null 2>&1; then
        local temp_output
        temp_output=$(mktemp)
        
        if haproxy -c -f "$CONFIG_FILE" > "$temp_output" 2>&1; then
            log "INFO" "HAProxy syntax validation passed"
            if [ "$VERBOSE" = "true" ]; then
                log "DEBUG" "HAProxy output: $(cat "$temp_output")"
            fi
            rm -f "$temp_output"
            return 0
        else
            log "ERROR" "HAProxy syntax validation failed"
            log "ERROR" "HAProxy output: $(cat "$temp_output")"
            rm -f "$temp_output"
            return 1
        fi
    else
        log "WARN" "HAProxy binary not found, skipping syntax validation"
        return 0
    fi
}

validate_required_sections() {
    log "DEBUG" "Checking for required configuration sections"
    local errors=0
    
    # Check for required sections
    local required_sections=("global" "defaults" "frontend" "backend")
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "^${section}" "$CONFIG_FILE"; then
            log "ERROR" "Missing required section: $section"
            ((errors++))
        else
            log "DEBUG" "Found required section: $section"
        fi
    done
    
    return $errors
}

validate_ssl_configuration() {
    log "DEBUG" "Validating SSL configuration"
    local warnings=0
    
    # Check for SSL cipher configuration
    if ! grep -q "ssl-default-bind-ciphers" "$CONFIG_FILE"; then
        log "WARN" "SSL cipher configuration not found"
        ((warnings++))
    else
        log "DEBUG" "SSL cipher configuration found"
    fi
    
    # Check for SSL options
    if ! grep -q "ssl-default-bind-options" "$CONFIG_FILE"; then
        log "WARN" "SSL bind options not configured"
        ((warnings++))
    else
        log "DEBUG" "SSL bind options found"
    fi
    
    # Check for SSL certificate binding
    if ! grep -q "bind.*ssl.*crt" "$CONFIG_FILE"; then
        log "WARN" "No SSL certificate binding found"
        ((warnings++))
    else
        log "DEBUG" "SSL certificate binding found"
    fi
    
    return $warnings
}

validate_security_headers() {
    log "DEBUG" "Validating security headers configuration"
    local warnings=0
    
    # Check for important security headers
    local security_headers=(
        "Strict-Transport-Security"
        "X-Content-Type-Options"
        "X-Frame-Options"
        "X-XSS-Protection"
    )
    
    for header in "${security_headers[@]}"; do
        if ! grep -q "$header" "$CONFIG_FILE"; then
            log "WARN" "Security header not configured: $header"
            ((warnings++))
        else
            log "DEBUG" "Security header found: $header"
        fi
    done
    
    return $warnings
}

validate_logging_configuration() {
    log "DEBUG" "Validating logging configuration"
    local warnings=0
    
    # Check for logging configuration
    if ! grep -q "^[[:space:]]*log" "$CONFIG_FILE"; then
        log "WARN" "No logging configuration found"
        ((warnings++))
    else
        log "DEBUG" "Logging configuration found"
    fi
    
    # Check for log format
    if ! grep -q "option httplog\|option tcplog" "$CONFIG_FILE"; then
        log "WARN" "No log format specified"
        ((warnings++))
    else
        log "DEBUG" "Log format configuration found"
    fi
    
    return $warnings
}

validate_timeouts() {
    log "DEBUG" "Validating timeout configuration"
    local warnings=0
    
    # Check for important timeouts
    local timeouts=("timeout connect" "timeout client" "timeout server")
    
    for timeout in "${timeouts[@]}"; do
        if ! grep -q "$timeout" "$CONFIG_FILE"; then
            log "WARN" "Timeout not configured: $timeout"
            ((warnings++))
        else
            log "DEBUG" "Timeout found: $timeout"
        fi
    done
    
    return $warnings
}

validate_backends() {
    log "DEBUG" "Validating backend configuration"
    local warnings=0
    
    # Get all backend names
    local backends
    backends=$(grep "^backend " "$CONFIG_FILE" | awk '{print $2}' || true)
    
    if [ -z "$backends" ]; then
        log "WARN" "No backends defined"
        return 1
    fi
    
    # Simple check - just count backends
    local backend_count
    backend_count=$(echo "$backends" | wc -l)
    log "DEBUG" "Found $backend_count backends"
    
    # Check if we have at least some backends defined
    if [ "$backend_count" -gt 0 ]; then
        log "DEBUG" "Backend configuration appears valid"
        return 0
    else
        log "WARN" "No valid backends found"
        return 1
    fi
}

create_backup() {
    if [ "$BACKUP_ENABLED" = "true" ] && [ "$CHECK_ONLY" = "false" ]; then
        log "INFO" "Creating configuration backup"
        
        mkdir -p "$BACKUP_DIR"
        local backup_file="$BACKUP_DIR/haproxy.cfg.$(date +%Y%m%d_%H%M%S)"
        
        if cp "$CONFIG_FILE" "$backup_file"; then
            log "INFO" "Backup created: $backup_file"
            
            # Keep only last 10 backups
            find "$BACKUP_DIR" -name "haproxy.cfg.*" -type f | sort -r | tail -n +11 | xargs -r rm -f
            log "DEBUG" "Old backups cleaned up"
            
            return 0
        else
            log "ERROR" "Failed to create backup"
            return 1
        fi
    fi
    return 0
}

# Main validation function
main() {
    log "INFO" "Starting HAProxy configuration validation"
    
    local exit_code=0
    local total_errors=0
    local total_warnings=0
    
    # Basic file checks
    if ! validate_file_exists; then
        exit 1
    fi
    
    if ! validate_file_readable; then
        exit 1
    fi
    
    # Create backup if requested
    if ! create_backup; then
        exit 1
    fi
    
    # Syntax validation (always performed)
    if ! validate_syntax; then
        log "ERROR" "Syntax validation failed"
        exit 1
    fi
    
    # Skip comprehensive checks if syntax-only mode
    if [ "$SYNTAX_ONLY" = "true" ]; then
        log "INFO" "Syntax validation completed successfully"
        exit 0
    fi
    
    # Comprehensive validation
    log "INFO" "Performing comprehensive configuration validation"
    
    # Required sections check
    if ! validate_required_sections; then
        log "ERROR" "Required sections validation failed"
        ((total_errors++))
    fi
    
    # SSL configuration check
    validate_ssl_configuration
    local ssl_warnings=$?
    ((total_warnings += ssl_warnings))
    
    # Security headers check
    validate_security_headers
    local security_warnings=$?
    ((total_warnings += security_warnings))
    
    # Logging configuration check
    validate_logging_configuration
    local logging_warnings=$?
    ((total_warnings += logging_warnings))
    
    # Timeout configuration check
    validate_timeouts
    local timeout_warnings=$?
    ((total_warnings += timeout_warnings))
    
    # Backend configuration check
    validate_backends
    local backend_warnings=$?
    ((total_warnings += backend_warnings))
    
    # Summary
    log "INFO" "Validation completed"
    log "INFO" "Total errors: $total_errors"
    log "INFO" "Total warnings: $total_warnings"
    log "DEBUG" "Exit code will be: $([ $total_errors -gt 0 ] && echo 1 || echo 0)"
    
    if [ $total_errors -gt 0 ]; then
        log "ERROR" "Configuration validation failed with $total_errors errors"
        exit_code=1
    elif [ $total_warnings -gt 0 ]; then
        log "WARN" "Configuration validation passed with $total_warnings warnings"
        exit_code=0
    else
        log "INFO" "Configuration validation passed without errors or warnings"
        exit_code=0
    fi
    
    # Reload HAProxy if requested and validation passed
    if [ "$RELOAD_ENABLED" = "true" ] && [ $exit_code -eq 0 ]; then
        log "INFO" "Reloading HAProxy configuration"
        if reload_haproxy; then
            log "INFO" "HAProxy reloaded successfully"
        else
            log "ERROR" "HAProxy reload failed"
            exit_code=1
        fi
    fi
    
    exit $exit_code
}

# HAProxy reload function (will be implemented in reload script)
reload_haproxy() {
    if command -v haproxy >/dev/null 2>&1; then
        # Use HAProxy's graceful reload
        if [ -f /var/run/haproxy.pid ]; then
            local old_pid
            old_pid=$(cat /var/run/haproxy.pid)
            haproxy -f "$CONFIG_FILE" -p /var/run/haproxy.pid -sf "$old_pid"
            return $?
        else
            log "WARN" "HAProxy PID file not found, attempting standard reload"
            haproxy -f "$CONFIG_FILE" -p /var/run/haproxy.pid
            return $?
        fi
    else
        log "ERROR" "HAProxy binary not found"
        return 1
    fi
}

# Run main function
main "$@"