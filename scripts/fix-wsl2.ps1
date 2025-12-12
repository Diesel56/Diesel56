#
# WSL2 Fix Script for Windows - Run as Administrator
# Resolves common WSL2 freezing, hanging, and command issues
#

param(
    [switch]$DiagnoseOnly,
    [switch]$FixAll,
    [switch]$RestartWSL,
    [switch]$FixNetworking,
    [switch]$FixLxssManager,
    [switch]$CreateWslConfig,
    [switch]$Help
)

# Check if running as Administrator
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[+] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[-] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Show-Banner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "    WSL2 Fix Script for Windows" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Help {
    Write-Host "Usage: .\fix-wsl2.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -DiagnoseOnly     Run diagnostics without making changes"
    Write-Host "  -FixAll           Apply all available fixes"
    Write-Host "  -RestartWSL       Restart WSL completely"
    Write-Host "  -FixNetworking    Fix WSL2 networking issues"
    Write-Host "  -FixLxssManager   Restart the LxssManager service"
    Write-Host "  -CreateWslConfig  Create optimized .wslconfig file"
    Write-Host "  -Help             Show this help message"
    Write-Host ""
}

# Get WSL status
function Get-WSLStatus {
    Write-Info "Checking WSL status..."

    try {
        $wslList = wsl --list --verbose 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "WSL is responding"
            Write-Host $wslList
        } else {
            Write-Error-Custom "WSL is not responding or not installed"
            return $false
        }
    } catch {
        Write-Error-Custom "Failed to query WSL: $_"
        return $false
    }

    return $true
}

# Check vmmem process
function Get-VmmemStatus {
    Write-Info "Checking vmmem process..."

    $vmmem = Get-Process -Name "vmmem" -ErrorAction SilentlyContinue
    if ($vmmem) {
        $memMB = [math]::Round($vmmem.WorkingSet64 / 1MB, 2)
        Write-Status "vmmem is running (Memory: ${memMB}MB)"

        if ($memMB -gt 4000) {
            Write-Warning-Custom "vmmem is using a lot of memory (${memMB}MB)"
            Write-Warning-Custom "Consider adding memory limits to .wslconfig"
        }
    } else {
        Write-Warning-Custom "vmmem is not running - WSL VM may not be active"
    }
}

# Check LxssManager service
function Get-LxssManagerStatus {
    Write-Info "Checking LxssManager service..."

    try {
        $service = Get-Service -Name "LxssManager" -ErrorAction Stop
        if ($service.Status -eq "Running") {
            Write-Status "LxssManager is running"
        } else {
            Write-Warning-Custom "LxssManager status: $($service.Status)"
        }
    } catch {
        Write-Error-Custom "LxssManager service not found: $_"
    }
}

# Fix LxssManager hanging
function Repair-LxssManager {
    Write-Info "Restarting LxssManager service..."

    if (-not (Test-Administrator)) {
        Write-Error-Custom "Administrator privileges required for this fix"
        return $false
    }

    try {
        # Get LxssManager PID
        $svcInfo = sc.exe queryex LxssManager
        Write-Host $svcInfo

        # Stop the service
        Write-Info "Stopping LxssManager..."
        sc.exe stop LxssManager | Out-Null
        Start-Sleep -Seconds 3

        # If service is stuck, find and kill the process
        $lxssProcess = tasklist /svc /fi "imagename eq svchost.exe" | Select-String "LxssManager"
        if ($lxssProcess) {
            $match = $lxssProcess -match "svchost.exe\s+(\d+)"
            if ($match) {
                $pid = $Matches[1]
                Write-Warning-Custom "Force killing LxssManager process (PID: $pid)..."
                taskkill /F /PID $pid 2>&1 | Out-Null
            }
        }

        Start-Sleep -Seconds 2

        # Start the service
        Write-Info "Starting LxssManager..."
        sc.exe start LxssManager | Out-Null
        Start-Sleep -Seconds 3

        $service = Get-Service -Name "LxssManager"
        if ($service.Status -eq "Running") {
            Write-Status "LxssManager successfully restarted"
            return $true
        } else {
            Write-Error-Custom "LxssManager failed to restart"
            return $false
        }
    } catch {
        Write-Error-Custom "Failed to restart LxssManager: $_"
        return $false
    }
}

# Restart WSL completely
function Restart-WSL {
    Write-Info "Shutting down WSL..."

    try {
        wsl --shutdown
        Start-Sleep -Seconds 5
        Write-Status "WSL shutdown complete"

        Write-Info "WSL will restart automatically on next use"
        Write-Info "You can start it with: wsl"
    } catch {
        Write-Error-Custom "Failed to shutdown WSL: $_"
    }
}

# Create/update .wslconfig
function New-WslConfig {
    Write-Info "Creating optimized .wslconfig..."

    $wslConfigPath = "$env:USERPROFILE\.wslconfig"

    # Get system memory
    $totalMemGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)
    $recommendedMem = [math]::Max([math]::Floor($totalMemGB / 2), 4)

    $config = @"
# WSL2 Configuration - Optimized for stability
# Created by WSL2 Fix Script on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

[wsl2]
# Limit memory to prevent system-wide issues
memory=${recommendedMem}GB

# Limit CPU cores
processors=4

# Swap space
swap=8GB

# Enable localhost forwarding
localhostForwarding=true

# Use mirrored networking to fix connectivity issues
# This is the most important setting for Claude Code CLI issues
networkingMode=mirrored

# Nested virtualization (if needed)
nestedVirtualization=true

[experimental]
# Automatically release memory back to Windows
autoMemoryReclaim=gradual

# Use sparse VHD to save disk space
sparseVhd=true

# Better networking for some scenarios
dnsTunneling=true
firewall=true
autoProxy=true
"@

    # Backup existing config
    if (Test-Path $wslConfigPath) {
        $backupPath = "$wslConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $wslConfigPath $backupPath
        Write-Warning-Custom "Backed up existing config to: $backupPath"
    }

    # Write new config
    $config | Out-File -FilePath $wslConfigPath -Encoding utf8
    Write-Status "Created .wslconfig at: $wslConfigPath"
    Write-Host ""
    Write-Host $config
    Write-Host ""
    Write-Warning-Custom "Restart WSL for changes to take effect: wsl --shutdown"
}

# Fix Windows Firewall for WSL2
function Repair-WSLFirewall {
    Write-Info "Configuring Windows Firewall for WSL2..."

    if (-not (Test-Administrator)) {
        Write-Error-Custom "Administrator privileges required"
        return
    }

    try {
        # Remove existing rules
        Remove-NetFirewallRule -DisplayName "WSL2 Inbound" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "WSL2 Outbound" -ErrorAction SilentlyContinue

        # Get WSL2 IP range
        $wslIP = wsl hostname -I 2>&1
        if ($wslIP -match "\d+\.\d+\.\d+\.\d+") {
            $ip = $Matches[0]
            $subnet = $ip -replace "\.\d+$", ".0/24"

            # Create firewall rules
            New-NetFirewallRule -DisplayName "WSL2 Inbound" `
                -Direction Inbound `
                -LocalAddress $subnet `
                -Action Allow `
                -Profile Private,Domain | Out-Null

            New-NetFirewallRule -DisplayName "WSL2 Outbound" `
                -Direction Outbound `
                -RemoteAddress $subnet `
                -Action Allow `
                -Profile Private,Domain | Out-Null

            Write-Status "Firewall rules created for subnet: $subnet"
        } else {
            Write-Warning-Custom "Could not determine WSL2 IP address"
        }
    } catch {
        Write-Error-Custom "Failed to configure firewall: $_"
    }
}

# Check for common issues
function Invoke-Diagnostics {
    Write-Info "Running diagnostics..."
    Write-Host ""

    Get-WSLStatus
    Write-Host ""

    Get-VmmemStatus
    Write-Host ""

    Get-LxssManagerStatus
    Write-Host ""

    # Check .wslconfig
    Write-Info "Checking .wslconfig..."
    $wslConfigPath = "$env:USERPROFILE\.wslconfig"
    if (Test-Path $wslConfigPath) {
        Write-Status ".wslconfig exists"
        $content = Get-Content $wslConfigPath -Raw
        if ($content -match "networkingMode\s*=\s*mirrored") {
            Write-Status "Mirrored networking is configured"
        } else {
            Write-Warning-Custom "Mirrored networking not configured - this often fixes CLI freezing"
        }
    } else {
        Write-Warning-Custom ".wslconfig not found - consider creating one"
    }
    Write-Host ""

    # Check for multiple WSL processes
    Write-Info "Checking for WSL processes..."
    $wslProcesses = Get-Process -Name "wsl*" -ErrorAction SilentlyContinue
    if ($wslProcesses) {
        Write-Status "Found $($wslProcesses.Count) WSL process(es)"
    }
}

# Main function
function Main {
    Show-Banner

    if ($Help) {
        Show-Help
        return
    }

    if (-not (Test-Administrator)) {
        Write-Warning-Custom "Some fixes require Administrator privileges"
        Write-Warning-Custom "Consider running PowerShell as Administrator"
        Write-Host ""
    }

    if ($DiagnoseOnly -or (-not $FixAll -and -not $RestartWSL -and -not $FixNetworking -and -not $FixLxssManager -and -not $CreateWslConfig)) {
        Invoke-Diagnostics
        Write-Host ""
        Write-Host "Available fixes:" -ForegroundColor Cyan
        Write-Host "  .\fix-wsl2.ps1 -RestartWSL        Restart WSL completely"
        Write-Host "  .\fix-wsl2.ps1 -FixLxssManager    Restart LxssManager service"
        Write-Host "  .\fix-wsl2.ps1 -CreateWslConfig   Create optimized .wslconfig"
        Write-Host "  .\fix-wsl2.ps1 -FixNetworking     Configure firewall for WSL2"
        Write-Host "  .\fix-wsl2.ps1 -FixAll            Apply all fixes"
        return
    }

    if ($FixAll) {
        New-WslConfig
        Write-Host ""
        Repair-WSLFirewall
        Write-Host ""
        Restart-WSL
        return
    }

    if ($RestartWSL) {
        Restart-WSL
    }

    if ($FixLxssManager) {
        Repair-LxssManager
    }

    if ($CreateWslConfig) {
        New-WslConfig
    }

    if ($FixNetworking) {
        Repair-WSLFirewall
    }
}

# Run main
Main
