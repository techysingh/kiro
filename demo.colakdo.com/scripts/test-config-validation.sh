#!/bin/bash

#---------------------------------------------------------------------
# Test Script for HAProxy Configuration Validation and Reload
# Tests all aspects of the configuration management system
#---------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/haproxy.cfg"
BACKUP_DIR="$PROJECT_DIR/config/backups"
LOG_DIR="$PROJECT_DIR/logs"
TEST_LOG="$LOG_DIR/test-config-validation.log"

# Test configuration
TEST_CONFIG_DIR="/tmp/haproxy-test-$$"
TEST_CONFIG_FILE="$TEST_CONFIG_DIR/haproxy.cfg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG"
    
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
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

# Test framework functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    log "INFO" "Running test: $test_name"
    
    if $test_function; then
        ((TESTS_PASSED++))
        log "INFO" "✓ PASSED: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        log "ERROR" "✗ FAILED: $test_name"
        return 1
    fi
}

setup_test_environment() {
    log "INFO" "Setting up test environment"
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Copy original config for testing
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$TEST_CONFIG_FILE"
    else
        log "ERROR" "Original config file not found: $CONFIG_FILE"
        return 1
    fi
    
    log "INFO" "Test environment setup complete"
    return 0
}

cleanup_test_environment() {
    log "INFO" "Cleaning up test environment"
    
    # Remove test directory
    if [ -d "$TEST_CONFIG_DIR" ]; then
        rm -rf "$TEST_CONFIG_DIR"
    fi
    
    log "INFO" "Test environment cleanup complete"
}

# Test functions
test_validation_script_exists() {
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    
    if [ -f "$validation_script" ] && [ -x "$validation_script" ]; then
        return 0
    else
        log "ERROR" "Validation script not found or not executable: $validation_script"
        return 1
    fi
}

test_reload_script_exists() {
    local reload_script="$SCRIPT_DIR/haproxy-config-reload.sh"
    
    if [ -f "$reload_script" ] && [ -x "$reload_script" ]; then
        return 0
    else
        log "ERROR" "Reload script not found or not executable: $reload_script"
        return 1
    fi
}

test_watcher_script_exists() {
    local watcher_script="$SCRIPT_DIR/haproxy-config-watcher.sh"
    
    if [ -f "$watcher_script" ] && [ -x "$watcher_script" ]; then
        return 0
    else
        log "ERROR" "Watcher script not found or not executable: $watcher_script"
        return 1
    fi
}

test_valid_config_validation() {
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    
    # Test with valid configuration
    if "$validation_script" --syntax-only "$TEST_CONFIG_FILE" >/dev/null 2>&1; then
        log "DEBUG" "Valid configuration passed validation"
        return 0
    else
        log "ERROR" "Valid configuration failed validation"
        return 1
    fi
}

test_invalid_config_validation() {
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    local invalid_config="$TEST_CONFIG_DIR/invalid.cfg"
    
    # Create invalid configuration (missing required sections)
    cat > "$invalid_config" << 'EOF'
# Invalid HAProxy configuration - missing required sections
global
    daemon
# Missing defaults, frontend, and backend sections
EOF
    
    # Test with invalid configuration using comprehensive check (should fail)
    if "$validation_script" --full-check "$invalid_config" >/dev/null 2>&1; then
        log "ERROR" "Invalid configuration passed validation (should have failed)"
        return 1
    else
        log "DEBUG" "Invalid configuration correctly failed validation"
        return 0
    fi
}

test_validation_comprehensive_check() {
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    
    # Test comprehensive validation (not just syntax)
    if "$validation_script" --full-check "$TEST_CONFIG_FILE" >/dev/null 2>&1; then
        log "DEBUG" "Comprehensive validation passed"
        return 0
    else
        log "ERROR" "Comprehensive validation failed"
        return 1
    fi
}

test_backup_creation() {
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    local test_backup_dir="$TEST_CONFIG_DIR/backups"
    
    # Set backup directory for test
    export BACKUP_DIR="$test_backup_dir"
    
    # Run validation with backup
    if "$validation_script" --backup "$TEST_CONFIG_FILE" >/dev/null 2>&1; then
        # Check if backup was created
        if [ -d "$test_backup_dir" ] && [ "$(find "$test_backup_dir" -name "haproxy.cfg.*" | wc -l)" -gt 0 ]; then
            log "DEBUG" "Backup creation successful"
            return 0
        else
            log "ERROR" "Backup directory created but no backup files found"
            return 1
        fi
    else
        log "ERROR" "Validation with backup failed"
        return 1
    fi
}

test_reload_script_test_mode() {
    local reload_script="$SCRIPT_DIR/haproxy-config-reload.sh"
    
    # Test reload script in test-only mode
    if "$reload_script" --test-only "$TEST_CONFIG_FILE" >/dev/null 2>&1; then
        log "DEBUG" "Reload script test mode passed"
        return 0
    else
        log "ERROR" "Reload script test mode failed"
        return 1
    fi
}

test_reload_script_validation_failure() {
    local reload_script="$SCRIPT_DIR/haproxy-config-reload.sh"
    local invalid_config="$TEST_CONFIG_DIR/invalid_reload.cfg"
    
    # Create invalid configuration (missing required sections)
    cat > "$invalid_config" << 'EOF'
# Invalid HAProxy configuration - missing required sections
global
    daemon
# Missing defaults, frontend, and backend sections
EOF
    
    # Test reload script with invalid config (should fail)
    if "$reload_script" --test-only "$invalid_config" >/dev/null 2>&1; then
        log "ERROR" "Reload script accepted invalid configuration"
        return 1
    else
        log "DEBUG" "Reload script correctly rejected invalid configuration"
        return 0
    fi
}

test_watcher_script_help() {
    local watcher_script="$SCRIPT_DIR/haproxy-config-watcher.sh"
    
    # Test watcher script help
    if "$watcher_script" --help >/dev/null 2>&1; then
        log "DEBUG" "Watcher script help displayed successfully"
        return 0
    else
        log "ERROR" "Watcher script help failed"
        return 1
    fi
}

test_config_file_checksum_detection() {
    local test_file="$TEST_CONFIG_DIR/checksum_test.cfg"
    
    # Copy original config
    cp "$TEST_CONFIG_FILE" "$test_file"
    
    # Get initial checksum
    local checksum1
    checksum1=$(sha256sum "$test_file" | cut -d' ' -f1)
    
    # Modify file
    echo "# Test modification" >> "$test_file"
    
    # Get new checksum
    local checksum2
    checksum2=$(sha256sum "$test_file" | cut -d' ' -f1)
    
    # Checksums should be different
    if [ "$checksum1" != "$checksum2" ]; then
        log "DEBUG" "Checksum detection working correctly"
        return 0
    else
        log "ERROR" "Checksum detection failed - checksums are identical"
        return 1
    fi
}

test_docker_compose_config_watcher_service() {
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check if config-watcher service is defined
    if grep -q "config-watcher:" "$compose_file"; then
        log "DEBUG" "Config watcher service found in Docker Compose"
        
        # Check for required volumes
        if grep -A 20 "config-watcher:" "$compose_file" | grep -q "./config:/usr/local/etc/haproxy:ro"; then
            log "DEBUG" "Config volume mount found"
            return 0
        else
            log "ERROR" "Config volume mount not found in config-watcher service"
            return 1
        fi
    else
        log "ERROR" "Config watcher service not found in Docker Compose"
        return 1
    fi
}

test_script_permissions() {
    local scripts=(
        "$SCRIPT_DIR/validate-haproxy-config.sh"
        "$SCRIPT_DIR/haproxy-config-reload.sh"
        "$SCRIPT_DIR/haproxy-config-watcher.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -x "$script" ]; then
            log "ERROR" "Script not executable: $script"
            return 1
        fi
    done
    
    log "DEBUG" "All scripts have correct permissions"
    return 0
}

test_log_directory_creation() {
    local test_log_dir="$TEST_CONFIG_DIR/logs"
    
    # Test log directory creation
    export LOG_FILE="$test_log_dir/test.log"
    
    # Run validation script to trigger log directory creation
    local validation_script="$SCRIPT_DIR/validate-haproxy-config.sh"
    "$validation_script" --syntax-only "$TEST_CONFIG_FILE" >/dev/null 2>&1 || true
    
    if [ -d "$test_log_dir" ]; then
        log "DEBUG" "Log directory creation successful"
        return 0
    else
        log "ERROR" "Log directory was not created"
        return 1
    fi
}

# Main test execution
main() {
    log "INFO" "Starting HAProxy configuration validation and reload tests"
    
    # Setup test environment
    if ! setup_test_environment; then
        log "ERROR" "Failed to setup test environment"
        exit 1
    fi
    
    # Run tests
    run_test "Validation script exists and is executable" test_validation_script_exists
    run_test "Reload script exists and is executable" test_reload_script_exists
    run_test "Watcher script exists and is executable" test_watcher_script_exists
    run_test "Valid configuration passes validation" test_valid_config_validation
    run_test "Invalid configuration fails validation" test_invalid_config_validation
    run_test "Comprehensive validation check" test_validation_comprehensive_check
    run_test "Backup creation functionality" test_backup_creation
    run_test "Reload script test mode" test_reload_script_test_mode
    run_test "Reload script rejects invalid config" test_reload_script_validation_failure
    run_test "Watcher script help functionality" test_watcher_script_help
    run_test "Configuration file checksum detection" test_config_file_checksum_detection
    run_test "Docker Compose config watcher service" test_docker_compose_config_watcher_service
    run_test "Script permissions are correct" test_script_permissions
    run_test "Log directory creation" test_log_directory_creation
    
    # Cleanup
    cleanup_test_environment
    
    # Test summary
    log "INFO" "Test execution completed"
    log "INFO" "Tests run: $TESTS_RUN"
    log "INFO" "Tests passed: $TESTS_PASSED"
    log "INFO" "Tests failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log "INFO" "All tests passed! ✓"
        exit 0
    else
        log "ERROR" "Some tests failed! ✗"
        exit 1
    fi
}

# Signal handlers
trap 'cleanup_test_environment; exit 130' INT TERM

# Run main function
main "$@"