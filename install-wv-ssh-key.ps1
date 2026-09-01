<#
  install-wv-ssh-key.ps1
  Run as: PowerShell (Admin)
  Purpose: Authorize the WorldViz support workstation's SSH public key for
           administrator logins on this machine (key-based SSH, no password).
           The key below is a PUBLIC key - safe to distribute.
  Run remotely:  iwr -useb util.worldviz.com/install-wv-ssh-key.ps1 | iex
  Idempotent - re-running changes nothing if the key is already present.
#>

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    return
}

$pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/Wm6LgS28hCozK61A0vBdFNFM3mbNdlCN0STlbYiol wv-support"
$file = "C:\ProgramData\ssh\administrators_authorized_keys"

New-Item -ItemType Directory -Path "C:\ProgramData\ssh" -Force | Out-Null
$existing = ""
if (Test-Path $file) { $existing = Get-Content $file -Raw }
if ($existing -match [regex]::Escape(($pubkey -split " ")[1])) {
    Write-Host "WorldViz support key already authorized." -ForegroundColor Gray
} else {
    Add-Content -Path $file -Value $pubkey -Encoding ASCII
    Write-Host "WorldViz support key added." -ForegroundColor Green
}

# Required permissions or sshd refuses the file
icacls $file /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
Write-Host "Permissions set." -ForegroundColor Green

$acct = (Get-CimInstance Win32_ComputerSystem).UserName
Write-Host ""
Write-Host ("Done. Current console user: " + $acct) -ForegroundColor Cyan
Write-Host "Tell WorldViz the Windows account name to use for SSH." -ForegroundColor Yellow
