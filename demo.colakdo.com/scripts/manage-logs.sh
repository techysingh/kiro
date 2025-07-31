#!/bin/bash

# HAProxy Log Management Script
# Provides utilities for managing HAProxy logs

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

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[LOG MANAGER]${NC} $1"
}

# Function to show log statistics
show_log_stats() {
    print_header "HAProxy Log Statistics"
    
    if [ ! -d "$LOGS_DIR" ]; then
        print_error "Logs directory not found: $LOGS_DIR"
        return 1
    fi
    
    echo
    echo "Log Directory: $LOGS_DIR"
    echo "Disk Usage:"
    du -sh "$LOGS_DIR"
    echo
    
    # Show individual log file sizes
    if ls "$LOGS_DIR"/*.log >/dev/null 2>&1; then
        echo "Current Log Files:"
        ls -lh "$LOGS_DIR"/*.log 2>/dev/null || true
        echo
    fi
    
    # Show archived logs
    if ls "$LOGS_DIR"/*.gz >/dev/null 2>&1; then
        echo "Archived Log Files:"
        ls -lh "$LOGS_DIR"/*.gz 2>/dev/null || true
        echo
    fi
    
    # Show log line counts
    if [ -f "$LOGS_DIR/haproxy.log" ]; then
        echo "Log Line Counts:"
        echo "  General Log: $(wc -l < "$LOGS_DIR/haproxy.log" 2>/dev/null || echo "0") lines"
    fi
    
    if [ -f "$LOGS_DIR/access.log" ]; then
        echo "  Access Log: $(wc -l < "$LOGS_DIR/access.log" 2>/dev/null || echo "0") lines"
    fi
    
    if [ -f "$LOGS_DIR/error.log" ]; then
        echo "  Error Log: $(wc -l < "$LOGS_DIR/error.log" 2>/dev/null || echo "0") lines"
    fi
}

# Function to tail logs
tail_logs() {
    local log_type="${1:-all}"
    
    print_header "Tailing HAProxy Logs (type: $log_type)"
    
    case "$log_type" in
        "access")
            if [ -f "$LOGS_DIR/access.log" ]; then
                tail -f "$LOGS_DIR/access.log"
            else
                print_error "Access log not found: $LOGS_DIR/access.log"
            fi
            ;;
        "error")
            if [ -f "$LOGS_DIR/error.log" ]; then
                tail -f "$LOGS_DIR/error.log"
            else
                print_error "Error log not found: $LOGS_DIR/error.log"
            fi
            ;;
        "general"|"haproxy")
            if [ -f "$LOGS_DIR/haproxy.log" ]; then
                tail -f "$LOGS_DIR/haproxy.log"
            else
                print_error "General log not found: $LOGS_DIR/haproxy.log"
            fi
            ;;
        "all")
            if ls "$LOGS_DIR"/*.log >/dev/null 2>&1; then
                tail -f "$LOGS_DIR"/*.log
            else
                print_error "No log files found in: $LOGS_DIR"
            fi
            ;;
        *)
            print_error "Invalid log type: $log_type"
            echo "Valid types: access, error, general, all"
            return 1
            ;;
    esac
}

# Function to rotate logs manually
rotate_logs() {
    print_header "Manually Rotating HAProxy Logs"
    
    if [ ! -f "$PROJECT_DIR/config/logrotate.conf" ]; then
        print_error "Logrotate configuration not found: $PROJECT_DIR/config/logrotate.conf"
        return 1
    fi
    
    print_status "Running logrotate..."
    docker exec haproxy-log-rotator logrotate -f /etc/logrotate.d/haproxy
    
    print_status "Log rotation completed"
    show_log_stats
}

# Function to clean old logs
clean_logs() {
    local days="${1:-30}"
    
    print_header "Cleaning Logs Older Than $days Days"
    
    if [ ! -d "$LOGS_DIR" ]; then
        print_error "Logs directory not found: $LOGS_DIR"
        return 1
    fi
    
    print_warning "This will delete log files older than $days days"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "$LOGS_DIR" -name "*.gz" -mtime +$days -delete
        print_status "Old log files cleaned"
        show_log_stats
    else
        print_status "Operation cancelled"
    fi
}

# Function to search logs
search_logs() {
    local pattern="$1"
    local log_type="${2:-all}"
    
    if [ -z "$pattern" ]; then
        print_error "Search pattern is required"
        echo "Usage: $0 search <pattern> [log_type]"
        return 1
    fi
    
    print_header "Searching for '$pattern' in $log_type logs"
    
    case "$log_type" in
        "access")
            grep -n "$pattern" "$LOGS_DIR/access.log" 2>/dev/null || print_warning "No matches found"
            ;;
        "error")
            grep -n "$pattern" "$LOGS_DIR/error.log" 2>/dev/null || print_warning "No matches found"
            ;;
        "general"|"haproxy")
            grep -n "$pattern" "$LOGS_DIR/haproxy.log" 2>/dev/null || print_warning "No matches found"
            ;;
        "all")
            grep -n "$pattern" "$LOGS_DIR"/*.log 2>/dev/null || print_warning "No matches found"
            ;;
        *)
            print_error "Invalid log type: $log_type"
            echo "Valid types: access, error, general, all"
            return 1
            ;;
    esac
}

# Function to show help
show_help() {
    echo "HAProxy Log Management Script"
    echo
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  stats                    Show log statistics and disk usage"
    echo "  tail [type]             Tail logs (types: access, error, general, all)"
    echo "  rotate                  Manually rotate logs"
    echo "  clean [days]            Clean logs older than specified days (default: 30)"
    echo "  search <pattern> [type] Search for pattern in logs"
    echo "  help                    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 stats"
    echo "  $0 tail access"
    echo "  $0 search 'ERROR' error"
    echo "  $0 clean 7"
}

# Main script logic
case "${1:-help}" in
    "stats")
        show_log_stats
        ;;
    "tail")
        tail_logs "$2"
        ;;
    "rotate")
        rotate_logs
        ;;
    "clean")
        clean_logs "$2"
        ;;
    "search")
        search_logs "$2" "$3"
        ;;
    "help"|*)
        show_help
        ;;
esac