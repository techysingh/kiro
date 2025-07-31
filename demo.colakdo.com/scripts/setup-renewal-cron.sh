#!/bin/bash

# Setup Certificate Renewal Cron Job
# Configures automated certificate renewal scheduling

set -euo pipefail

# Configuration
RENEWAL_SCRIPT="/scripts/certificate-renewal.sh"
CRON_LOG="/var/log/letsencrypt/cron.log"
CRON_USER="root"

# Cron schedule configurations
# Default: Run every 12 hours at minute 0
CRON_SCHEDULE="${RENEWAL_CRON_SCHEDULE:-0 */12 * * *}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$CRON_LOG"
}

# Error handling
handle_error() {
    local exit_code=$?
    log "ERROR: $1"
    return $exit_code
}

# Create cron job entry
create_cron_entry() {
    log "Setting up certificate renewal cron job..."
    
    # Create log directory
    mkdir -p "$(dirname "$CRON_LOG")"
    
    # Create cron job command with proper logging and error handling
    local cron_command="$RENEWAL_SCRIPT >> $CRON_LOG 2>&1"
    local cron_entry="$CRON_SCHEDULE $cron_command"
    
    log "Cron schedule: $CRON_SCHEDULE"
    log "Cron command: $cron_command"
    
    # Check if cron is available
    if ! command -v crontab >/dev/null 2>&1; then
        log "Installing cron..."
        apk add --no-cache dcron || handle_error "Failed to install cron"
    fi
    
    # Get existing crontab (if any)
    local temp_cron="/tmp/renewal_cron.tmp"
    crontab -l 2>/dev/null | grep -v "$RENEWAL_SCRIPT" > "$temp_cron" || true
    
    # Add new cron entry
    echo "$cron_entry" >> "$temp_cron"
    
    # Install new crontab
    if crontab "$temp_cron"; then
        log "Cron job installed successfully"
        rm -f "$temp_cron"
    else
        handle_error "Failed to install cron job"
        rm -f "$temp_cron"
        return 1
    fi
    
    # Display installed cron jobs
    log "Current cron jobs:"
    crontab -l | while read -r line; do
        log "  $line"
    done
    
    return 0
}

# Start cron daemon
start_cron_daemon() {
    log "Starting cron daemon..."
    
    # Create cron directories if they don't exist
    mkdir -p /var/spool/cron/crontabs
    mkdir -p /var/log/cron
    
    # Start crond in the background
    if crond -b -l 2; then
        log "Cron daemon started successfully"
    else
        handle_error "Failed to start cron daemon"
        return 1
    fi
    
    # Verify cron is running
    if pgrep crond >/dev/null 2>&1; then
        log "Cron daemon is running (PID: $(pgrep crond))"
    else
        handle_error "Cron daemon is not running"
        return 1
    fi
    
    return 0
}

# Verify cron setup
verify_cron_setup() {
    log "Verifying cron setup..."
    
    # Check if cron job exists
    if crontab -l 2>/dev/null | grep -q "$RENEWAL_SCRIPT"; then
        log "Certificate renewal cron job is configured"
    else
        handle_error "Certificate renewal cron job not found"
        return 1
    fi
    
    # Check if cron daemon is running
    if pgrep crond >/dev/null 2>&1; then
        log "Cron daemon is running"
    else
        handle_error "Cron daemon is not running"
        return 1
    fi
    
    # Test renewal script exists and is executable
    if [[ -x "$RENEWAL_SCRIPT" ]]; then
        log "Renewal script is executable: $RENEWAL_SCRIPT"
    else
        handle_error "Renewal script not found or not executable: $RENEWAL_SCRIPT"
        return 1
    fi
    
    log "Cron setup verification completed successfully"
    return 0
}

# Show next scheduled run times
show_schedule_info() {
    log "Certificate renewal schedule information:"
    log "  Schedule: $CRON_SCHEDULE"
    log "  Script: $RENEWAL_SCRIPT"
    log "  Log file: $CRON_LOG"
    
    # Calculate next run time (approximate)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    log "  Current time: $current_time"
    
    # Show cron job details
    log "  Cron job details:"
    crontab -l | grep "$RENEWAL_SCRIPT" | while read -r line; do
        log "    $line"
    done
}

# Remove existing cron job (for cleanup)
remove_cron_job() {
    log "Removing existing certificate renewal cron job..."
    
    local temp_cron="/tmp/removal_cron.tmp"
    if crontab -l 2>/dev/null | grep -v "$RENEWAL_SCRIPT" > "$temp_cron"; then
        crontab "$temp_cron"
        log "Existing cron job removed"
    else
        log "No existing cron job found"
    fi
    
    rm -f "$temp_cron"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup Certificate Renewal Cron Job

OPTIONS:
    --install       Install and start cron job (default)
    --remove        Remove existing cron job
    --verify        Verify cron setup
    --schedule      Show schedule information
    --help          Show this help message

ENVIRONMENT VARIABLES:
    RENEWAL_CRON_SCHEDULE    Cron schedule (default: "0 */12 * * *")

EXAMPLES:
    $0                      # Install cron job with default schedule
    $0 --verify             # Verify cron setup
    $0 --remove             # Remove cron job
    
    # Custom schedule (every 6 hours)
    RENEWAL_CRON_SCHEDULE="0 */6 * * *" $0

EOF
}

# Main execution
main() {
    local action="install"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                action="install"
                shift
                ;;
            --remove)
                action="remove"
                shift
                ;;
            --verify)
                action="verify"
                shift
                ;;
            --schedule)
                action="schedule"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log "ERROR: Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Create log directory
    mkdir -p "$(dirname "$CRON_LOG")"
    
    log "Starting cron setup with action: $action"
    
    case "$action" in
        "install")
            create_cron_entry || exit 1
            start_cron_daemon || exit 1
            verify_cron_setup || exit 1
            show_schedule_info
            ;;
        "remove")
            remove_cron_job
            ;;
        "verify")
            verify_cron_setup || exit 1
            ;;
        "schedule")
            show_schedule_info
            ;;
        *)
            log "ERROR: Unknown action: $action"
            exit 1
            ;;
    esac
    
    log "Cron setup completed successfully"
}

# Execute main function
main "$@"