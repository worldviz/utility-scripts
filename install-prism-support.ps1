<#
  install-prism-support.ps1
  Run as: PowerShell (Admin)
  Purpose: Set up WorldViz remote support access on a PRISM machine.
           Tailscale (tagged, unattended) + OpenSSH scoped to the tailnet
           + rig-LAN network guard + optional customer on/off switch.
  Run remotely:  iwr -useb util.worldviz.com/install-prism-support.ps1 | iex
  Idempotent - safe to re-run; completed steps are skipped.
#>

# Check for Administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell, 'Run as Administrator', then re-run the command." -ForegroundColor Yellow
    return
}

Clear-Host
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "WorldViz PRISM Remote Support Setup" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

# ========== [1/5] NETWORK GUARD (rig-LAN gateway trap) ==========
Write-Host "[1/5] Network check" -ForegroundColor Cyan
Write-Host ""
Write-Host "A projector/rig LAN adapter with a default gateway breaks internet" -ForegroundColor Gray
Write-Host "routing and hangs Tailscale. Checking adapters..." -ForegroundColor Gray
Write-Host ""

$cfgs = @(Get-NetIPConfiguration | Where-Object { $_.IPv4Address })
$i = 0
foreach ($c in $cfgs) {
    $gw = ($c.IPv4DefaultGateway.NextHop -join ",")
    $gwTxt = "no gateway"
    if ($gw) { $gwTxt = "gateway " + $gw }
    Write-Host ("  [{0}] {1}  {2}  ({3})" -f $i, $c.InterfaceAlias.PadRight(14), ($c.IPv4Address.IPAddress -join ","), $gwTxt) -ForegroundColor White
    $i++
}
Write-Host ""
$gwCount = @($cfgs | Where-Object { $_.IPv4DefaultGateway }).Count
if ($gwCount -gt 1) {
    Write-Host "WARNING: multiple default gateways found - one is likely the rig LAN." -ForegroundColor Red
}
$ans = Read-Host "Is one of these adapters the PROJECTOR/RIG LAN (no internet)? (y/n)"
if ($ans -match "^[yY]") {
    $idx = Read-Host "Enter its number from the list above"
    $rig = $cfgs[[int]$idx]
    if ($rig) {
        $alias = $rig.InterfaceAlias
        $curIp = $rig.IPv4Address.IPAddress | Select-Object -First 1
        $curLen = ($rig.IPv4Address | Select-Object -First 1).PrefixLength
        if (-not $curLen) { $curLen = 24 }
        Write-Host ""
        Write-Host ("Converting '{0}' to STATIC {1}/{2}, NO gateway, NO DNS (fleet standard)..." -f $alias, $curIp, $curLen) -ForegroundColor Yellow
        $go = Read-Host "Proceed? (y/n)"
        if ($go -match "^[yY]") {
            Set-NetIPInterface -InterfaceAlias $alias -Dhcp Disabled
            Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceAlias $alias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $alias -IPAddress $curIp -PrefixLength $curLen | Out-Null
            Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses
            Write-Host "Rig LAN adapter converted." -ForegroundColor Green
            Write-Host "NOTE: ask WorldViz to reserve this IP on the rig router (DHCP reservation)." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "OK - leaving network as-is." -ForegroundColor Gray
}
$defRoutes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)
Write-Host ("Default route(s) now: " + (($defRoutes | ForEach-Object { $_.InterfaceAlias + " via " + $_.NextHop }) -join " | ")) -ForegroundColor Gray

# ========== [2/5] TAILSCALE ==========
Write-Host ""
Write-Host "[2/5] Tailscale" -ForegroundColor Cyan
Write-Host ""

$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $ts)) {
    Write-Host "Installing Tailscale via winget..." -ForegroundColor Yellow
    winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
    Start-Sleep -Seconds 3
}
if (-not (Test-Path $ts)) {
    Write-Host "Tailscale not found after install. Install manually from:" -ForegroundColor Red
    Write-Host "  https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" -ForegroundColor Yellow
    Write-Host "then re-run this script." -ForegroundColor Yellow
    return
}
$svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne "Running") { Start-Service -Name Tailscale; Start-Sleep -Seconds 2 }

$already = (& $ts ip -4 2>$null)
if ($already) {
    Write-Host ("Tailscale already joined: " + $already) -ForegroundColor Gray
} else {
    $site = Read-Host "Site short name from WorldViz (e.g. sioux)"
    $key = Read-Host "Tailscale auth key from WorldViz (tskey-auth-...)"
    Write-Host "Joining tailnet (this should take a few seconds)..." -ForegroundColor Yellow
    $job = Start-Job -ScriptBlock {
        param($exe, $k, $h)
        & $exe up --authkey $k --hostname $h --unattended 2>&1
    } -ArgumentList $ts, $key, ("prism-" + $site)
    if (-not (Wait-Job $job -Timeout 90)) {
        Stop-Job $job
        Write-Host ""
        Write-Host "Tailscale join TIMED OUT. Common causes:" -ForegroundColor Red
        Write-Host "  1. Rig-LAN adapter still has a default gateway (step 1)" -ForegroundColor Yellow
        Write-Host "  2. Facility firewall blocks outbound port 443" -ForegroundColor Yellow
        Write-Host "     test:  Test-NetConnection controlplane.tailscale.com -Port 443" -ForegroundColor Gray
        Write-Host "Fix and re-run this script." -ForegroundColor Yellow
        Remove-Job $job -Force
        return
    }
    Receive-Job $job | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Gray }
    Remove-Job $job -Force
}
$tsip = (& $ts ip -4 2>$null)
if ($tsip) { Write-Host ("Tailscale address: " + $tsip) -ForegroundColor Green }
else { Write-Host "Tailscale has no address - resolve before continuing." -ForegroundColor Red; return }

# ========== [3/5] OPENSSH SERVER ==========
Write-Host ""
Write-Host "[3/5] OpenSSH Server" -ForegroundColor Cyan
Write-Host ""

$cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
if ($cap.State -ne "Installed") {
    Write-Host "Installing OpenSSH Server (5-15 minutes - be patient)..." -ForegroundColor Yellow
    foreach ($try in 1, 2) {
        $job = Start-Job -ScriptBlock { param($n) Add-WindowsCapability -Online -Name $n } -ArgumentList $cap.Name
        while ($job.State -eq "Running") { Write-Host "." -NoNewline -ForegroundColor Gray; Start-Sleep -Seconds 5 }
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job -Force
        Write-Host ""
        $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
        if ($cap.State -eq "Installed") { break }
        if ($try -eq 1) { Write-Host "First attempt failed (this is common) - retrying once..." -ForegroundColor Yellow }
    }
}
if ($cap.State -ne "Installed") {
    Write-Host "OpenSSH capability install failed twice. On WSUS-managed machines try:" -ForegroundColor Red
    Write-Host "  winget install --id Microsoft.OpenSSH.Preview -e" -ForegroundColor Yellow
    Write-Host "then re-run this script." -ForegroundColor Yellow
    return
}
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd -ErrorAction SilentlyContinue
Write-Host "OpenSSH Server installed and running." -ForegroundColor Green

# ========== [4/5] FIREWALL: SSH visible ONLY over the tunnel ==========
Write-Host ""
Write-Host "[4/5] Firewall scoping" -ForegroundColor Cyan
Write-Host ""

$tailnet = "100.64.0.0/10"
$scoped = 0
Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter
    if ($pf.Protocol -eq "TCP" -and $pf.LocalPort -eq 22) {
        Set-NetFirewallRule -Name $_.Name -RemoteAddress $tailnet
        Write-Host ("  scoped rule: " + $_.DisplayName) -ForegroundColor Green
        $scoped++
    }
}
if ($scoped -eq 0) {
    New-NetFirewallRule -DisplayName "OpenSSH tailnet only" -Direction Inbound `
        -Protocol TCP -LocalPort 22 -RemoteAddress $tailnet -Action Allow | Out-Null
    Write-Host "  created scoped rule 'OpenSSH tailnet only'" -ForegroundColor Green
}
Write-Host "SSH is now invisible on the local network - reachable only via the tunnel." -ForegroundColor Green
New-Item -ItemType Directory -Path "C:\wvlab" -Force | Out-Null

# ========== [5/5] OPTIONAL: CUSTOMER ON/OFF SWITCH ==========
Write-Host ""
Write-Host "[5/5] Customer on/off switch (optional)" -ForegroundColor Cyan
Write-Host ""
$ans = Read-Host "Place Enable/Disable WorldViz Support shortcuts on the shared desktop? (y/n)"
if ($ans -match "^[yY]") {
    $desk = Join-Path $env:PUBLIC "Desktop"
    $enable = "@echo off`r`nREM Turns the WorldViz support tunnel ON.`r`n`"C:\Program Files\Tailscale\tailscale.exe`" up`r`necho.`r`necho WorldViz support tunnel is ON.`r`npause`r`n"
    $disable = "@echo off`r`nREM Turns the WorldViz support tunnel OFF. Nothing is connected while off.`r`n`"C:\Program Files\Tailscale\tailscale.exe`" down`r`necho.`r`necho WorldViz support tunnel is OFF. No remote access is possible.`r`npause`r`n"
    Set-Content -Path (Join-Path $desk "Enable WorldViz Support.cmd") -Value $enable -Encoding ASCII
    Set-Content -Path (Join-Path $desk "Disable WorldViz Support.cmd") -Value $disable -Encoding ASCII
    Write-Host "Shortcuts placed on the shared desktop." -ForegroundColor Green
}

# ========== COMPLETION ==========
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "Setup Complete" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Write-Host "Verification:" -ForegroundColor Cyan
Write-Host ("  Tailscale IP:   " + $tsip) -ForegroundColor White
$svc = Get-Service sshd -ErrorAction SilentlyContinue
$sshTxt = "[X] not running"
if ($svc -and $svc.Status -eq "Running") { $sshTxt = "[OK] running" }
Write-Host ("  OpenSSH:        " + $sshTxt) -ForegroundColor White
$scopes = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow |
    Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq 22 } |
    ForEach-Object { ($_ | Get-NetFirewallAddressFilter).RemoteAddress })
Write-Host ("  SSH visibility: " + (($scopes | Select-Object -Unique) -join ", ")) -ForegroundColor White
Write-Host ""
Write-Host "READ THIS ADDRESS TO WORLDVIZ:  $tsip" -ForegroundColor Yellow -BackgroundColor DarkBlue
Write-Host ""
Write-Host "WorldViz will then verify the connection and complete their side" -ForegroundColor Gray
Write-Host "(key-expiry disable, isolation checks)." -ForegroundColor Gray
Write-Host ""
