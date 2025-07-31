#!/bin/bash

#---------------------------------------------------------------------
# HAProxy Configuration File Watcher
# Monitors configuration files for changes and triggers reload
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/usr/local/etc/haproxy/haproxy.cfg}"
CONFIG_DIR="${CONFIG_DIR:-/usr/local/etc/haproxy}"
LOG_FILE="${LOG_FILE:-./logs/watcher.log}"
RELOAD_SCRIPT="${RELOAD_SCRIPT:-$(dirname "$0")/haproxy-config-reload.sh}"
WATCH_INTERVAL="${WATCH_INTERVAL:-5}"
DEBOUNCE_TIME="${DEBOUNCE_TIME:-10}"
MAX_RELOAD_ATTEMPTS="${MAX_RELOAD_ATTEMPTS:-3}"
RELOAD_COOLDOWN="${RELOAD_COOLDOWN:-60}"
VERBOSE="${VERBOSE:-false}"

# State tracking
LAST_RELOAD_TIME=0
RELOAD_ATTEMPTS=0
PENDING_RELOAD=false
LAST_CHANGE_TIME=0

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
Usage: $0 [OPTIONS]

HAProxy Configuration File Watcher

Monitors HAProxy configuration files for changes and automatically
triggers validation and reload processes.

OPTIONS:
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose output
    -c, --config FILE           Configuration file to watch
                               (default: /usr/local/etc/haproxy/haproxy.cfg)
    -d, --config-dir DIR        Configuration directory to watch
                               (default: /usr/local/etc/haproxy)
    -i, --interval SEC          Watch interval in seconds (default: 5)
    -b, --debounce SEC          Debounce time in seconds (default: 10)
    -r, --reload-script PATH    Path to reload script
    --max-attempts NUM          Maximum reload attempts (default: 3)
    --cooldown SEC              Cooldown between reloads (default: 60)
    --dry-run                   Log changes but don't trigger reloads
    --daemon                    Run as daemon (background process)

EXAMPLES:
    $0                                      # Watch default configuration
    $0 -v -i 2 -b 5                       # Verbose with custom intervals
    $0 --config /path/to/haproxy.cfg       # Watch specific file
    $0 --daemon                            # Run as background daemon
    $0 --dry-run                           # Monitor only, no reloads

SIGNALS:
    SIGUSR1    Trigger immediate reload check
    SIGUSR2    Reset reload attempt counter
    SIGTERM    Graceful shutdown
    SIGINT     Graceful shutdown

EOF
}

# Parse command line arguments
DRY_RUN=false
DAEMON_MODE=false

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
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -d|--config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        -i|--interval)
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -b|--debounce)
            DEBOUNCE_TIME="$2"
            shift 2
            ;;
        -r|--reload-script)
            RELOAD_SCRIPT="$2"
            shift 2
            ;;
        --max-attempts)
            MAX_RELOAD_ATTEMPTS="$2"
            shift 2
            ;;
        --cooldown)
            RELOAD_COOLDOWN="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --daemon)
            DAEMON_MODE=true
            shift
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            log "ERROR" "Unexpected argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
    # Fallback to current directory if we can't create log directory
    LOG_FILE="./watcher.log"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
fi

log "INFO" "Starting HAProxy configuration watcher"
log "DEBUG" "Config file: $CONFIG_FILE"
log "DEBUG" "Config directory: $CONFIG_DIR"
log "DEBUG" "Watch interval: ${WATCH_INTERVAL}s"
log "DEBUG" "Debounce time: ${DEBOUNCE_TIME}s"
log "DEBUG" "Reload script: $RELOAD_SCRIPT"
log "DEBUG" "Dry run mode: $DRY_RUN"
log "DEBUG" "Daemon mode: $DAEMON_MODE"

# Utility functions
get_current_time() {
    date +%s
}

get_file_checksum() {
    local file="$1"
    if [ -f "$file" ]; then
        sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "error"
    else
        echo "missing"
    fi
}

get_directory_checksum() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "*.cfg" -o -name "*.conf" | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "error"
    else
        echo "missing"
    fi
}

check_reload_cooldown() {
    local current_time
    current_time=$(get_current_time)
    local time_since_last_reload=$((current_time - LAST_RELOAD_TIME))
    
    if [ $time_since_last_reload -lt $RELOAD_COOLDOWN ]; then
        local remaining=$((RELOAD_COOLDOWN - time_since_last_reload))
        log "DEBUG" "Reload cooldown active, ${remaining}s remaining"
        return 1
    fi
    
    return 0
}

check_reload_attempts() {
    if [ $RELOAD_ATTEMPTS -ge $MAX_RELOAD_ATTEMPTS ]; then
        log "WARN" "Maximum reload attempts ($MAX_RELOAD_ATTEMPTS) reached"
        return 1
    fi
    
    return 0
}

reset_reload_attempts() {
    log "INFO" "Resetting reload attempt counter"
    RELOAD_ATTEMPTS=0
}

trigger_reload() {
    local current_time
    current_time=$(get_current_time)
    
    log "INFO" "Triggering configuration reload"
    
    # Check cooldown
    if ! check_reload_cooldown; then
        log "WARN" "Reload skipped due to cooldown period"
        return 1
    fi
    
    # Check attempt limit
    if ! check_reload_attempts; then
        log "ERROR" "Reload skipped due to attempt limit"
        return 1
    fi
    
    # Dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "Dry run mode: reload would be triggered here"
        return 0
    fi
    
    # Check if reload script exists
    if [ ! -f "$RELOAD_SCRIPT" ]; then
        log "ERROR" "Reload script not found: $RELOAD_SCRIPT"
        return 1
    fi
    
    # Execute reload script
    log "INFO" "Executing reload script: $RELOAD_SCRIPT"
    
    local reload_output
    local reload_exit_code
    
    if reload_output=$("$RELOAD_SCRIPT" "$CONFIG_FILE" 2>&1); then
        reload_exit_code=0
    else
        reload_exit_code=$?
    fi
    
    # Update state
    LAST_RELOAD_TIME=$current_time
    ((RELOAD_ATTEMPTS++))
    
    # Handle reload result
    case $reload_exit_code in
        0)
            log "INFO" "Configuration reload successful"
            reset_reload_attempts
            return 0
            ;;
        2)
            log "WARN" "Configuration reload failed but rollback successful"
            return 1
            ;;
        3)
            log "ERROR" "Configuration reload and rollback failed"
            log "ERROR" "Reload output: $reload_output"
            return 1
            ;;
        *)
            log "ERROR" "Configuration reload failed with exit code: $reload_exit_code"
            log "ERROR" "Reload output: $reload_output"
            return 1
            ;;
    esac
}

check_for_changes() {
    local current_time
    current_time=$(get_current_time)
    
    # Get current checksums
    local current_file_checksum
    local current_dir_checksum
    
    current_file_checksum=$(get_file_checksum "$CONFIG_FILE")
    current_dir_checksum=$(get_directory_checksum "$CONFIG_DIR")
    
    # Initialize checksums on first run
    if [ -z "${LAST_FILE_CHECKSUM:-}" ]; then
        LAST_FILE_CHECKSUM="$current_file_checksum"
        LAST_DIR_CHECKSUM="$current_dir_checksum"
        log "DEBUG" "Initial checksums recorded"
        return 0
    fi
    
    # Check for changes
    local changes_detected=false
    
    if [ "$current_file_checksum" != "$LAST_FILE_CHECKSUM" ]; then
        log "INFO" "Configuration file change detected: $CONFIG_FILE"
        changes_detected=true
    fi
    
    if [ "$current_dir_checksum" != "$LAST_DIR_CHECKSUM" ]; then
        log "INFO" "Configuration directory change detected: $CONFIG_DIR"
        changes_detected=true
    fi
    
    # Handle changes
    if [ "$changes_detected" = "true" ]; then
        log "DEBUG" "Change detected at $(date)"
        LAST_CHANGE_TIME=$current_time
        PENDING_RELOAD=true
        
        # Update checksums
        LAST_FILE_CHECKSUM="$current_file_checksum"
        LAST_DIR_CHECKSUM="$current_dir_checksum"
        
        return 0
    fi
    
    # Check if debounce period has passed for pending reload
    if [ "$PENDING_RELOAD" = "true" ]; then
        local time_since_change=$((current_time - LAST_CHANGE_TIME))
        
        if [ $time_since_change -ge $DEBOUNCE_TIME ]; then
            log "DEBUG" "Debounce period passed, triggering reload"
            PENDING_RELOAD=false
            
            if trigger_reload; then
                log "INFO" "Reload triggered successfully"
            else
                log "WARN" "Reload trigger failed"
            fi
        else
            local remaining=$((DEBOUNCE_TIME - time_since_change))
            log "DEBUG" "Debounce period active, ${remaining}s remaining"
        fi
    fi
    
    return 0
}

# Signal handlers
handle_sigusr1() {
    log "INFO" "SIGUSR1 received, forcing immediate reload check"
    PENDING_RELOAD=true
    LAST_CHANGE_TIME=$(get_current_time)
}

handle_sigusr2() {
    log "INFO" "SIGUSR2 received, resetting reload attempts"
    reset_reload_attempts
}

handle_shutdown() {
    log "INFO" "Shutdown signal received, stopping watcher"
    exit 0
}

# Set up signal handlers
trap 'handle_sigusr1' USR1
trap 'handle_sigusr2' USR2
trap 'handle_shutdown' TERM INT

# Daemon mode setup
if [ "$DAEMON_MODE" = "true" ]; then
    log "INFO" "Starting in daemon mode"
    
    # Create PID file
    local pid_file="/var/run/haproxy-config-watcher.pid"
    echo $$ > "$pid_file"
    
    # Redirect output to log file
    exec >> "$LOG_FILE" 2>&1
fi

# Validate prerequisites
if [ ! -f "$CONFIG_FILE" ] && [ ! -d "$CONFIG_DIR" ]; then
    log "ERROR" "Neither config file nor config directory exists"
    exit 1
fi

if [ ! -f "$RELOAD_SCRIPT" ] && [ "$DRY_RUN" = "false" ]; then
    log "ERROR" "Reload script not found: $RELOAD_SCRIPT"
    exit 1
fi

# Main watch loop
log "INFO" "Configuration watcher started"
log "INFO" "Watching: $CONFIG_FILE and $CONFIG_DIR"
log "INFO" "Watch interval: ${WATCH_INTERVAL}s, Debounce: ${DEBOUNCE_TIME}s"

while true; do
    if ! check_for_changes; then
        log "ERROR" "Error checking for changes"
    fi
    
    sleep "$WATCH_INTERVAL"
done