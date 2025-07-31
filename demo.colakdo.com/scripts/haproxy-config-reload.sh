#!/bin/bash

#---------------------------------------------------------------------
# HAProxy Configuration Reload Script with Rollback
# Safely reloads HAProxy configuration with automatic rollback on failure
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/usr/local/etc/haproxy/haproxy.cfg}"
BACKUP_DIR="${BACKUP_DIR:-/usr/local/etc/haproxy/backups}"
LOG_FILE="${LOG_FILE:-./logs/reload.log}"
PID_FILE="${PID_FILE:-/var/run/haproxy.pid}"
STATS_SOCKET="${STATS_SOCKET:-/var/run/haproxy.sock}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:8404/health}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-60}"
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

HAProxy Configuration Reload Script with Rollback

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --force             Force reload without validation
    -t, --test-only         Test configuration without reloading
    -r, --rollback          Rollback to previous configuration
    --no-health-check       Skip health checks after reload
    --health-timeout SEC    Health check timeout (default: 30)
    --rollback-timeout SEC  Rollback timeout (default: 60)

ARGUMENTS:
    CONFIG_FILE            Path to HAProxy configuration file
                          (default: /usr/local/etc/haproxy/haproxy.cfg)

EXAMPLES:
    $0                                    # Validate and reload default config
    $0 -v /path/to/haproxy.cfg           # Verbose reload with custom config
    $0 --test-only                       # Test configuration only
    $0 --rollback                        # Rollback to previous configuration
    $0 --force --no-health-check         # Force reload without health checks

EOF
}

# Parse command line arguments
FORCE_RELOAD=false
TEST_ONLY=false
ROLLBACK_MODE=false
SKIP_HEALTH_CHECK=false

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
        -f|--force)
            FORCE_RELOAD=true
            shift
            ;;
        -t|--test-only)
            TEST_ONLY=true
            shift
            ;;
        -r|--rollback)
            ROLLBACK_MODE=true
            shift
            ;;
        --no-health-check)
            SKIP_HEALTH_CHECK=true
            shift
            ;;
        --health-timeout)
            HEALTH_CHECK_TIMEOUT="$2"
            shift 2
            ;;
        --rollback-timeout)
            ROLLBACK_TIMEOUT="$2"
            shift 2
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
    LOG_FILE="./reload.log"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
fi
mkdir -p "$BACKUP_DIR" 2>/dev/null || true

log "INFO" "Starting HAProxy configuration reload process"
log "DEBUG" "Config file: $CONFIG_FILE"
log "DEBUG" "Force reload: $FORCE_RELOAD"
log "DEBUG" "Test only: $TEST_ONLY"
log "DEBUG" "Rollback mode: $ROLLBACK_MODE"
log "DEBUG" "Skip health check: $SKIP_HEALTH_CHECK"

# Utility functions
check_haproxy_binary() {
    if ! command -v haproxy >/dev/null 2>&1; then
        if [ "$TEST_ONLY" = "true" ]; then
            log "WARN" "HAProxy binary not found in PATH (test mode, continuing)"
            return 0
        else
            log "ERROR" "HAProxy binary not found in PATH"
            return 1
        fi
    fi
    log "DEBUG" "HAProxy binary found: $(command -v haproxy)"
    return 0
}

get_haproxy_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            log "WARN" "PID file exists but process is not running"
            rm -f "$PID_FILE"
        fi
    fi
    
    # Try to find HAProxy process
    local pid
    pid=$(pgrep -f "haproxy.*$CONFIG_FILE" | head -1 || true)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    
    return 1
}

validate_configuration() {
    log "INFO" "Validating HAProxy configuration"
    
    if [ "$FORCE_RELOAD" = "true" ]; then
        log "WARN" "Force reload enabled, skipping validation"
        return 0
    fi
    
    # Use the validation script
    local validation_script="$(dirname "$0")/validate-haproxy-config.sh"
    
    if [ -f "$validation_script" ]; then
        log "DEBUG" "Using validation script: $validation_script"
        if "$validation_script" --syntax-only "$CONFIG_FILE"; then
            log "INFO" "Configuration validation passed"
            return 0
        else
            log "ERROR" "Configuration validation failed"
            return 1
        fi
    else
        # Fallback to basic haproxy syntax check
        log "DEBUG" "Validation script not found, using basic syntax check"
        if haproxy -c -f "$CONFIG_FILE" >/dev/null 2>&1; then
            log "INFO" "Basic syntax validation passed"
            return 0
        else
            log "ERROR" "Basic syntax validation failed"
            return 1
        fi
    fi
}

create_backup() {
    log "INFO" "Creating configuration backup"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/haproxy.cfg.$timestamp"
    
    if cp "$CONFIG_FILE" "$backup_file"; then
        log "INFO" "Backup created: $backup_file"
        echo "$backup_file" > "$BACKUP_DIR/latest_backup"
        
        # Keep only last 20 backups
        find "$BACKUP_DIR" -name "haproxy.cfg.*" -type f | sort -r | tail -n +21 | xargs -r rm -f
        log "DEBUG" "Old backups cleaned up"
        
        return 0
    else
        log "ERROR" "Failed to create backup"
        return 1
    fi
}

get_latest_backup() {
    if [ -f "$BACKUP_DIR/latest_backup" ]; then
        local backup_file
        backup_file=$(cat "$BACKUP_DIR/latest_backup")
        if [ -f "$backup_file" ]; then
            echo "$backup_file"
            return 0
        fi
    fi
    
    # Fallback to finding latest backup
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "haproxy.cfg.*" -type f | sort -r | head -1 || true)
    if [ -n "$latest_backup" ]; then
        echo "$latest_backup"
        return 0
    fi
    
    return 1
}

perform_graceful_reload() {
    log "INFO" "Performing graceful HAProxy reload"
    
    local old_pid
    if old_pid=$(get_haproxy_pid); then
        log "DEBUG" "Current HAProxy PID: $old_pid"
        
        # Perform graceful reload
        if haproxy -f "$CONFIG_FILE" -p "$PID_FILE" -sf "$old_pid"; then
            log "INFO" "HAProxy graceful reload initiated"
            
            # Wait a moment for the new process to start
            sleep 2
            
            # Verify new process is running
            local new_pid
            if new_pid=$(get_haproxy_pid); then
                log "INFO" "HAProxy reload successful, new PID: $new_pid"
                return 0
            else
                log "ERROR" "HAProxy reload failed, no process found"
                return 1
            fi
        else
            log "ERROR" "HAProxy graceful reload command failed"
            return 1
        fi
    else
        log "INFO" "No existing HAProxy process found, starting new instance"
        if haproxy -f "$CONFIG_FILE" -p "$PID_FILE" -D; then
            log "INFO" "HAProxy started successfully"
            return 0
        else
            log "ERROR" "Failed to start HAProxy"
            return 1
        fi
    fi
}

perform_health_check() {
    if [ "$SKIP_HEALTH_CHECK" = "true" ]; then
        log "INFO" "Health check skipped"
        return 0
    fi
    
    log "INFO" "Performing health check"
    
    local timeout="$HEALTH_CHECK_TIMEOUT"
    local start_time
    start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
        if curl -s -f "$HEALTH_CHECK_URL" >/dev/null 2>&1; then
            log "INFO" "Health check passed"
            return 0
        fi
        
        log "DEBUG" "Health check failed, retrying in 2 seconds..."
        sleep 2
    done
    
    log "ERROR" "Health check failed after $timeout seconds"
    return 1
}

perform_rollback() {
    log "WARN" "Performing configuration rollback"
    
    local backup_file
    if backup_file=$(get_latest_backup); then
        log "INFO" "Rolling back to: $backup_file"
        
        # Copy backup to current config
        if cp "$backup_file" "$CONFIG_FILE"; then
            log "INFO" "Configuration restored from backup"
            
            # Reload with backup configuration
            if perform_graceful_reload; then
                log "INFO" "Rollback reload successful"
                
                # Verify health after rollback
                if perform_health_check; then
                    log "INFO" "Rollback completed successfully"
                    return 0
                else
                    log "ERROR" "Health check failed after rollback"
                    return 1
                fi
            else
                log "ERROR" "Rollback reload failed"
                return 1
            fi
        else
            log "ERROR" "Failed to restore configuration from backup"
            return 1
        fi
    else
        log "ERROR" "No backup found for rollback"
        return 1
    fi
}

monitor_reload_success() {
    log "INFO" "Monitoring reload success"
    
    local timeout="$ROLLBACK_TIMEOUT"
    local start_time
    start_time=$(date +%s)
    local check_interval=5
    
    while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
        if perform_health_check; then
            log "INFO" "Reload monitoring successful"
            return 0
        fi
        
        log "DEBUG" "Health check failed, waiting $check_interval seconds..."
        sleep "$check_interval"
    done
    
    log "ERROR" "Reload monitoring failed, initiating rollback"
    return 1
}

# Main functions
main_reload() {
    log "INFO" "Starting configuration reload process"
    
    # Check HAProxy binary
    if ! check_haproxy_binary; then
        exit 1
    fi
    
    # Validate configuration
    if ! validate_configuration; then
        log "ERROR" "Configuration validation failed, aborting reload"
        exit 1
    fi
    
    # Test only mode
    if [ "$TEST_ONLY" = "true" ]; then
        log "INFO" "Test completed successfully, no reload performed"
        exit 0
    fi
    
    # Create backup
    if ! create_backup; then
        log "ERROR" "Failed to create backup, aborting reload"
        exit 1
    fi
    
    # Perform reload
    if ! perform_graceful_reload; then
        log "ERROR" "Graceful reload failed"
        
        # Attempt rollback
        if perform_rollback; then
            log "WARN" "Rollback completed, reload failed but system is stable"
            exit 2
        else
            log "ERROR" "Rollback failed, system may be unstable"
            exit 3
        fi
    fi
    
    # Monitor success and rollback if needed
    if ! monitor_reload_success; then
        if perform_rollback; then
            log "WARN" "Automatic rollback completed due to health check failures"
            exit 2
        else
            log "ERROR" "Automatic rollback failed, manual intervention required"
            exit 3
        fi
    fi
    
    log "INFO" "Configuration reload completed successfully"
    exit 0
}

main_rollback() {
    log "INFO" "Starting manual rollback process"
    
    # Check HAProxy binary
    if ! check_haproxy_binary; then
        exit 1
    fi
    
    # Perform rollback
    if perform_rollback; then
        log "INFO" "Manual rollback completed successfully"
        exit 0
    else
        log "ERROR" "Manual rollback failed"
        exit 1
    fi
}

# Signal handlers for graceful shutdown
trap 'log "WARN" "Reload process interrupted"; exit 130' INT TERM

# Main execution
if [ "$ROLLBACK_MODE" = "true" ]; then
    main_rollback
else
    main_reload
fi