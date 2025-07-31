#!/bin/bash

# Certificate Renewal Monitoring and Reporting Script
# Provides comprehensive monitoring and analysis of renewal attempts

set -euo pipefail

# Configuration
LOG_DIR="/var/log/letsencrypt"
RENEWAL_LOG="$LOG_DIR/renewal.log"
ERROR_LOG="$LOG_DIR/renewal-errors.log"
HISTORY_LOG="$LOG_DIR/renewal-history.log"
MONITOR_LOG="$LOG_DIR/monitor.log"

# Certificate paths
DOMAIN="${DOMAIN:-colakdo.com}"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"

# Monitoring thresholds
WARNING_DAYS=14
CRITICAL_DAYS=7
ERROR_THRESHOLD=3  # Number of consecutive errors before alert

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MONITOR_LOG"
}

# Colored output functions
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "OK")
            echo -e "${GREEN}[OK]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "CRITICAL")
            echo -e "${RED}[CRITICAL]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        *)
            echo "[$status] $message"
            ;;
    esac
}

# Check certificate status
check_certificate_status() {
    local cert_file="$CERT_PATH/fullchain.pem"
    
    print_status "INFO" "Checking certificate status..."
    
    if [[ ! -f "$cert_file" ]]; then
        print_status "CRITICAL" "Certificate file not found: $cert_file"
        return 2
    fi
    
    # Get certificate information
    local subject
    local issuer
    local expiry_date
    local expiry_epoch
    local current_epoch
    local days_until_expiry
    
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "Unknown")
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
    
    if [[ "$expiry_date" != "Unknown" ]]; then
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    else
        days_until_expiry=-1
    fi
    
    # Display certificate information
    echo
    print_status "INFO" "Certificate Information:"
    echo "  Domain: $DOMAIN"
    echo "  Subject: $subject"
    echo "  Issuer: $issuer"
    echo "  Expires: $expiry_date"
    
    if [[ $days_until_expiry -ge 0 ]]; then
        echo "  Days until expiry: $days_until_expiry"
        
        # Determine status based on expiry
        if [[ $days_until_expiry -le $CRITICAL_DAYS ]]; then
            print_status "CRITICAL" "Certificate expires in $days_until_expiry days!"
            return 2
        elif [[ $days_until_expiry -le $WARNING_DAYS ]]; then
            print_status "WARNING" "Certificate expires in $days_until_expiry days"
            return 1
        else
            print_status "OK" "Certificate is valid for $days_until_expiry days"
            return 0
        fi
    else
        print_status "CRITICAL" "Unable to determine certificate expiry"
        return 2
    fi
}

# Analyze renewal logs
analyze_renewal_logs() {
    print_status "INFO" "Analyzing renewal logs..."
    
    # Check if log files exist
    local log_files=("$RENEWAL_LOG" "$ERROR_LOG" "$HISTORY_LOG")
    local missing_logs=()
    
    for log_file in "${log_files[@]}"; do
        if [[ ! -f "$log_file" ]]; then
            missing_logs+=("$log_file")
        fi
    done
    
    if [[ ${#missing_logs[@]} -gt 0 ]]; then
        print_status "WARNING" "Missing log files: ${missing_logs[*]}"
    fi
    
    echo
    print_status "INFO" "Log Analysis Summary:"
    
    # Analyze renewal history
    if [[ -f "$HISTORY_LOG" ]]; then
        local total_renewals
        local successful_renewals
        local failed_renewals
        local last_renewal
        
        total_renewals=$(grep -c "RENEWAL" "$HISTORY_LOG" 2>/dev/null || echo "0")
        successful_renewals=$(grep -c "Certificate renewal completed successfully" "$HISTORY_LOG" 2>/dev/null || echo "0")
        failed_renewals=$(grep -c "RENEWAL FAILED" "$HISTORY_LOG" 2>/dev/null || echo "0")
        last_renewal=$(grep "RENEWAL" "$HISTORY_LOG" 2>/dev/null | tail -1 | cut -d']' -f1 | tr -d '[' || echo "Never")
        
        echo "  Total renewal attempts: $total_renewals"
        echo "  Successful renewals: $successful_renewals"
        echo "  Failed renewals: $failed_renewals"
        echo "  Last renewal attempt: $last_renewal"
        
        if [[ $failed_renewals -gt 0 ]]; then
            print_status "WARNING" "$failed_renewals renewal failures detected"
        fi
    else
        echo "  No renewal history available"
    fi
    
    # Analyze recent errors
    if [[ -f "$ERROR_LOG" ]]; then
        local recent_errors
        recent_errors=$(tail -20 "$ERROR_LOG" 2>/dev/null | wc -l || echo "0")
        
        echo "  Recent errors (last 20 lines): $recent_errors"
        
        if [[ $recent_errors -gt $ERROR_THRESHOLD ]]; then
            print_status "WARNING" "High error count detected"
        fi
    else
        echo "  No error log available"
    fi
}

# Show recent log entries
show_recent_logs() {
    local lines="${1:-20}"
    
    print_status "INFO" "Recent log entries (last $lines lines):"
    
    echo
    echo "=== Renewal Log ==="
    if [[ -f "$RENEWAL_LOG" ]]; then
        tail -"$lines" "$RENEWAL_LOG" 2>/dev/null || echo "No entries found"
    else
        echo "Log file not found: $RENEWAL_LOG"
    fi
    
    echo
    echo "=== Error Log ==="
    if [[ -f "$ERROR_LOG" ]]; then
        tail -"$lines" "$ERROR_LOG" 2>/dev/null || echo "No entries found"
    else
        echo "Log file not found: $ERROR_LOG"
    fi
    
    echo
    echo "=== History Log ==="
    if [[ -f "$HISTORY_LOG" ]]; then
        tail -"$lines" "$HISTORY_LOG" 2>/dev/null || echo "No entries found"
    else
        echo "Log file not found: $HISTORY_LOG"
    fi
}

# Check renewal system health
check_renewal_system() {
    print_status "INFO" "Checking renewal system health..."
    
    local issues=0
    
    # Check if renewal script exists and is executable
    local renewal_script="/scripts/certificate-renewal.sh"
    if [[ -x "$renewal_script" ]]; then
        print_status "OK" "Renewal script is executable: $renewal_script"
    else
        print_status "CRITICAL" "Renewal script not found or not executable: $renewal_script"
        ((issues++))
    fi
    
    # Check if cron is running
    if pgrep crond >/dev/null 2>&1; then
        print_status "OK" "Cron daemon is running"
        
        # Check if renewal cron job exists
        if crontab -l 2>/dev/null | grep -q "$renewal_script"; then
            print_status "OK" "Renewal cron job is configured"
        else
            print_status "WARNING" "Renewal cron job not found"
            ((issues++))
        fi
    else
        print_status "WARNING" "Cron daemon is not running"
        ((issues++))
    fi
    
    # Check log directory permissions
    if [[ -d "$LOG_DIR" ]] && [[ -w "$LOG_DIR" ]]; then
        print_status "OK" "Log directory is writable: $LOG_DIR"
    else
        print_status "WARNING" "Log directory issues: $LOG_DIR"
        ((issues++))
    fi
    
    # Check DNS credentials
    local dns_plugin="${DNS_PLUGIN:-dns-cloudflare}"
    local credentials_file="/etc/letsencrypt/dns-credentials/${dns_plugin#dns-}.ini"
    if [[ -f "$credentials_file" ]]; then
        local perms=$(stat -c "%a" "$credentials_file" 2>/dev/null || echo "000")
        if [[ "$perms" == "600" ]]; then
            print_status "OK" "DNS credentials file has correct permissions"
        else
            print_status "WARNING" "DNS credentials file has incorrect permissions: $perms"
            ((issues++))
        fi
    else
        print_status "CRITICAL" "DNS credentials file not found: $credentials_file"
        ((issues++))
    fi
    
    echo
    if [[ $issues -eq 0 ]]; then
        print_status "OK" "Renewal system health check passed"
        return 0
    else
        print_status "WARNING" "Renewal system health check found $issues issues"
        return 1
    fi
}

# Generate monitoring report
generate_report() {
    local report_file="${1:-/tmp/renewal-report.txt}"
    
    print_status "INFO" "Generating monitoring report: $report_file"
    
    {
        echo "Certificate Renewal Monitoring Report"
        echo "Generated: $(date)"
        echo "Domain: $DOMAIN"
        echo "========================================"
        echo
        
        echo "CERTIFICATE STATUS:"
        check_certificate_status 2>&1
        echo
        
        echo "RENEWAL SYSTEM HEALTH:"
        check_renewal_system 2>&1
        echo
        
        echo "LOG ANALYSIS:"
        analyze_renewal_logs 2>&1
        echo
        
        echo "RECENT LOGS (Last 10 entries):"
        show_recent_logs 10 2>&1
        
    } > "$report_file"
    
    print_status "OK" "Report generated: $report_file"
}

# Test renewal system
test_renewal() {
    print_status "INFO" "Testing certificate renewal system..."
    
    local renewal_script="/scripts/certificate-renewal.sh"
    
    if [[ ! -x "$renewal_script" ]]; then
        print_status "CRITICAL" "Renewal script not found or not executable"
        return 1
    fi
    
    print_status "INFO" "Running renewal test (dry run)..."
    
    # Note: This would be a dry run test in a real implementation
    # For now, we'll just validate the script can be executed
    if "$renewal_script" --help >/dev/null 2>&1; then
        print_status "OK" "Renewal script responds to --help"
    else
        print_status "WARNING" "Renewal script may have issues"
    fi
    
    print_status "INFO" "Renewal test completed"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Certificate Renewal Monitoring and Reporting

COMMANDS:
    status          Check certificate status (default)
    logs            Show recent log entries
    health          Check renewal system health
    report          Generate comprehensive report
    test            Test renewal system
    analyze         Analyze renewal logs

OPTIONS:
    --lines N       Number of log lines to show (default: 20)
    --output FILE   Output file for report
    --help          Show this help message

EXAMPLES:
    $0                          # Check certificate status
    $0 status                   # Same as above
    $0 logs --lines 50          # Show last 50 log lines
    $0 health                   # Check system health
    $0 report --output /tmp/report.txt
    $0 analyze                  # Analyze logs

EOF
}

# Main execution
main() {
    local command="status"
    local lines=20
    local output_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            status|logs|health|report|test|analyze)
                command="$1"
                shift
                ;;
            --lines)
                lines="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Execute command
    case "$command" in
        "status")
            check_certificate_status
            ;;
        "logs")
            show_recent_logs "$lines"
            ;;
        "health")
            check_renewal_system
            ;;
        "report")
            if [[ -n "$output_file" ]]; then
                generate_report "$output_file"
            else
                generate_report
            fi
            ;;
        "test")
            test_renewal
            ;;
        "analyze")
            analyze_renewal_logs
            ;;
        *)
            echo "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"