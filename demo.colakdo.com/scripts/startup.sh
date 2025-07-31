#!/bin/bash

# HAProxy Wildcard SSL Startup Orchestration Script
# This script handles the startup sequence and service orchestration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
LOG_FILE="$PROJECT_DIR/logs/startup.log"

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
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    
    case "$level" in
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Service startup order and dependencies
declare -A SERVICE_DEPENDENCIES=(
    ["syslog"]=""
    ["certbot"]="syslog"
    ["maintenance-server"]="syslog"
    ["haproxy"]="syslog certbot maintenance-server"
    ["log-rotator"]="syslog"
    ["monitor"]="haproxy"
    ["backend-discovery"]="haproxy maintenance-server"
    ["config-watcher"]="haproxy backend-discovery"
)

# Check if service is running
is_service_running() {
    local service="$1"
    docker-compose ps -q "$service" 2>/dev/null | xargs -r docker inspect -f '{{.State.Status}}' 2>/dev/null | grep -q "running"
}

# Check if service is healthy
is_service_healthy() {
    local service="$1"
    local health_status=$(docker-compose ps -q "$service" 2>/dev/null | xargs -r docker inspect -f '{{.State.Health.Status}}' 2>/dev/null)
    [[ "$health_status" == "healthy" ]] || [[ -z "$health_status" && $(is_service_running "$service") ]]
}

# Wait for service to be healthy
wait_for_service() {
    local service="$1"
    local timeout="${2:-120}"
    local interval=5
    local elapsed=0
    
    log "INFO" "Waiting for service '$service' to become healthy..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if is_service_healthy "$service"; then
            log "INFO" "Service '$service' is healthy"
            return 0
        fi
        
        if ! is_service_running "$service"; then
            log "WARN" "Service '$service' is not running, attempting to start..."
            docker-compose up -d "$service" || true
        fi
        
        sleep $interval
        ((elapsed += interval))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "DEBUG" "Still waiting for '$service'... (${elapsed}s elapsed)"
        fi
    done
    
    log "ERROR" "Timeout waiting for service '$service' to become healthy"
    return 1
}

# Start service with dependencies
start_service() {
    local service="$1"
    local dependencies="${SERVICE_DEPENDENCIES[$service]:-}"
    
    # Start dependencies first
    if [[ -n "$dependencies" ]]; then
        for dep in $dependencies; do
            if ! is_service_healthy "$dep"; then
                log "INFO" "Starting dependency '$dep' for service '$service'"
                start_service "$dep"
            fi
        done
    fi
    
    # Start the service if not already running
    if ! is_service_running "$service"; then
        log "INFO" "Starting service '$service'"
        docker-compose up -d "$service"
    else
        log "DEBUG" "Service '$service' is already running"
    fi
    
    # Wait for service to be healthy
    wait_for_service "$service"
}

# Stop service gracefully
stop_service() {
    local service="$1"
    local timeout="${2:-30}"
    
    if is_service_running "$service"; then
        log "INFO" "Stopping service '$service'"
        docker-compose stop -t "$timeout" "$service"
    else
        log "DEBUG" "Service '$service' is not running"
    fi
}

# Restart service
restart_service() {
    local service="$1"
    
    log "INFO" "Restarting service '$service'"
    stop_service "$service"
    start_service "$service"
}

# Start all services in dependency order
start_all_services() {
    log "INFO" "Starting all services in dependency order..."
    
    # Create network if it doesn't exist
    if ! docker network inspect proxy-network &> /dev/null; then
        log "INFO" "Creating proxy-network"
        docker network create proxy-network --driver bridge --attachable
    fi
    
    # Start services in dependency order
    local services=(
        "syslog"
        "certbot"
        "maintenance-server"
        "haproxy"
        "log-rotator"
        "monitor"
        "backend-discovery"
        "config-watcher"
    )
    
    for service in "${services[@]}"; do
        start_service "$service"
    done
    
    log "INFO" "All services started successfully"
}

# Stop all services
stop_all_services() {
    log "INFO" "Stopping all services..."
    
    # Stop in reverse dependency order
    local services=(
        "config-watcher"
        "backend-discovery"
        "monitor"
        "log-rotator"
        "haproxy"
        "maintenance-server"
        "certbot"
        "syslog"
    )
    
    for service in "${services[@]}"; do
        stop_service "$service"
    done
    
    log "INFO" "All services stopped"
}

# Restart all services
restart_all_services() {
    log "INFO" "Restarting all services..."
    stop_all_services
    sleep 5
    start_all_services
}

# Check service health status
check_health() {
    log "INFO" "Checking service health status..."
    
    local all_healthy=true
    
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        if is_service_running "$service"; then
            if is_service_healthy "$service"; then
                log "INFO" "✓ $service: healthy"
            else
                log "WARN" "⚠ $service: unhealthy"
                all_healthy=false
            fi
        else
            log "ERROR" "✗ $service: not running"
            all_healthy=false
        fi
    done
    
    if $all_healthy; then
        log "INFO" "All services are healthy"
        return 0
    else
        log "WARN" "Some services are not healthy"
        return 1
    fi
}

# Show service status
show_status() {
    echo -e "\n${BLUE}Service Status:${NC}"
    echo "==============="
    
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        local status="stopped"
        local health="unknown"
        
        if is_service_running "$service"; then
            status="running"
            if is_service_healthy "$service"; then
                health="healthy"
            else
                health="unhealthy"
            fi
        fi
        
        printf "%-20s %-10s %-10s\n" "$service" "$status" "$health"
    done
    
    echo ""
    echo -e "${BLUE}Network Status:${NC}"
    echo "==============="
    if docker network inspect proxy-network &> /dev/null; then
        local container_count=$(docker network inspect proxy-network --format "{{len .Containers}}")
        echo "proxy-network: $container_count containers connected"
    else
        echo "proxy-network: not found"
    fi
}

# Monitor services continuously
monitor_services() {
    local interval="${1:-60}"
    
    log "INFO" "Starting continuous service monitoring (interval: ${interval}s)"
    
    while true; do
        if ! check_health; then
            log "WARN" "Health check failed, attempting to restart unhealthy services"
            
            for service in "${!SERVICE_DEPENDENCIES[@]}"; do
                if is_service_running "$service" && ! is_service_healthy "$service"; then
                    log "INFO" "Restarting unhealthy service: $service"
                    restart_service "$service"
                fi
            done
        fi
        
        sleep "$interval"
    done
}

# Handle graceful shutdown
graceful_shutdown() {
    log "INFO" "Received shutdown signal, stopping services gracefully..."
    stop_all_services
    exit 0
}

# Set up signal handlers
trap graceful_shutdown SIGTERM SIGINT

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND [SERVICE]

HAProxy Wildcard SSL Startup Orchestration Script

COMMANDS:
    start [SERVICE]     Start all services or specific service
    stop [SERVICE]      Stop all services or specific service
    restart [SERVICE]   Restart all services or specific service
    status              Show service status
    health              Check service health
    monitor [INTERVAL]  Monitor services continuously (default: 60s)
    logs [SERVICE]      Show logs for service
    help                Show this help message

OPTIONS:
    --timeout SECONDS   Set timeout for service operations (default: 120)
    --verbose           Enable verbose logging

EXAMPLES:
    $0 start                    # Start all services
    $0 start haproxy           # Start HAProxy service
    $0 restart                 # Restart all services
    $0 status                  # Show service status
    $0 health                  # Check service health
    $0 monitor 30              # Monitor services every 30 seconds
    $0 logs haproxy            # Show HAProxy logs

EOF
}

# Parse command line arguments
TIMEOUT=120
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        start|stop|restart|status|health|monitor|logs|help)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Get remaining arguments
SERVICE="${1:-}"
INTERVAL="${2:-60}"

# Set default command
COMMAND="${COMMAND:-start}"

# Change to project directory
cd "$PROJECT_DIR"

# Execute command
case "$COMMAND" in
    start)
        if [[ -n "$SERVICE" ]]; then
            start_service "$SERVICE"
        else
            start_all_services
        fi
        ;;
    stop)
        if [[ -n "$SERVICE" ]]; then
            stop_service "$SERVICE"
        else
            stop_all_services
        fi
        ;;
    restart)
        if [[ -n "$SERVICE" ]]; then
            restart_service "$SERVICE"
        else
            restart_all_services
        fi
        ;;
    status)
        show_status
        ;;
    health)
        check_health
        ;;
    monitor)
        monitor_services "$INTERVAL"
        ;;
    logs)
        if [[ -n "$SERVICE" ]]; then
            docker-compose logs -f "$SERVICE"
        else
            docker-compose logs -f
        fi
        ;;
    help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac