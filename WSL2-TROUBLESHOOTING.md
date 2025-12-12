# WSL2 & Claude Code CLI Troubleshooting Guide

A comprehensive guide to fix WSL2 command errors and Claude Code CLI freezing issues.

## Table of Contents

- [Quick Fixes](#quick-fixes)
- [WSL2 Common Issues](#wsl2-common-issues)
- [Claude Code CLI Freezing](#claude-code-cli-freezing)
- [The .wslconfig File](#the-wslconfig-file)
- [Scripts](#scripts)
- [Advanced Troubleshooting](#advanced-troubleshooting)

---

## Quick Fixes

### WSL2 Terminal Freezing - Immediate Fix

If your terminal is frozen RIGHT NOW:

1. **Press `Ctrl+C`** to send SIGINT
2. **Then press `Ctrl+-` or `Ctrl++`** (zoom in/out) - this often unfreezes the terminal
3. If still frozen, open a new terminal and run:
   ```powershell
   wsl --shutdown
   ```

### Claude Code CLI Frozen - Immediate Fix

```bash
# Kill all Claude processes
pkill -9 -f "claude"

# Or from PowerShell
wsl --shutdown
```

---

## WSL2 Common Issues

### Issue 1: WSL Commands Hang for Minutes

**Symptoms:**
- `wsl` command hangs indefinitely
- Terminal doesn't respond after sleep/resume
- Commands take 10+ minutes to execute

**Cause:** LxssManager service gets stuck, especially after system sleep/resume.

**Fix:**

From PowerShell (as Administrator):
```powershell
# Method 1: Restart LxssManager service
sc.exe stop LxssManager
sc.exe start LxssManager

# Method 2: Force kill if stuck
tasklist /svc /fi "imagename eq svchost.exe" | findstr LxssManager
# Note the PID, then:
taskkill /F /PID <PID>
sc.exe start LxssManager

# Method 3: Full WSL restart
wsl --shutdown
```

### Issue 2: WSL2 Using Too Much Memory

**Symptoms:**
- System becomes slow
- `vmmem` process consuming GBs of RAM
- Out of memory errors

**Fix:** Create/update `.wslconfig`:

```ini
# %USERPROFILE%\.wslconfig (e.g., C:\Users\YourName\.wslconfig)

[wsl2]
memory=8GB
swap=4GB
processors=4

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Then restart WSL:
```powershell
wsl --shutdown
```

### Issue 3: Network Connectivity Issues

**Symptoms:**
- `ping` fails inside WSL
- DNS resolution doesn't work
- API calls timeout

**Fix 1: Enable Mirrored Networking** (Recommended)

```ini
# %USERPROFILE%\.wslconfig

[wsl2]
networkingMode=mirrored
```

**Fix 2: Manual DNS Configuration**

```bash
# Inside WSL
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
sudo chattr +i /etc/resolv.conf  # Prevent WSL from overwriting
```

**Fix 3: Configure Windows Firewall**

```powershell
# PowerShell as Administrator
New-NetFirewallRule -DisplayName "WSL2" -Direction Inbound -InterfaceAlias "vEthernet (WSL)" -Action Allow
```

### Issue 4: Slow File Operations

**Symptoms:**
- Operations on `/mnt/c/...` are very slow
- Git operations timeout
- Large file copies hang

**Cause:** Windows filesystem access through WSL2 is slow by design.

**Fix:** Work in Linux filesystem:
```bash
# Instead of:
cd /mnt/c/Users/YourName/projects

# Use:
cd ~/projects

# Clone repos to Linux filesystem
git clone https://github.com/user/repo ~/projects/repo
```

---

## Claude Code CLI Freezing

### Issue 1: CLI Hangs on Startup

**Symptoms:**
- Claude Code freezes at startup
- "Musing..." or "Thinking..." appears forever
- No response after launching

**Cause:** Network issues or WSL2 NAT networking problems.

**Fix:**

1. **Enable Mirrored Networking** (Most effective):
   ```ini
   # %USERPROFILE%\.wslconfig
   [wsl2]
   networkingMode=mirrored
   ```

2. **Restart WSL:**
   ```powershell
   wsl --shutdown
   ```

3. **Kill orphaned processes:**
   ```bash
   pkill -9 -f "claude"
   pkill -9 -f "@anthropic"
   ```

### Issue 2: CLI Freezes During Bash Commands

**Symptoms:**
- Works fine until running shell commands
- Hangs at "Running command..." indefinitely
- Basic commands like `ls`, `pwd` freeze

**Cause:** Path issues or Windows/Linux interop problems.

**Fix:**

1. **Work in Linux filesystem:**
   ```bash
   cd ~
   # Don't work in /mnt/c/...
   ```

2. **Disable Windows interop temporarily:**
   ```bash
   # Add to ~/.bashrc
   export WSL_INTEROP=""
   ```

3. **Clear Claude cache:**
   ```bash
   rm -rf ~/.claude
   rm -rf ~/.cache/claude
   ```

### Issue 3: Memory Issues Causing Freezes

**Symptoms:**
- Freezes after a few prompts
- Task Manager shows high vmmem usage
- WSL becomes unresponsive

**Fix:**

1. **Limit WSL memory:**
   ```ini
   # %USERPROFILE%\.wslconfig
   [wsl2]
   memory=8GB

   [experimental]
   autoMemoryReclaim=gradual
   ```

2. **Set Node.js memory limit:**
   ```bash
   # Add to ~/.bashrc
   export NODE_OPTIONS="--max-old-space-size=4096"
   ```

3. **Clear caches regularly:**
   ```bash
   npm cache clean --force
   sync && echo 1 | sudo tee /proc/sys/vm/drop_caches
   ```

### Issue 4: Version-Specific Bugs

**Symptoms:**
- CLI worked before, broke after update
- Specific version introduced issues

**Fix - Rollback:**
```bash
# Uninstall current version
npm uninstall -g @anthropic-ai/claude-code

# Install known stable version
npm install -g @anthropic-ai/claude-code@1.0.57
```

---

## The .wslconfig File

### Location
```
C:\Users\<YourUsername>\.wslconfig
```

### Recommended Configuration

```ini
# WSL2 Configuration for optimal Claude Code performance

[wsl2]
# Memory limit (adjust based on your system)
memory=8GB

# CPU cores
processors=4

# Swap space
swap=8GB

# Enable localhost forwarding
localhostForwarding=true

# CRITICAL: Use mirrored networking
# This fixes most Claude Code connectivity issues
networkingMode=mirrored

[experimental]
# Automatically release unused memory
autoMemoryReclaim=gradual

# Use sparse VHD (saves disk space)
sparseVhd=true

# Better networking
dnsTunneling=true
firewall=true
autoProxy=true
```

### After Changing .wslconfig

Always restart WSL:
```powershell
wsl --shutdown
```

---

## Scripts

This repository includes fix scripts:

### Linux/WSL2 Side

```bash
# WSL2 diagnostic and fix script
./scripts/fix-wsl2.sh

# Claude Code CLI specific fixes
./scripts/fix-claude-cli.sh
```

### Windows Side (PowerShell as Admin)

```powershell
# Diagnose issues
.\scripts\fix-wsl2.ps1 -DiagnoseOnly

# Apply all fixes
.\scripts\fix-wsl2.ps1 -FixAll

# Create optimized .wslconfig
.\scripts\fix-wsl2.ps1 -CreateWslConfig

# Restart WSL
.\scripts\fix-wsl2.ps1 -RestartWSL
```

---

## Advanced Troubleshooting

### Enable WSL Debug Logging

```powershell
# Create WSL debug log
wsl --debug-shell
```

### Check WSL Kernel Version

```bash
uname -r
# Should show something like: 5.15.x.x-microsoft-standard-WSL2
```

### Reset WSL Completely

```powershell
# Nuclear option - resets everything
wsl --unregister Ubuntu  # or your distro name
# Then reinstall from Microsoft Store
```

### Check for Windows Updates

WSL2 issues are often fixed by Windows updates. Check:
- Settings > Windows Update

### Hyper-V Issues

Ensure Hyper-V features are enabled:
```powershell
# Check status
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V

# Enable if needed
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

---

## Resources

- [Microsoft WSL Issues](https://github.com/microsoft/WSL/issues)
- [Windows Terminal Issues](https://github.com/microsoft/terminal/issues)
- [Claude Code Issues](https://github.com/anthropics/claude-code/issues)
- [Claude Code Troubleshooting Docs](https://docs.claude.com/en/docs/claude-code/troubleshooting)

---

## Quick Reference

| Problem | Quick Fix |
|---------|-----------|
| Terminal frozen | Ctrl+C, then Ctrl+- |
| WSL hangs | `wsl --shutdown` |
| Claude freezes | `pkill -9 -f "claude"` |
| Network issues | Add `networkingMode=mirrored` to .wslconfig |
| Memory issues | Add `memory=8GB` to .wslconfig |
| Slow operations | Work in `~` not `/mnt/c/` |
