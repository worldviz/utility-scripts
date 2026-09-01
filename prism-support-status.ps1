<#
  prism-support-status.ps1
  Run as: PowerShell (Admin not required)
  Purpose: One-shot health readout of the WorldViz support tunnel and
           network on a PRISM machine. For support calls: "run this and
           read me the screen."
  Run remotely:  iwr -useb util.worldviz.com/prism-support-status.ps1 | iex
  Read-only - changes nothing.
#>

Clear-Host
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "WorldViz PRISM Support Status" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""
Write-Host ("Machine: " + $env:COMPUTERNAME + "   Time: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Gray
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("Last boot: " + $os.LastBootUpTime) -ForegroundColor Gray
Write-Host ""

Write-Host "-- Tailscale" -ForegroundColor Cyan
$ts = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $ts)) {
    Write-Host "  [X] Tailscale NOT INSTALLED" -ForegroundColor Red
} else {
    $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    $svcTxt = "[X] service missing"
    if ($svc) { $svcTxt = "service " + $svc.Status }
    Write-Host ("  " + $svcTxt) -ForegroundColor White
    $ip = (& $ts ip -4 2>$null)
    if ($ip) { Write-Host ("  [OK] tunnel address: " + $ip) -ForegroundColor Green }
    else {
        Write-Host "  [X] no tunnel address" -ForegroundColor Red
        $st = (& $ts status 2>&1 | Select-Object -First 2)
        $st | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Yellow }
    }
}

Write-Host ""
Write-Host "-- SSH service" -ForegroundColor Cyan
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd -and $sshd.Status -eq "Running") { Write-Host "  [OK] sshd running" -ForegroundColor Green }
elseif ($sshd) { Write-Host ("  [X] sshd " + $sshd.Status) -ForegroundColor Red }
else { Write-Host "  [X] sshd not installed" -ForegroundColor Red }
$scopes = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
    Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq 22 } |
    ForEach-Object { ($_ | Get-NetFirewallAddressFilter).RemoteAddress }) | Select-Object -Unique
if ($scopes) { Write-Host ("  port-22 firewall scope: " + ($scopes -join ", ")) -ForegroundColor White }

Write-Host ""
Write-Host "-- Network" -ForegroundColor Cyan
Get-NetIPConfiguration | Where-Object { $_.IPv4Address } | ForEach-Object {
    $gw = ($_.IPv4DefaultGateway.NextHop -join ",")
    $gwTxt = "no gateway"
    if ($gw) { $gwTxt = "gateway " + $gw }
    Write-Host ("  " + $_.InterfaceAlias.PadRight(14) + ($_.IPv4Address.IPAddress -join ",").PadRight(18) + $gwTxt) -ForegroundColor White
}
$defCount = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).Count
if ($defCount -gt 1) {
    Write-Host ("  [!] " + $defCount + " default routes - possible rig-LAN gateway problem") -ForegroundColor Red
}
Write-Host "  internet (443 to Tailscale): " -NoNewline -ForegroundColor White
$net = Test-NetConnection controlplane.tailscale.com -Port 443 -WarningAction SilentlyContinue
if ($net.TcpTestSucceeded) { Write-Host "[OK] reachable" -ForegroundColor Green }
else { Write-Host "[X] BLOCKED or no internet" -ForegroundColor Red }

Write-Host ""
Write-Host "Read this screen to WorldViz support." -ForegroundColor Yellow
Write-Host ""
