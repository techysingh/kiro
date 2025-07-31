#!/bin/bash

# HAProxy Wildcard SSL Deployment Script
# This script orchestrates the deployment of the complete HAProxy stack

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
LOG_FILE="$PROJECT_DIR/logs/deployment.log"

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
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
    
    case "$level" in
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed or not in PATH"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error_exit "Docker Compose is not installed"
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running"
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Validate environment configuration
validate_environment() {
    log "INFO" "Validating environment configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Environment file not found: $ENV_FILE. Copy .env.example to .env and configure it."
    fi
    
    # Source environment file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Check required variables
    local required_vars=("LETSENCRYPT_EMAIL" "DOMAIN" "DNS_PLUGIN")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable $var is not set in $ENV_FILE"
        fi
    done
    
    # Check DNS credentials
    local dns_creds_file="$PROJECT_DIR/dns-credentials/${DNS_PLUGIN#dns-}.ini"
    if [[ ! -f "$dns_creds_file" ]]; then
        error_exit "DNS credentials file not found: $dns_creds_file"
    fi
    
    # Check file permissions
    local perms=$(stat -c "%a" "$dns_creds_file" 2>/dev/null || stat -f "%A" "$dns_creds_file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        log "WARN" "DNS credentials file has incorrect permissions. Setting to 600..."
        chmod 600 "$dns_creds_file"
    fi
    
    log "INFO" "Environment validation passed"
}

# Create required directories
create_directories() {
    log "INFO" "Creating required directories..."
    
    local dirs=(
        "$PROJECT_DIR/certs"
        "$PROJECT_DIR/certs/live"
        "$PROJECT_DIR/certs/dns-credentials"
        "$PROJECT_DIR/logs"
        "$PROJECT_DIR/config"
        "$PROJECT_DIR/errors"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "DEBUG" "Created directory: $dir"
        fi
    done
    
    log "INFO" "Directory creation completed"
}

# Setup Docker network
setup_network() {
    log "INFO" "Setting up Docker network..."
    
    if ! docker network inspect proxy-network &> /dev/null; then
        docker network create proxy-network --driver bridge --attachable
        log "INFO" "Created proxy-network"
    else
        log "INFO" "proxy-network already exists"
    fi
}

# Pull Docker images
pull_images() {
    log "INFO" "Pulling Docker images..."
    
    # Source environment to get image names
    set -a
    source "$ENV_FILE"
    set +a
    
    local images=(
        "haproxy:2.8-alpine"
        "${CERTBOT_IMAGE:-certbot/dns-cloudflare:latest}"
        "alpine:latest"
        "python:3.11-alpine"
    )
    
    for image in "${images[@]}"; do
        log "DEBUG" "Pulling image: $image"
        docker pull "$image" || log "WARN" "Failed to pull image: $image"
    done
    
    log "INFO" "Image pulling completed"
}

# Start services
start_services() {
    log "INFO" "Starting HAProxy stack..."
    
    cd "$PROJECT_DIR"
    
    # Start services with dependency order
    docker-compose up -d --remove-orphans
    
    log "INFO" "Services started successfully"
}

# Wait for services to be healthy
wait_for_health() {
    log "INFO" "Waiting for services to become healthy..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=10
    
    while [[ $wait_time -lt $max_wait ]]; do
        local healthy_count=0
        local total_services=0
        
        # Get service health status
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z0-9_-]+[[:space:]]+[a-zA-Z0-9_-]+[[:space:]]+\"docker-entrypoint.sh\" ]]; then
                ((total_services++))
                if [[ "$line" =~ \(healthy\) ]]; then
                    ((healthy_count++))
                fi
            fi
        done < <(docker-compose ps 2>/dev/null || true)
        
        if [[ $healthy_count -eq $total_services ]] && [[ $total_services -gt 0 ]]; then
            log "INFO" "All services are healthy ($healthy_count/$total_services)"
            return 0
        fi
        
        log "DEBUG" "Services health check: $healthy_count/$total_services healthy"
        sleep $check_interval
        ((wait_time += check_interval))
    done
    
    log "WARN" "Timeout waiting for all services to become healthy"
    return 1
}

# Verify deployment
verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    # Check HAProxy stats endpoint
    if curl -s -f "http://localhost:8404/health" > /dev/null; then
        log "INFO" "HAProxy health endpoint is responding"
    else
        log "WARN" "HAProxy health endpoint is not responding"
    fi
    
    # Check certificate generation
    local cert_path="$PROJECT_DIR/certs/live/${DOMAIN:-colakdo.com}/fullchain.pem"
    if [[ -f "$cert_path" ]]; then
        log "INFO" "SSL certificate found at $cert_path"
        
        # Check certificate validity
        local expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            log "INFO" "Certificate expires: $expiry"
        fi
    else
        log "WARN" "SSL certificate not found. It may still be generating..."
    fi
    
    # Check logs
    if [[ -f "$PROJECT_DIR/logs/haproxy.log" ]]; then
        log "INFO" "HAProxy logs are being written"
    else
        log "WARN" "HAProxy logs not found"
    fi
    
    log "INFO" "Deployment verification completed"
}

# Show deployment status
show_status() {
    log "INFO" "Deployment Status Summary"
    echo "=================================="
    
    # Service status
    echo -e "\n${BLUE}Service Status:${NC}"
    docker-compose ps
    
    # Network status
    echo -e "\n${BLUE}Network Status:${NC}"
    docker network inspect proxy-network --format "{{.Name}}: {{len .Containers}} containers connected" 2>/dev/null || echo "proxy-network: Not found"
    
    # Certificate status
    echo -e "\n${BLUE}Certificate Status:${NC}"
    if [[ -f "$PROJECT_DIR/certs/live/${DOMAIN:-colakdo.com}/fullchain.pem" ]]; then
        local cert_path="$PROJECT_DIR/certs/live/${DOMAIN:-colakdo.com}/fullchain.pem"
        local expiry=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "Certificate: Found"
        echo "Expires: ${expiry:-Unknown}"
    else
        echo "Certificate: Not found or still generating"
    fi
    
    # Access URLs
    echo -e "\n${BLUE}Access URLs:${NC}"
    echo "HAProxy Stats: http://localhost:8404/stats"
    echo "HAProxy Health: http://localhost:8404/health"
    echo "HTTPS Endpoint: https://${DOMAIN:-colakdo.com}"
    
    # Log locations
    echo -e "\n${BLUE}Log Files:${NC}"
    echo "Deployment: $LOG_FILE"
    echo "HAProxy: $PROJECT_DIR/logs/haproxy.log"
    echo "Access: $PROJECT_DIR/logs/access.log"
    echo "Errors: $PROJECT_DIR/logs/error.log"
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up deployment artifacts..."
    
    # Remove orphaned containers
    docker-compose down --remove-orphans
    
    # Clean up unused images (optional)
    if [[ "${CLEANUP_IMAGES:-false}" == "true" ]]; then
        docker image prune -f
    fi
    
    log "INFO" "Cleanup completed"
}

# Main deployment function
deploy() {
    log "INFO" "Starting HAProxy Wildcard SSL deployment..."
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run deployment steps
    check_prerequisites
    validate_environment
    create_directories
    setup_network
    pull_images
    start_services
    
    # Wait for services (optional, can be skipped with --no-wait)
    if [[ "${NO_WAIT:-false}" != "true" ]]; then
        wait_for_health
    fi
    
    verify_deployment
    show_status
    
    log "INFO" "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Configure your DNS to point *.${DOMAIN:-colakdo.com} to this server"
    echo "2. Add backend services to the proxy-network"
    echo "3. Update HAProxy configuration for your specific routing needs"
    echo "4. Monitor logs and certificate renewal"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

HAProxy Wildcard SSL Deployment Script

COMMANDS:
    deploy      Deploy the complete HAProxy stack
    status      Show current deployment status
    cleanup     Clean up deployment artifacts
    logs        Show deployment logs
    help        Show this help message

OPTIONS:
    --no-wait           Skip waiting for service health checks
    --cleanup-images    Remove unused Docker images during cleanup
    --verbose           Enable verbose logging
    --dry-run          Show what would be done without executing

EXAMPLES:
    $0 deploy                    # Deploy the stack
    $0 deploy --no-wait          # Deploy without waiting for health checks
    $0 status                    # Show current status
    $0 cleanup --cleanup-images  # Clean up with image removal
    $0 logs                      # Show deployment logs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-wait)
            NO_WAIT=true
            shift
            ;;
        --cleanup-images)
            CLEANUP_IMAGES=true
            shift
            ;;
        --verbose)
            set -x
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        deploy|status|cleanup|logs|help)
            COMMAND="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default command
COMMAND="${COMMAND:-deploy}"

# Execute command
case "$COMMAND" in
    deploy)
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log "INFO" "DRY RUN: Would execute deployment steps"
            exit 0
        fi
        deploy
        ;;
    status)
        show_status
        ;;
    cleanup)
        cleanup
        ;;
    logs)
        if [[ -f "$LOG_FILE" ]]; then
            tail -f "$LOG_FILE"
        else
            echo "Log file not found: $LOG_FILE"
            exit 1
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