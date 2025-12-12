#!/bin/bash
#
# Claude Code CLI Fix Script
# Resolves common freezing and hanging issues with Claude Code in WSL2
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Claude Code CLI Fix Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

print_status() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_info() { echo -e "${BLUE}[*]${NC} $1"; }

# Check if Claude Code is installed
check_installation() {
    print_info "Checking Claude Code installation..."

    if command -v claude &> /dev/null; then
        version=$(claude --version 2>/dev/null || echo "unknown")
        print_status "Claude Code is installed: $version"
        return 0
    else
        print_error "Claude Code is not installed"
        print_info "Install with: npm install -g @anthropic-ai/claude-code"
        return 1
    fi
}

# Check Node.js version
check_node() {
    print_info "Checking Node.js..."

    if command -v node &> /dev/null; then
        node_version=$(node --version)
        print_status "Node.js: $node_version"

        # Check if version is compatible (v18+)
        major_version=$(echo "$node_version" | sed 's/v//' | cut -d. -f1)
        if [ "$major_version" -lt 18 ]; then
            print_warning "Node.js v18+ recommended for Claude Code"
        fi
    else
        print_error "Node.js is not installed"
        return 1
    fi
}

# Kill all Claude-related processes
kill_claude_processes() {
    print_info "Killing Claude Code processes..."

    # Kill claude processes
    pkill -9 -f "claude" 2>/dev/null && print_status "Killed claude processes" || print_info "No claude processes found"

    # Kill related node processes (be careful here)
    # Only kill node processes that are clearly Claude-related
    pkill -9 -f "@anthropic-ai/claude" 2>/dev/null && print_status "Killed anthropic node processes" || print_info "No anthropic node processes found"

    sleep 2
}

# Clear Claude Code cache and config
clear_claude_cache() {
    print_info "Clearing Claude Code cache..."

    # Claude Code cache locations
    cache_dirs=(
        "$HOME/.claude"
        "$HOME/.cache/claude"
        "$HOME/.config/claude-code"
        "$HOME/.npm/_cacache"
    )

    for dir in "${cache_dirs[@]}"; do
        if [ -d "$dir" ]; then
            print_warning "Found cache directory: $dir"
            read -p "  Clear this directory? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$dir"
                print_status "Cleared: $dir"
            fi
        fi
    done
}

# Reset Claude Code configuration
reset_config() {
    print_info "Checking Claude Code configuration..."

    config_file="$HOME/.claude/config.json"
    if [ -f "$config_file" ]; then
        print_warning "Found config file: $config_file"
        cat "$config_file" 2>/dev/null || true
        echo ""

        read -p "Reset configuration? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mv "$config_file" "$config_file.backup.$(date +%s)"
            print_status "Configuration backed up and reset"
        fi
    else
        print_info "No config file found"
    fi
}

# Reinstall Claude Code
reinstall_claude() {
    print_info "Reinstalling Claude Code..."

    # Get current version
    current_version=$(npm list -g @anthropic-ai/claude-code 2>/dev/null | grep claude-code || echo "not installed")
    print_info "Current: $current_version"

    read -p "Proceed with reinstall? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Uninstall
        npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true

        # Clear npm cache
        npm cache clean --force

        # Reinstall latest
        npm install -g @anthropic-ai/claude-code

        new_version=$(claude --version 2>/dev/null || echo "unknown")
        print_status "Installed: $new_version"
    fi
}

# Install specific version (rollback)
install_specific_version() {
    print_info "Available stable versions for rollback:"
    echo "  1. Latest (default)"
    echo "  2. v1.0.57 (known stable for WSL2)"
    echo "  3. v1.0.50"
    echo "  4. Custom version"
    echo ""

    read -p "Select version (1-4): " choice

    case $choice in
        1)
            npm install -g @anthropic-ai/claude-code@latest
            ;;
        2)
            npm install -g @anthropic-ai/claude-code@1.0.57
            ;;
        3)
            npm install -g @anthropic-ai/claude-code@1.0.50
            ;;
        4)
            read -p "Enter version number: " custom_version
            npm install -g @anthropic-ai/claude-code@$custom_version
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Fix network issues for Claude Code
fix_network() {
    print_info "Checking network configuration for Claude Code..."

    # Test connection to Anthropic API
    print_info "Testing connection to Anthropic API..."
    if timeout 10 curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com > /dev/null 2>&1; then
        print_status "Connection to Anthropic API successful"
    else
        print_error "Cannot connect to Anthropic API"
        print_warning "Check your network configuration and .wslconfig"
    fi

    # Check proxy settings
    print_info "Checking proxy settings..."
    if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ] || [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
        print_warning "Proxy detected:"
        echo "  HTTP_PROXY: ${HTTP_PROXY:-$http_proxy}"
        echo "  HTTPS_PROXY: ${HTTPS_PROXY:-$https_proxy}"
        print_warning "Proxies can cause issues with Claude Code"
    else
        print_status "No proxy configured"
    fi
}

# Set environment variables for better performance
set_env_vars() {
    print_info "Setting recommended environment variables..."

    env_file="$HOME/.bashrc"

    # Check if already set
    if grep -q "CLAUDE_CODE" "$env_file" 2>/dev/null; then
        print_warning "Claude Code environment variables already in $env_file"
        return
    fi

    read -p "Add recommended environment variables to $env_file? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat >> "$env_file" << 'EOF'

# Claude Code CLI optimizations
export NODE_OPTIONS="--max-old-space-size=4096"
export CLAUDE_CODE_SKIP_ANALYTICS=1

# Disable Node.js experimental warnings
export NODE_NO_WARNINGS=1

# Better terminal handling
export TERM=xterm-256color
EOF

        print_status "Environment variables added. Run: source ~/.bashrc"
    fi
}

# Diagnose common issues
diagnose() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Diagnostics${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_installation
    echo ""
    check_node
    echo ""

    # Check for multiple Claude processes
    print_info "Checking for running Claude processes..."
    claude_count=$(pgrep -c -f "claude" 2>/dev/null || echo "0")
    if [ "$claude_count" -gt 0 ]; then
        print_warning "Found $claude_count Claude process(es) running"
        pgrep -af "claude" 2>/dev/null || true
    else
        print_status "No Claude processes running"
    fi
    echo ""

    # Check memory
    print_info "Checking memory usage..."
    free -h
    echo ""

    # Check if in Windows filesystem
    print_info "Checking working directory..."
    if [[ "$(pwd)" == /mnt/* ]]; then
        print_warning "Working in Windows filesystem - may cause slowness"
    else
        print_status "Working in Linux filesystem"
    fi
    echo ""

    fix_network
}

# Main menu
main_menu() {
    echo ""
    echo -e "${BLUE}Available Actions:${NC}"
    echo "1. Run diagnostics"
    echo "2. Kill all Claude processes"
    echo "3. Clear Claude cache"
    echo "4. Reset configuration"
    echo "5. Reinstall Claude Code (latest)"
    echo "6. Install specific version (rollback)"
    echo "7. Set environment variables"
    echo "8. Fix all issues"
    echo "9. Exit"
    echo ""

    read -p "Select an option (1-9): " choice

    case $choice in
        1) diagnose ;;
        2) kill_claude_processes ;;
        3) clear_claude_cache ;;
        4) reset_config ;;
        5) reinstall_claude ;;
        6) install_specific_version ;;
        7) set_env_vars ;;
        8)
            kill_claude_processes
            clear_claude_cache
            set_env_vars
            reinstall_claude
            print_status "All fixes applied!"
            ;;
        9) exit 0 ;;
        *)
            print_error "Invalid option"
            main_menu
            ;;
    esac

    echo ""
    read -p "Return to menu? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        main_menu
    fi
}

# Command line arguments
case "${1:-}" in
    --diagnose|-d)
        diagnose
        ;;
    --kill|-k)
        kill_claude_processes
        ;;
    --reinstall|-r)
        reinstall_claude
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  --diagnose, -d    Run diagnostics only"
        echo "  --kill, -k        Kill Claude processes"
        echo "  --reinstall, -r   Reinstall Claude Code"
        echo "  --help, -h        Show this help"
        echo ""
        echo "Run without arguments for interactive menu."
        ;;
    *)
        diagnose
        main_menu
        ;;
esac
