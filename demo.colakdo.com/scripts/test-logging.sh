#!/bin/bash

# HAProxy Logging Test Script
# Tests the logging configuration and rotation setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$PROJECT_DIR/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[LOGGING TEST]${NC} $1"
}

# Test 1: Check log directory structure
test_log_directory() {
    print_header "Testing log directory structure"
    
    if [ ! -d "$LOGS_DIR" ]; then
        print_error "Logs directory not found: $LOGS_DIR"
        return 1
    fi
    
    print_status "✓ Logs directory exists: $LOGS_DIR"
    
    # Check for required log files
    local required_logs=("haproxy.log" "access.log" "error.log")
    
    for log_file in "${required_logs[@]}"; do
        if [ -f "$LOGS_DIR/$log_file" ]; then
            print_status "✓ Log file exists: $log_file"
        else
            print_error "✗ Missing log file: $log_file"
            return 1
        fi
    done
    
    return 0
}

# Test 2: Check logrotate configuration
test_logrotate_config() {
    print_header "Testing logrotate configuration"
    
    local logrotate_config="$PROJECT_DIR/config/logrotate.conf"
    
    if [ ! -f "$logrotate_config" ]; then
        print_error "Logrotate configuration not found: $logrotate_config"
        return 1
    fi
    
    print_status "✓ Logrotate configuration exists"
    
    # Check for required configuration elements
    local required_configs=("daily" "rotate 30" "compress" "delaycompress" "notifempty")
    
    for config in "${required_configs[@]}"; do
        if grep -q "$config" "$logrotate_config"; then
            print_status "✓ Configuration found: $config"
        else
            print_error "✗ Missing configuration: $config"
            return 1
        fi
    done
    
    return 0
}

# Test 3: Check HAProxy logging configuration
test_haproxy_logging() {
    print_header "Testing HAProxy logging configuration"
    
    local haproxy_config="$PROJECT_DIR/config/haproxy.cfg"
    
    if [ ! -f "$haproxy_config" ]; then
        print_error "HAProxy configuration not found: $haproxy_config"
        return 1
    fi
    
    print_status "✓ HAProxy configuration exists"
    
    # Check for logging configuration
    if grep -q "log syslog:514 local0 info" "$haproxy_config"; then
        print_status "✓ Syslog configuration found"
    else
        print_error "✗ Missing syslog configuration"
        return 1
    fi
    
    if grep -q "log-tag haproxy" "$haproxy_config"; then
        print_status "✓ Log tag configuration found"
    else
        print_error "✗ Missing log tag configuration"
        return 1
    fi
    
    if grep -q "option log-separate-errors" "$haproxy_config"; then
        print_status "✓ Separate error logging enabled"
    else
        print_error "✗ Missing separate error logging configuration"
        return 1
    fi
    
    return 0
}

# Test 4: Check Docker Compose logging services
test_docker_compose() {
    print_header "Testing Docker Compose logging services"
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    if [ ! -f "$compose_file" ]; then
        print_error "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    print_status "✓ Docker Compose file exists"
    
    # Check for syslog service
    if grep -q "syslog:" "$compose_file"; then
        print_status "✓ Syslog service defined"
    else
        print_error "✗ Missing syslog service"
        return 1
    fi
    
    # Check for log-rotator service
    if grep -q "log-rotator:" "$compose_file"; then
        print_status "✓ Log rotator service defined"
    else
        print_error "✗ Missing log rotator service"
        return 1
    fi
    
    # Check for volume mounts
    if grep -q "./logs:/var/log/haproxy" "$compose_file"; then
        print_status "✓ Log volume mounts configured"
    else
        print_error "✗ Missing log volume mounts"
        return 1
    fi
    
    return 0
}

# Test 5: Check log management script
test_log_management_script() {
    print_header "Testing log management script"
    
    local log_script="$PROJECT_DIR/scripts/manage-logs.sh"
    
    if [ ! -f "$log_script" ]; then
        print_error "Log management script not found: $log_script"
        return 1
    fi
    
    if [ ! -x "$log_script" ]; then
        print_error "Log management script is not executable"
        return 1
    fi
    
    print_status "✓ Log management script exists and is executable"
    
    # Test script help function
    if "$log_script" help >/dev/null 2>&1; then
        print_status "✓ Log management script help function works"
    else
        print_error "✗ Log management script help function failed"
        return 1
    fi
    
    # Test script stats function
    if "$log_script" stats >/dev/null 2>&1; then
        print_status "✓ Log management script stats function works"
    else
        print_error "✗ Log management script stats function failed"
        return 1
    fi
    
    return 0
}

# Run all tests
run_all_tests() {
    print_header "Running HAProxy Logging Configuration Tests"
    echo
    
    local tests=(
        "test_log_directory"
        "test_logrotate_config"
        "test_haproxy_logging"
        "test_docker_compose"
        "test_log_management_script"
    )
    
    local passed=0
    local total=${#tests[@]}
    
    for test in "${tests[@]}"; do
        echo
        if $test; then
            ((passed++))
        fi
    done
    
    echo
    print_header "Test Results: $passed/$total tests passed"
    
    if [ $passed -eq $total ]; then
        print_status "✓ All logging tests passed!"
        return 0
    else
        print_error "✗ Some tests failed. Please check the configuration."
        return 1
    fi
}

# Main execution
case "${1:-all}" in
    "directory")
        test_log_directory
        ;;
    "logrotate")
        test_logrotate_config
        ;;
    "haproxy")
        test_haproxy_logging
        ;;
    "compose")
        test_docker_compose
        ;;
    "script")
        test_log_management_script
        ;;
    "all")
        run_all_tests
        ;;
    *)
        echo "Usage: $0 [directory|logrotate|haproxy|compose|script|all]"
        exit 1
        ;;
esac