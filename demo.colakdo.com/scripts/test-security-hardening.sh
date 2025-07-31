#!/bin/bash

#---------------------------------------------------------------------
# Security Hardening Test Script
# Tests the implemented security features and configurations
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-colakdo.com}"
HAPROXY_HOST="${HAPROXY_HOST:-localhost}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
STATS_PORT="${STATS_PORT:-8404}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging function
log_test() {
    local status="$1"
    local test_name="$2"
    local details="${3:-}"
    
    ((TESTS_TOTAL++))
    
    case "$status" in
        PASS)
            echo -e "${GREEN}✓ PASS${NC}: $test_name"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}✗ FAIL${NC}: $test_name"
            [[ -n "$details" ]] && echo -e "  ${RED}Details: $details${NC}"
            ((TESTS_FAILED++))
            ;;
        SKIP)
            echo -e "${YELLOW}⚠ SKIP${NC}: $test_name"
            [[ -n "$details" ]] && echo -e "  ${YELLOW}Reason: $details${NC}"
            ;;
        INFO)
            echo -e "${BLUE}ℹ INFO${NC}: $test_name"
            [[ -n "$details" ]] && echo -e "  ${BLUE}$details${NC}"
            ;;
    esac
}

# Test HTTP rejection
test_http_rejection() {
    log_test "INFO" "Testing HTTP traffic rejection"
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -o /dev/null -w "%{http_code}" "http://$HAPROXY_HOST:$HTTP_PORT/" 2>/dev/null || echo "000")
        
        if [[ "$response" == "403" ]]; then
            log_test "PASS" "HTTP requests return 403 Forbidden"
        else
            log_test "FAIL" "HTTP requests return $response instead of 403"
        fi
    else
        log_test "SKIP" "HTTP rejection test" "curl not available"
    fi
}

# Test HTTPS security headers
test_security_headers() {
    log_test "INFO" "Testing HTTPS security headers"
    
    if command -v curl >/dev/null 2>&1; then
        local headers=$(curl -s -I -k "https://$HAPROXY_HOST:$HTTPS_PORT/" 2>/dev/null || echo "")
        
        # Test HSTS header
        if echo "$headers" | grep -qi "strict-transport-security"; then
            local hsts_value=$(echo "$headers" | grep -i "strict-transport-security" | cut -d: -f2- | tr -d ' \r\n')
            if echo "$hsts_value" | grep -q "max-age=63072000"; then
                log_test "PASS" "HSTS header with correct max-age"
            else
                log_test "FAIL" "HSTS header has incorrect max-age: $hsts_value"
            fi
        else
            log_test "FAIL" "HSTS header missing"
        fi
        
        # Test X-Content-Type-Options
        if echo "$headers" | grep -qi "x-content-type-options.*nosniff"; then
            log_test "PASS" "X-Content-Type-Options header present"
        else
            log_test "FAIL" "X-Content-Type-Options header missing or incorrect"
        fi
        
        # Test X-Frame-Options
        if echo "$headers" | grep -qi "x-frame-options"; then
            log_test "PASS" "X-Frame-Options header present"
        else
            log_test "FAIL" "X-Frame-Options header missing"
        fi
        
        # Test CSP header
        if echo "$headers" | grep -qi "content-security-policy"; then
            log_test "PASS" "Content-Security-Policy header present"
        else
            log_test "FAIL" "Content-Security-Policy header missing"
        fi
        
        # Test Referrer-Policy
        if echo "$headers" | grep -qi "referrer-policy"; then
            log_test "PASS" "Referrer-Policy header present"
        else
            log_test "FAIL" "Referrer-Policy header missing"
        fi
        
    else
        log_test "SKIP" "Security headers test" "curl not available"
    fi
}

# Test SSL/TLS configuration
test_ssl_configuration() {
    log_test "INFO" "Testing SSL/TLS configuration"
    
    if command -v openssl >/dev/null 2>&1; then
        # Test TLS version support
        local tls12_support=$(echo | openssl s_client -connect "$HAPROXY_HOST:$HTTPS_PORT" -tls1_2 2>/dev/null | grep -c "Verify return code: 0" || echo "0")
        if [[ "$tls12_support" -gt 0 ]]; then
            log_test "PASS" "TLS 1.2 supported"
        else
            log_test "FAIL" "TLS 1.2 not supported"
        fi
        
        # Test TLS 1.0 rejection (should fail)
        local tls10_rejected=$(echo | openssl s_client -connect "$HAPROXY_HOST:$HTTPS_PORT" -tls1 2>/dev/null | grep -c "handshake failure\|protocol version" || echo "0")
        if [[ "$tls10_rejected" -gt 0 ]]; then
            log_test "PASS" "TLS 1.0 properly rejected"
        else
            log_test "FAIL" "TLS 1.0 not rejected"
        fi
        
        # Test cipher suites
        local cipher_info=$(echo | openssl s_client -connect "$HAPROXY_HOST:$HTTPS_PORT" -cipher 'ECDHE' 2>/dev/null | grep "Cipher" || echo "")
        if echo "$cipher_info" | grep -q "ECDHE"; then
            log_test "PASS" "ECDHE cipher suites supported"
        else
            log_test "FAIL" "ECDHE cipher suites not found"
        fi
        
    else
        log_test "SKIP" "SSL/TLS configuration test" "openssl not available"
    fi
}

# Test HAProxy statistics interface
test_stats_interface() {
    log_test "INFO" "Testing HAProxy statistics interface"
    
    if command -v curl >/dev/null 2>&1; then
        # Test stats endpoint accessibility
        local stats_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$HAPROXY_HOST:$STATS_PORT/stats" 2>/dev/null || echo "000")
        
        if [[ "$stats_response" == "200" ]]; then
            log_test "PASS" "Statistics interface accessible"
        else
            log_test "FAIL" "Statistics interface returned $stats_response"
        fi
        
        # Test health endpoint
        local health_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$HAPROXY_HOST:$STATS_PORT/health" 2>/dev/null || echo "000")
        
        if [[ "$health_response" == "200" ]]; then
            log_test "PASS" "Health endpoint accessible"
        else
            log_test "FAIL" "Health endpoint returned $health_response"
        fi
        
        # Test rate limiting (make multiple rapid requests)
        local rate_limit_test=0
        for i in {1..25}; do
            local response=$(curl -s -o /dev/null -w "%{http_code}" "http://$HAPROXY_HOST:$STATS_PORT/stats" 2>/dev/null || echo "000")
            if [[ "$response" == "429" || "$response" == "403" ]]; then
                rate_limit_test=1
                break
            fi
            sleep 0.1
        done
        
        if [[ "$rate_limit_test" -eq 1 ]]; then
            log_test "PASS" "Rate limiting active on stats interface"
        else
            log_test "FAIL" "Rate limiting not detected on stats interface"
        fi
        
    else
        log_test "SKIP" "Statistics interface test" "curl not available"
    fi
}

# Test certificate monitoring
test_certificate_monitoring() {
    log_test "INFO" "Testing certificate monitoring"
    
    if [[ -x "/scripts/certificate-expiration-monitor.sh" ]]; then
        # Test certificate monitoring script
        if /scripts/certificate-expiration-monitor.sh health >/dev/null 2>&1; then
            log_test "PASS" "Certificate monitoring script functional"
        else
            log_test "FAIL" "Certificate monitoring script failed"
        fi
        
        # Test JSON output
        local json_output=$(/scripts/certificate-expiration-monitor.sh json 2>/dev/null || echo "{}")
        if echo "$json_output" | grep -q '"status"'; then
            log_test "PASS" "Certificate monitoring JSON output functional"
        else
            log_test "FAIL" "Certificate monitoring JSON output failed"
        fi
        
    else
        log_test "SKIP" "Certificate monitoring test" "Script not found or not executable"
    fi
}

# Test HAProxy monitoring
test_haproxy_monitoring() {
    log_test "INFO" "Testing HAProxy monitoring"
    
    if [[ -x "/scripts/haproxy-monitor.sh" ]]; then
        # Test HAProxy monitoring script
        if /scripts/haproxy-monitor.sh health >/dev/null 2>&1; then
            log_test "PASS" "HAProxy monitoring script functional"
        else
            log_test "FAIL" "HAProxy monitoring script failed"
        fi
        
        # Test metrics collection
        if /scripts/haproxy-monitor.sh metrics >/dev/null 2>&1; then
            log_test "PASS" "HAProxy metrics collection functional"
        else
            log_test "FAIL" "HAProxy metrics collection failed"
        fi
        
    else
        log_test "SKIP" "HAProxy monitoring test" "Script not found or not executable"
    fi
}

# Test configuration validation
test_configuration_validation() {
    log_test "INFO" "Testing configuration validation"
    
    if [[ -x "/scripts/validate-haproxy-config.sh" ]]; then
        if /scripts/validate-haproxy-config.sh >/dev/null 2>&1; then
            log_test "PASS" "HAProxy configuration validation passed"
        else
            log_test "FAIL" "HAProxy configuration validation failed"
        fi
    else
        log_test "SKIP" "Configuration validation test" "Script not found or not executable"
    fi
    
    # Test configuration file syntax
    if command -v haproxy >/dev/null 2>&1; then
        if haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
            log_test "PASS" "HAProxy configuration syntax valid"
        else
            log_test "FAIL" "HAProxy configuration syntax invalid"
        fi
    else
        log_test "SKIP" "Configuration syntax test" "haproxy command not available"
    fi
}

# Generate security report
generate_security_report() {
    echo
    echo "=================================================="
    echo "Security Hardening Test Report"
    echo "=================================================="
    echo "Domain: $DOMAIN"
    echo "HAProxy Host: $HAPROXY_HOST"
    echo "Test Date: $(date)"
    echo
    echo "Test Results:"
    echo "- Total Tests: $TESTS_TOTAL"
    echo "- Passed: $TESTS_PASSED"
    echo "- Failed: $TESTS_FAILED"
    echo "- Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All security tests passed!${NC}"
        echo "The HAProxy security hardening implementation is working correctly."
    else
        echo -e "${RED}⚠ Some security tests failed.${NC}"
        echo "Please review the failed tests and address any security issues."
    fi
    
    echo "=================================================="
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --domain DOMAIN     Domain to test (default: colakdo.com)
    --host HOST         HAProxy host (default: localhost)
    --http-port PORT    HTTP port (default: 80)
    --https-port PORT   HTTPS port (default: 443)
    --stats-port PORT   Stats port (default: 8404)
    --help              Show this help message

Examples:
    $0                                    # Run all tests with defaults
    $0 --domain example.com --host proxy  # Test specific domain and host
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --host)
            HAPROXY_HOST="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --https-port)
            HTTPS_PORT="$2"
            shift 2
            ;;
        --stats-port)
            STATS_PORT="$2"
            shift 2
            ;;
        --help|-h)
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

# Main test execution
main() {
    echo "Starting Security Hardening Tests..."
    echo "Domain: $DOMAIN"
    echo "HAProxy Host: $HAPROXY_HOST"
    echo
    
    # Run all tests
    test_http_rejection
    test_security_headers
    test_ssl_configuration
    test_stats_interface
    test_certificate_monitoring
    test_haproxy_monitoring
    test_configuration_validation
    
    # Generate report
    generate_security_report
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main