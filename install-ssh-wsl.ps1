<# 
  install-ssh-wsl.ps1
  Run as: PowerShell (Admin)
  Purpose: Install OpenSSH Server and WSL Ubuntu on Windows
#>

# Check for Administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

function Enable-WindowsFeature($FeatureName) {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName
    if ($feature.State -eq "Enabled") {
        Write-Host "$FeatureName already enabled." -ForegroundColor Gray
        return $false
    } else {
        Write-Host "Enabling $FeatureName..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart | Out-Null
        Write-Host "$FeatureName enabled." -ForegroundColor Green
        return $true
    }
}

function Test-RebootRequired {
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) { return $true }
    }
    return $false
}

Clear-Host
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Installing OpenSSH Server and WSL Ubuntu" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$rebootNeeded = $false

# ========== ENABLE WSL FEATURES ==========
Write-Host "[1/3] Enabling WSL Features" -ForegroundColor Cyan
Write-Host ""

$changed1 = Enable-WindowsFeature "VirtualMachinePlatform"
$changed2 = Enable-WindowsFeature "Microsoft-Windows-Subsystem-Linux"

if ($changed1 -or $changed2 -or (Test-RebootRequired)) {
    $rebootNeeded = $true
}

# ========== INSTALL WSL UBUNTU ==========
Write-Host ""
Write-Host "[2/3] Installing WSL Ubuntu" -ForegroundColor Cyan
Write-Host ""

$UbuntuVersion = "Ubuntu-22.04"

# Check if Ubuntu is already installed
$ubuntuInstalled = wsl --list 2>$null | Select-String $UbuntuVersion

if (-not $ubuntuInstalled) {
    Write-Host "Installing $UbuntuVersion..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "Ubuntu will open in a new window for initial setup." -ForegroundColor Yellow
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "  1. Create a username (lowercase, no spaces)" -ForegroundColor White
    Write-Host "  2. Create a password" -ForegroundColor White
    Write-Host "  3. Type 'exit' when complete" -ForegroundColor White
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    
    wsl --install -d $UbuntuVersion
    
    Write-Host ""
    Write-Host "Waiting for Ubuntu setup to complete..." -ForegroundColor Yellow
    Write-Host "Complete the setup in the Ubuntu window, then press any key here..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    
    Write-Host "$UbuntuVersion installed." -ForegroundColor Green
} else {
    Write-Host "$UbuntuVersion already installed." -ForegroundColor Gray
}

# ========== INSTALL OPENSSH SERVER ==========
Write-Host ""
Write-Host "[3/3] Installing OpenSSH Server" -ForegroundColor Cyan
Write-Host ""

# Install OpenSSH Server
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne "Installed") {
    Write-Host "Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    Write-Host "OpenSSH Server installed." -ForegroundColor Green
} else {
    Write-Host "OpenSSH Server already installed." -ForegroundColor Gray
}

# Configure and start SSH service
Write-Host "Configuring SSH service..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
Write-Host "SSH service configured and started." -ForegroundColor Green

# Configure firewall
$firewallRule = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    Write-Host "Configuring firewall rule for SSH..." -ForegroundColor Yellow
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    Write-Host "Firewall rule configured." -ForegroundColor Green
} else {
    Write-Host "Firewall rule already configured." -ForegroundColor Gray
}

# ========== COMPLETION ==========
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""

# Verify installations
Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  WSL: " -NoNewline
$wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslInstalled) {
    Write-Host "[OK] Installed" -ForegroundColor Green
} else {
    Write-Host "[X] Not found" -ForegroundColor Red
}

Write-Host "  SSH Service: " -NoNewline
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService -and $sshService.Status -eq "Running") {
    Write-Host "[OK] Running" -ForegroundColor Green
} else {
    Write-Host "[X] Not running" -ForegroundColor Red
}

Write-Host ""

if ($rebootNeeded) {
    Write-Host "REBOOT REQUIRED:" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host "Windows features have been enabled that require a restart." -ForegroundColor Yellow
    Write-Host "Please restart your computer to complete the installation." -ForegroundColor Yellow
    Write-Host ""
    
    $response = Read-Host "Would you like to restart now? (y/n)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host "Restarting computer..." -ForegroundColor Yellow
        Restart-Computer -Force
    }
} else {
    Write-Host "Note: You may need to restart your terminal for all changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
