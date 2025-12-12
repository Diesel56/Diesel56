#!/bin/bash
#
# WSL2 Fix Script - Resolves common WSL2 freezing and command issues
# Run this script inside WSL2 to diagnose and fix issues
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    WSL2 Diagnostic & Fix Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

# Check if running in WSL
check_wsl() {
    print_info "Checking if running in WSL..."
    if grep -qi microsoft /proc/version 2>/dev/null; then
        print_status "Confirmed running in WSL"
        WSL_VERSION=$(cat /proc/version)
        echo "  Version: $WSL_VERSION"
    else
        print_error "This script should be run inside WSL"
        exit 1
    fi
}

# Check WSL2 vs WSL1
check_wsl_version() {
    print_info "Checking WSL version..."
    if [ -d "/run/WSL" ]; then
        print_status "Running WSL2"
    else
        print_warning "May be running WSL1 - some fixes may not apply"
    fi
}

# Check memory usage
check_memory() {
    print_info "Checking memory usage..."
    free -h
    echo ""

    # Check if memory is critically low
    available=$(free -m | awk '/^Mem:/{print $7}')
    if [ "$available" -lt 500 ]; then
        print_error "Low memory detected: ${available}MB available"
        print_warning "Consider adding memory limits to .wslconfig"
    else
        print_status "Memory looks OK: ${available}MB available"
    fi
}

# Check for zombie processes
check_zombie_processes() {
    print_info "Checking for zombie processes..."
    zombies=$(ps aux | awk '$8 ~ /Z/ {print}' | wc -l)
    if [ "$zombies" -gt 0 ]; then
        print_warning "Found $zombies zombie process(es)"
        ps aux | awk '$8 ~ /Z/ {print "  PID: "$2" CMD: "$11}'
    else
        print_status "No zombie processes found"
    fi
}

# Check DNS resolution
check_dns() {
    print_info "Checking DNS resolution..."
    if timeout 5 nslookup google.com > /dev/null 2>&1; then
        print_status "DNS resolution working"
    else
        print_error "DNS resolution failed"
        print_warning "Try: echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
    fi
}

# Check network connectivity
check_network() {
    print_info "Checking network connectivity..."
    if timeout 5 ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        print_status "Network connectivity OK"
    else
        print_error "Network connectivity issues detected"
        print_warning "Consider setting networkingMode = mirrored in .wslconfig"
    fi
}

# Fix DNS if broken
fix_dns() {
    print_info "Attempting to fix DNS..."

    # Backup current resolv.conf
    if [ -f /etc/resolv.conf ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s)
    fi

    # Remove symlink if exists and create new file
    sudo rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
    echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
    echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf > /dev/null

    # Prevent WSL from overwriting
    sudo chattr +i /etc/resolv.conf 2>/dev/null || true

    print_status "DNS configuration updated"
}

# Kill hanging Claude Code processes
kill_claude_processes() {
    print_info "Checking for hanging Claude Code processes..."

    claude_procs=$(pgrep -f "claude" 2>/dev/null | wc -l)
    if [ "$claude_procs" -gt 0 ]; then
        print_warning "Found $claude_procs Claude-related process(es)"
        pgrep -af "claude" 2>/dev/null || true

        read -p "Kill these processes? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pkill -f "claude" 2>/dev/null || true
            print_status "Claude processes terminated"
        fi
    else
        print_status "No Claude processes found"
    fi
}

# Kill hanging node processes
kill_node_processes() {
    print_info "Checking for hanging Node.js processes..."

    node_procs=$(pgrep -f "node" 2>/dev/null | wc -l)
    if [ "$node_procs" -gt 5 ]; then
        print_warning "Found $node_procs Node.js processes (high count)"

        read -p "Kill orphaned node processes? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Kill node processes older than 1 hour
            pkill -9 -f "node" 2>/dev/null || true
            print_status "Node processes cleaned up"
        fi
    else
        print_status "Node process count looks normal: $node_procs"
    fi
}

# Clear WSL cache
clear_cache() {
    print_info "Clearing caches..."

    # Clear page cache
    sync
    echo 1 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || true

    # Clear npm cache
    if command -v npm &> /dev/null; then
        npm cache clean --force 2>/dev/null || true
        print_status "NPM cache cleared"
    fi

    # Clear tmp files older than 7 days
    sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true

    print_status "Caches cleared"
}

# Check file system issues
check_filesystem() {
    print_info "Checking filesystem..."

    # Check if working in Windows filesystem (slow)
    current_dir=$(pwd)
    if [[ "$current_dir" == /mnt/* ]]; then
        print_warning "Working in Windows filesystem (/mnt/*) - this is slower"
        print_warning "Consider working in Linux filesystem (~/) for better performance"
    else
        print_status "Working in Linux filesystem - good for performance"
    fi

    # Check disk space
    disk_usage=$(df -h . | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 90 ]; then
        print_error "Disk usage is high: ${disk_usage}%"
    else
        print_status "Disk usage OK: ${disk_usage}%"
    fi
}

# Generate .wslconfig recommendations
generate_wslconfig() {
    print_info "Generating recommended .wslconfig..."

    # Get system memory
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    recommended_mem=$((total_mem / 2))
    if [ "$recommended_mem" -lt 4 ]; then
        recommended_mem=4
    fi

    cat << EOF

Recommended .wslconfig for your system:
Create/edit this file at: C:\\Users\\<YourUsername>\\.wslconfig

[wsl2]
memory=${recommended_mem}GB
processors=4
swap=8GB
localhostForwarding=true
networkingMode=mirrored

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true

EOF
}

# Main diagnostic flow
main() {
    echo ""
    print_info "Starting diagnostics..."
    echo ""

    check_wsl
    echo ""
    check_wsl_version
    echo ""
    check_memory
    echo ""
    check_zombie_processes
    echo ""
    check_dns
    echo ""
    check_network
    echo ""
    check_filesystem
    echo ""

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Available Fixes${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "1. Fix DNS resolution"
    echo "2. Kill hanging Claude Code processes"
    echo "3. Kill hanging Node.js processes"
    echo "4. Clear caches"
    echo "5. Show .wslconfig recommendations"
    echo "6. Run all fixes"
    echo "7. Exit"
    echo ""

    read -p "Select an option (1-7): " choice

    case $choice in
        1) fix_dns ;;
        2) kill_claude_processes ;;
        3) kill_node_processes ;;
        4) clear_cache ;;
        5) generate_wslconfig ;;
        6)
            fix_dns
            kill_claude_processes
            kill_node_processes
            clear_cache
            generate_wslconfig
            ;;
        7) exit 0 ;;
        *) print_error "Invalid option" ;;
    esac

    echo ""
    print_status "Done! If issues persist, try running from Windows PowerShell:"
    echo "  wsl --shutdown"
    echo "  Then restart your terminal"
}

# Run main function
main "$@"
