<# 
  install-devmode.ps1
  Run as: PowerShell (Admin)
  Purpose: Enable Developer Mode and Long Paths on Windows
#>

# Check for Administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuring Windows Developer Settings..." -ForegroundColor Cyan
Write-Host ""

# Enable Developer Mode
Write-Host "Enabling Developer Mode..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
    -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord -Force
Write-Host "[OK] Developer Mode enabled" -ForegroundColor Green

# Enable long paths
Write-Host "Enabling Long Paths..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1 -Type DWord -Force
Write-Host "[OK] Long Paths enabled" -ForegroundColor Green

Write-Host ""
Write-Host "Configuration complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Some applications may require a restart to use these settings." -ForegroundColor Yellow
