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

# ========== INSTALL OPENSSH SERVER ==========
Write-Host "[1/3] Installing OpenSSH Server" -ForegroundColor Cyan
Write-Host ""

# Install OpenSSH Server
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -ne "Installed") {
    Write-Host "Installing OpenSSH Server..." -ForegroundColor Yellow
    Write-Host "WARNING: This typically takes 5-10 minutes. Please be patient..." -ForegroundColor Red
    Write-Host ""
    
    # Show progress dots while installing
    $job = Start-Job -ScriptBlock {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }
    
    while ($job.State -eq 'Running') {
        Write-Host "." -NoNewline -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
    
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    Write-Host ""
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

# ========== ENABLE WSL FEATURES ==========
Write-Host ""
Write-Host "[2/3] Enabling WSL Features" -ForegroundColor Cyan
Write-Host ""

$changed1 = Enable-WindowsFeature "VirtualMachinePlatform"
$changed2 = Enable-WindowsFeature "Microsoft-Windows-Subsystem-Linux"

if ($changed1 -or $changed2 -or (Test-RebootRequired)) {
    $rebootNeeded = $true
}

# ========== CHECK IF REBOOT NEEDED BEFORE CONTINUING ==========
if ($rebootNeeded) {
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host "REBOOT REQUIRED" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host ""
    Write-Host "OpenSSH Server: [OK] Installed" -ForegroundColor Green
    Write-Host "WSL features have been enabled but require a restart before Ubuntu can be installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After reboot, run this script again to install Ubuntu." -ForegroundColor Cyan
    Write-Host ""
    
    $response = Read-Host "Would you like to restart now? (y/n)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host "Restarting computer..." -ForegroundColor Yellow
        Restart-Computer -Force
    }
    exit 0
}

# ========== INSTALL WSL UBUNTU ==========
Write-Host ""
Write-Host "[3/3] Installing WSL Ubuntu" -ForegroundColor Cyan
Write-Host ""

$UbuntuVersion = "Ubuntu-22.04"

# Check if Ubuntu is already installed
$wslList = wsl --list --quiet 2>$null
$ubuntuInstalled = $wslList | Where-Object { $_ -match $UbuntuVersion }

if (-not $ubuntuInstalled) {
    Write-Host "Installing $UbuntuVersion..." -ForegroundColor Yellow
    Write-Host "(This may take a few minutes to download...)" -ForegroundColor Gray
    Write-Host ""
    
    # Install Ubuntu (don't use --no-launch, let it launch automatically)
    wsl --install -d $UbuntuVersion
    
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host "UBUNTU SETUP REQUIRED" -ForegroundColor Yellow -BackgroundColor DarkBlue
    Write-Host "=" * 60 -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Ubuntu window should have opened for first-time setup." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "In the Ubuntu window, you will be prompted to:" -ForegroundColor White
    Write-Host "  1. Enter a new UNIX username (lowercase, no spaces)" -ForegroundColor Yellow
    Write-Host "  2. Enter a password (you won't see it as you type)" -ForegroundColor Yellow
    Write-Host "  3. Confirm the password" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After setup completes, type 'exit' in Ubuntu to return here." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press any key after you've completed Ubuntu setup..." -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    
    Write-Host ""
    Write-Host "$UbuntuVersion setup complete." -ForegroundColor Green
} else {
    Write-Host "$UbuntuVersion already installed." -ForegroundColor Gray
}

# ========== COMPLETION ==========
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""

# Verify installations
Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  OpenSSH Server: " -NoNewline
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService -and $sshService.Status -eq "Running") {
    Write-Host "[OK] Running" -ForegroundColor Green
} else {
    Write-Host "[X] Not running" -ForegroundColor Red
}

Write-Host "  WSL: " -NoNewline
$wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslInstalled) {
    Write-Host "[OK] Installed" -ForegroundColor Green
} else {
    Write-Host "[X] Not found" -ForegroundColor Red
}

Write-Host "  Ubuntu: " -NoNewline
$wslList = wsl --list --quiet 2>$null
$ubuntuCheck = $wslList | Where-Object { $_ -match "Ubuntu" }
if ($ubuntuCheck) {
    Write-Host "[OK] Installed" -ForegroundColor Green
} else {
    Write-Host "[X] Not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "You can launch Ubuntu anytime by typing: wsl" -ForegroundColor Cyan
Write-Host ""