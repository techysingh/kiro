#!/bin/bash
"""
Service Health Checker for HAProxy Stack
Provides comprehensive health checks for all stack components
"""

set -euo pipefail

# Configuration
SERVICE_NAME="${1:-}"
HEALTH_CHECK_TIMEOUT=10
LOG_FILE="/var/log/haproxy/health-checks.log"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [$SERVICE_NAME] $message" >> "$LOG_FILE"
    
    # Also output to stdout for Docker health check
    if [[ "$level" == "ERROR" ]]; then
        echo "UNHEALTHY: $message" >&2
    fi
}

# HAProxy health check
check_haproxy_health() {
    log "DEBUG" "Checking HAProxy health"
    
    # Check if HAProxy process is running
    if ! pgrep -f "haproxy.*master" >/dev/null; then
        log "ERROR" "HAProxy master process not found"
        return 1
    fi
    
    # Check stats endpoint
    if ! curl -f -s --max-time "$HEALTH_CHECK_TIMEOUT" \
         "http://localhost:8404/health" >/dev/null 2>&1; then
        log "ERROR" "HAProxy stats endpoint not responding"
        return 1
    fi
    
    # Check if HAProxy is accepting connections on port 443
    if ! timeout "$HEALTH_CHECK_TIMEOUT" bash -c '</dev/tcp/localhost/443' 2>/dev/null; then
        log "ERROR" "HAProxy not accepting HTTPS connections"
        return 1
    fi
    
    # Check configuration validity
    if ! haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        log "ERROR" "HAProxy configuration is invalid"
        return 1
    fi
    
    log "DEBUG" "HAProxy health check passed"
    return 0
}

# Certbot health check
check_certbot_health() {
    log "DEBUG" "Checking Certbot health"
    
    # Check if certificate files exist
    local cert_file="/etc/letsencrypt/live/colakdo.com/fullchain.pem"
    local key_file="/etc/letsencrypt/live/colakdo.com/privkey.pem"
    
    if [[ ! -f "$cert_file" ]]; then
        log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log "ERROR" "Private key file not found: $key_file"
        return 1
    fi
    
    # Check certificate validity
    if ! openssl x509 -in "$cert_file" -noout -checkend 86400 >/dev/null 2>&1; then
        log "ERROR" "Certificate expires within 24 hours or is invalid"
        return 1
    fi
    
    # Check if certbot can run
    if ! certbot --version >/dev/null 2>&1; then
        log "ERROR" "Certbot command not available"
        return 1
    fi
    
    # Check renewal configuration
    local renewal_config="/etc/letsencrypt/renewal/colakdo.com.conf"
    if [[ ! -f "$renewal_config" ]]; then
        log "ERROR" "Renewal configuration not found: $renewal_config"
        return 1
    fi
    
    log "DEBUG" "Certbot health check passed"
    return 0
}

# Syslog health check
check_syslog_health() {
    log "DEBUG" "Checking Syslog health"
    
    # Check if rsyslog process is running
    if ! pgrep rsyslogd >/dev/null; then
        log "ERROR" "Rsyslog daemon not running"
        return 1
    fi
    
    # Check if syslog is listening on UDP 514
    if ! netstat -ulnp 2>/dev/null | grep -q ":514 "; then
        log "ERROR" "Syslog not listening on UDP port 514"
        return 1
    fi
    
    # Check if log directory is writable
    if [[ ! -w "/var/log/haproxy" ]]; then
        log "ERROR" "Log directory not writable: /var/log/haproxy"
        return 1
    fi
    
    # Test log writing
    local test_message="Health check test message $(date)"
    if ! logger -p local0.info "$test_message" 2>/dev/null; then
        log "ERROR" "Cannot write to syslog"
        return 1
    fi
    
    log "DEBUG" "Syslog health check passed"
    return 0
}

# Monitor service health check
check_monitor_health() {
    log "DEBUG" "Checking Monitor service health"
    
    # Check if monitoring scripts are running
    if ! pgrep -f "haproxy-monitor.sh" >/dev/null; then
        log "ERROR" "HAProxy monitor script not running"
        return 1
    fi
    
    # Check if certificate monitor is running
    if ! pgrep -f "certificate-expiration-monitor.sh" >/dev/null; then
        log "ERROR" "Certificate expiration monitor not running"
        return 1
    fi
    
    # Check if monitor log file is being updated
    local monitor_log="/var/log/haproxy/monitor.log"
    if [[ -f "$monitor_log" ]]; then
        local last_update
        last_update=$(stat -c %Y "$monitor_log" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local time_diff=$((current_time - last_update))
        
        # If log hasn't been updated in 10 minutes, consider unhealthy
        if [[ $time_diff -gt 600 ]]; then
            log "ERROR" "Monitor log not updated for $time_diff seconds"
            return 1
        fi
    fi
    
    log "DEBUG" "Monitor service health check passed"
    return 0
}

# Maintenance server health check
check_maintenance_health() {
    log "DEBUG" "Checking Maintenance server health"
    
    # Check if maintenance server is responding
    if ! curl -f -s --max-time "$HEALTH_CHECK_TIMEOUT" \
         "http://localhost:8080/health" >/dev/null 2>&1; then
        log "ERROR" "Maintenance server not responding on port 8080"
        return 1
    fi
    
    # Check if Python process is running
    if ! pgrep -f "maintenance-server.py" >/dev/null; then
        log "ERROR" "Maintenance server Python process not found"
        return 1
    fi
    
    # Test different health endpoints
    local endpoints=("/health" "/api/health" "/app/health" "/admin/health" "/demo/health")
    for endpoint in "${endpoints[@]}"; do
        if ! curl -f -s --max-time 5 "http://localhost:8080$endpoint" >/dev/null 2>&1; then
            log "ERROR" "Maintenance server endpoint not responding: $endpoint"
            return 1
        fi
    done
    
    log "DEBUG" "Maintenance server health check passed"
    return 0
}

# Backend discovery health check
check_backend_discovery_health() {
    log "DEBUG" "Checking Backend Discovery health"
    
    # Check if backend discovery script is running
    if ! pgrep -f "backend-discovery.sh" >/dev/null; then
        log "ERROR" "Backend discovery script not running"
        return 1
    fi
    
    # Check if Docker socket is accessible
    if [[ ! -S "/var/run/docker.sock" ]]; then
        log "ERROR" "Docker socket not accessible"
        return 1
    fi
    
    # Test Docker connectivity
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Docker daemon"
        return 1
    fi
    
    # Check if proxy-network exists
    if ! docker network ls --format "{{.Name}}" | grep -q "^proxy-network$"; then
        log "ERROR" "Proxy network not found"
        return 1
    fi
    
    # Check if discovery log is being updated
    local discovery_log="/var/log/haproxy/backend-discovery.log"
    if [[ -f "$discovery_log" ]]; then
        local last_update
        last_update=$(stat -c %Y "$discovery_log" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local time_diff=$((current_time - last_update))
        
        # If log hasn't been updated in 5 minutes, consider unhealthy
        if [[ $time_diff -gt 300 ]]; then
            log "ERROR" "Backend discovery log not updated for $time_diff seconds"
            return 1
        fi
    fi
    
    log "DEBUG" "Backend discovery health check passed"
    return 0
}

# Config watcher health check
check_config_watcher_health() {
    log "DEBUG" "Checking Config Watcher health"
    
    # Check if config watcher script is running
    if ! pgrep -f "haproxy-config-watcher.sh" >/dev/null; then
        log "ERROR" "Config watcher script not running"
        return 1
    fi
    
    # Check if inotify tools are available
    if ! command -v inotifywait >/dev/null 2>&1; then
        log "ERROR" "inotifywait command not available"
        return 1
    fi
    
    # Check if configuration directory is accessible
    if [[ ! -d "/usr/local/etc/haproxy" ]]; then
        log "ERROR" "HAProxy configuration directory not accessible"
        return 1
    fi
    
    # Check if main configuration file exists
    if [[ ! -f "/usr/local/etc/haproxy/haproxy.cfg" ]]; then
        log "ERROR" "HAProxy configuration file not found"
        return 1
    fi
    
    log "DEBUG" "Config watcher health check passed"
    return 0
}

# Log rotator health check
check_log_rotator_health() {
    log "DEBUG" "Checking Log Rotator health"
    
    # Check if logrotate is available
    if ! command -v logrotate >/dev/null 2>&1; then
        log "ERROR" "logrotate command not available"
        return 1
    fi
    
    # Check if logrotate configuration exists
    if [[ ! -f "/etc/logrotate.d/haproxy" ]]; then
        log "ERROR" "Logrotate configuration not found"
        return 1
    fi
    
    # Check if log directory is accessible
    if [[ ! -d "/var/log/haproxy" ]]; then
        log "ERROR" "Log directory not accessible"
        return 1
    fi
    
    # Test logrotate configuration
    if ! logrotate -d /etc/logrotate.d/haproxy >/dev/null 2>&1; then
        log "ERROR" "Logrotate configuration test failed"
        return 1
    fi
    
    log "DEBUG" "Log rotator health check passed"
    return 0
}

# Generic health check for unknown services
check_generic_health() {
    log "DEBUG" "Performing generic health check"
    
    # Basic system checks
    
    # Check disk space
    local disk_usage
    disk_usage=$(df /var/log/haproxy | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log "ERROR" "Disk usage too high: ${disk_usage}%"
        return 1
    fi
    
    # Check memory usage
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $mem_usage -gt 95 ]]; then
        log "ERROR" "Memory usage too high: ${mem_usage}%"
        return 1
    fi
    
    # Check if system is responsive
    if ! timeout 5 ls /tmp >/dev/null 2>&1; then
        log "ERROR" "System appears unresponsive"
        return 1
    fi
    
    log "DEBUG" "Generic health check passed"
    return 0
}

# Main health check function
main() {
    if [[ -z "$SERVICE_NAME" ]]; then
        echo "Usage: $0 <service_name>"
        echo "Available services: haproxy, certbot, syslog, monitor, maintenance, backend-discovery, config-watcher, log-rotator"
        exit 1
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "Starting health check"
    
    case "$SERVICE_NAME" in
        "haproxy")
            if check_haproxy_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "certbot")
            if check_certbot_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "syslog")
            if check_syslog_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "monitor")
            if check_monitor_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "maintenance")
            if check_maintenance_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "backend-discovery")
            if check_backend_discovery_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "config-watcher")
            if check_config_watcher_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        "log-rotator")
            if check_log_rotator_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
        *)
            log "WARN" "Unknown service type, performing generic health check"
            if check_generic_health; then
                echo "HEALTHY"
                exit 0
            else
                echo "UNHEALTHY"
                exit 1
            fi
            ;;
    esac
}

main "$@"