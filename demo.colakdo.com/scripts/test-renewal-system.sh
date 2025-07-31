#!/bin/bash

# Test Script for Certificate Renewal System
# Validates all components of the automated renewal system

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
LOG_FILE="/var/log/letsencrypt/test-renewal.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Test result functions
test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    log "PASS: $1"
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    log "FAIL: $1"
}

test_skip() {
    echo -e "${YELLOW}⚠ SKIP${NC}: $1"
    log "SKIP: $1"
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
    log "INFO: $1"
}

# Test script existence and permissions
test_script_files() {
    test_info "Testing script files..."
    
    local scripts=(
        "/scripts/certificate-renewal.sh"
        "/scripts/setup-renewal-cron.sh"
        "/scripts/renewal-monitor.sh"
        "/scripts/combine-certs.sh"
        "/scripts/certbot-manager.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                test_pass "Script exists and is executable: $script"
            else
                test_fail "Script exists but is not executable: $script"
            fi
        else
            test_fail "Script not found: $script"
        fi
    done
}

# Test log directory structure
test_log_directories() {
    test_info "Testing log directory structure..."
    
    local log_dirs=(
        "/var/log/letsencrypt"
        "/var/log/haproxy"
    )
    
    for dir in "${log_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -w "$dir" ]]; then
                test_pass "Log directory exists and is writable: $dir"
            else
                test_fail "Log directory exists but is not writable: $dir"
            fi
        else
            test_fail "Log directory not found: $dir"
        fi
    done
}

# Test DNS credentials
test_dns_credentials() {
    test_info "Testing DNS credentials..."
    
    local dns_plugin="${DNS_PLUGIN:-dns-cloudflare}"
    local credentials_file="/etc/letsencrypt/dns-credentials/${dns_plugin#dns-}.ini"
    
    if [[ -f "$credentials_file" ]]; then
        local perms=$(stat -c "%a" "$credentials_file" 2>/dev/null || echo "000")
        if [[ "$perms" == "600" ]]; then
            test_pass "DNS credentials file has correct permissions (600)"
        else
            test_fail "DNS credentials file has incorrect permissions: $perms (should be 600)"
        fi
        
        if [[ -s "$credentials_file" ]]; then
            test_pass "DNS credentials file is not empty"
        else
            test_fail "DNS credentials file is empty"
        fi
    else
        test_fail "DNS credentials file not found: $credentials_file"
    fi
}

# Test certificate renewal script functionality
test_renewal_script() {
    test_info "Testing certificate renewal script functionality..."
    
    local renewal_script="/scripts/certificate-renewal.sh"
    
    if [[ -x "$renewal_script" ]]; then
        # Test help option
        if "$renewal_script" --help >/dev/null 2>&1; then
            test_pass "Renewal script responds to --help"
        else
            test_fail "Renewal script does not respond to --help"
        fi
        
        # Test environment validation (without actually running renewal)
        # This would require modifying the script to have a --validate-only option
        test_info "Renewal script basic functionality test completed"
    else
        test_fail "Renewal script not executable"
    fi
}

# Test cron setup functionality
test_cron_setup() {
    test_info "Testing cron setup functionality..."
    
    local cron_script="/scripts/setup-renewal-cron.sh"
    
    if [[ -x "$cron_script" ]]; then
        # Test help option
        if "$cron_script" --help >/dev/null 2>&1; then
            test_pass "Cron setup script responds to --help"
        else
            test_fail "Cron setup script does not respond to --help"
        fi
        
        # Check if cron is available
        if command -v crontab >/dev/null 2>&1; then
            test_pass "Crontab command is available"
        else
            test_fail "Crontab command not found"
        fi
    else
        test_fail "Cron setup script not executable"
    fi
}

# Test monitoring script functionality
test_monitoring_script() {
    test_info "Testing monitoring script functionality..."
    
    local monitor_script="/scripts/renewal-monitor.sh"
    
    if [[ -x "$monitor_script" ]]; then
        # Test help option
        if "$monitor_script" --help >/dev/null 2>&1; then
            test_pass "Monitoring script responds to --help"
        else
            test_fail "Monitoring script does not respond to --help"
        fi
        
        # Test status command (should work even without certificates)
        if "$monitor_script" status >/dev/null 2>&1; then
            test_pass "Monitoring script status command works"
        else
            test_info "Monitoring script status command failed (expected if no certificates)"
        fi
    else
        test_fail "Monitoring script not executable"
    fi
}

# Test certificate directory structure
test_certificate_directories() {
    test_info "Testing certificate directory structure..."
    
    local cert_dirs=(
        "/etc/letsencrypt"
        "/etc/ssl/certs"
        "/etc/letsencrypt/dns-credentials"
    )
    
    for dir in "${cert_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            test_pass "Certificate directory exists: $dir"
        else
            test_fail "Certificate directory not found: $dir"
        fi
    done
}

# Test environment variables
test_environment_variables() {
    test_info "Testing environment variables..."
    
    local required_vars=(
        "DOMAIN"
        "EMAIL"
        "DNS_PLUGIN"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            test_pass "Environment variable set: $var=${!var}"
        else
            test_fail "Environment variable not set: $var"
        fi
    done
}

# Test HAProxy integration
test_haproxy_integration() {
    test_info "Testing HAProxy integration..."
    
    # Check if HAProxy container is running (if in Docker environment)
    if command -v docker >/dev/null 2>&1; then
        if docker ps --format "{{.Names}}" | grep -q "haproxy-proxy"; then
            test_pass "HAProxy container is running"
        else
            test_info "HAProxy container not found (may not be started yet)"
        fi
    else
        test_info "Docker not available, skipping container check"
    fi
    
    # Check if combine-certs script exists
    local combine_script="/scripts/combine-certs.sh"
    if [[ -x "$combine_script" ]]; then
        test_pass "Certificate combination script is executable"
    else
        test_fail "Certificate combination script not found or not executable"
    fi
}

# Test system dependencies
test_system_dependencies() {
    test_info "Testing system dependencies..."
    
    local commands=(
        "openssl"
        "certbot"
        "curl"
    )
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            test_pass "Command available: $cmd"
        else
            test_fail "Command not found: $cmd"
        fi
    done
}

# Generate test report
generate_test_report() {
    echo
    echo "========================================"
    echo "Certificate Renewal System Test Report"
    echo "========================================"
    echo "Domain: $DOMAIN"
    echo "Test Date: $(date)"
    echo "Log File: $LOG_FILE"
    echo
    echo "Results:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
        echo "The certificate renewal system appears to be properly configured."
        return 0
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
        echo "Please review the failed tests and fix the issues before proceeding."
        return 1
    fi
}

# Main test execution
main() {
    echo "Starting Certificate Renewal System Tests..."
    echo "============================================="
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run all tests
    test_script_files
    test_log_directories
    test_dns_credentials
    test_certificate_directories
    test_environment_variables
    test_system_dependencies
    test_renewal_script
    test_cron_setup
    test_monitoring_script
    test_haproxy_integration
    
    # Generate report
    generate_test_report
}

# Execute main function
main "$@"