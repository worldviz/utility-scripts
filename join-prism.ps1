<#
  join-prism.ps1
  Run as: PowerShell (Admin)
  Purpose: Join a PRISM PC to WorldViz support WITHOUT an auth key.
           The PC asks to join as tag:prism-<site> and shows a login link;
           a WorldViz admin opens the link and approves. Only a tailnet admin
           may apply the tag, so the link is a request, not a secret.
  Run remotely:  iwr -useb util.worldviz.com/join-prism.ps1 | iex
  Prereq: WorldViz has added the site to the tailnet policy
          (newsite.py add <site> --no-key). Prep first (prep-prism.ps1) is
          fastest; if Tailscale is missing, this runs the prep itself.
  Fallback when nobody can approve: the auth-key line from WorldViz.
#>

param([string]$Site)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Start menu -> type powershell -> right-click -> Run as administrator," -ForegroundColor Yellow
    Write-Host "then run the command again. The prompt should read PS C:\WINDOWS\system32>" -ForegroundColor Yellow
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Path "C:\wvlab" -Force | Out-Null
$installer = [scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://util.worldviz.com/install-prism-support.ps1'))
$ts = "C:\Program Files\Tailscale\tailscale.exe"

function Get-TsStatus {
    try { return (& $ts status --json 2>$null | Out-String | ConvertFrom-Json) } catch { return $null }
}

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "WorldViz PRISM - join support (approval link)" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ts)) {
    Write-Host "Tailscale is not installed yet - running the prep first (about 20 min)." -ForegroundColor Yellow
    & $installer -Prep
    if (-not (Test-Path $ts)) {
        Write-Host "The prep did not install Tailscale - see the messages above." -ForegroundColor Red
        return
    }
}
$svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne "Running") { Start-Service -Name Tailscale; Start-Sleep -Seconds 2 }

# Already joined: report, never re-join.
if (& $ts ip -4 2>$null) {
    $st = Get-TsStatus
    $name = ""
    $tags = @()
    if ($st) {
        if ($st.Self.DNSName) { $name = ($st.Self.DNSName -split "\.")[0] } else { $name = $st.Self.HostName }
        if ($st.Self.Tags) { $tags = @($st.Self.Tags) }
    }
    if ($tags.Count) {
        Write-Host ("Already joined as " + $name + " (" + ($tags -join ", ") + "). Nothing to do.") -ForegroundColor Green
    } else {
        Write-Host ("Already joined as " + $name + " but UNTAGGED - not isolated. Tell WorldViz now.") -ForegroundColor Yellow -BackgroundColor DarkRed
    }
    return
}

# Site name: parameter, or ask.
$siteName = ""
if ($Site) { $siteName = $Site.Trim().ToLower() }
while ($siteName -notmatch "^[a-z0-9][a-z0-9-]*$" -or $siteName -like "prism-*") {
    if ($siteName -like "prism-*") {
        Write-Host ("Leave off the 'prism-' prefix: type '" + ($siteName -replace "^prism-", "") + "'.") -ForegroundColor Red
    } elseif ($siteName -ne "") {
        Write-Host "One short word: lowercase letters, digits, hyphens only." -ForegroundColor Red
    }
    $siteName = (Read-Host "Site name from WorldViz (e.g. froedtert)").Trim().ToLower()
}
$tag = "tag:prism-" + $siteName
$node = "prism-" + $siteName

# Same HTTPS check as the installer: some firewalls accept the TCP connect
# and then drop the session.
$ctrlOK = $false
try {
    $r = Invoke-WebRequest -Uri "https://controlplane.tailscale.com/key?v=71" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    $body = $r.Content
    if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
    $ctrlOK = ($r.StatusCode -eq 200 -and $body -match "publicKey")
} catch { }
if (-not $ctrlOK) {
    Write-Host "[X] This network blocks the Tailscale control plane. Ask the site's IT to allow" -ForegroundColor Red
    Write-Host "    outbound HTTPS (TCP 443 and 80) to *.tailscale.com and *.tailscale.io." -ForegroundColor Red
    return
}

# A tray app mid-way through a browser login makes the service ignore this
# request. Clear it first.
Get-Process -Name "tailscale-ipn" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Restart-Service -Name Tailscale -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$outFile = "C:\wvlab\join-prism-out.txt"
$errFile = "C:\wvlab\join-prism-err.txt"
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
Write-Host ("Requesting to join as " + $node + " (" + $tag + ")...") -ForegroundColor Gray
$proc = Start-Process -FilePath $ts -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
    -ArgumentList @("up", "--advertise-tags=$tag", "--hostname=$node", "--unattended", "--timeout=600s")

# Wait for the login link (from status, or from tailscale's own output).
$url = ""
for ($i = 0; $i -lt 45 -and -not $url -and -not $proc.HasExited; $i++) {
    Start-Sleep -Seconds 1
    $st = Get-TsStatus
    if ($st -and $st.AuthURL) { $url = $st.AuthURL }
    if (-not $url) {
        $txt = ((Get-Content $outFile, $errFile -Raw -ErrorAction SilentlyContinue) -join "`n")
        if ($txt -match "https://login\.tailscale\.com/a/[0-9A-Za-z]+") { $url = $Matches[0] }
    }
}

if ($url) {
    $code = ($url -split "/")[-1]
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host " SEND THIS LINK TO WORLDVIZ FOR APPROVAL " -ForegroundColor Yellow -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host ("   " + $url) -ForegroundColor White
    Write-Host ""
    Write-Host ("   (short code: " + $code + ")") -ForegroundColor Gray
    Write-Host ""
    Write-Host " Slack it, photograph it, or read it out. Do NOT open it yourself:" -ForegroundColor Yellow
    Write-Host " only a WorldViz admin can approve it." -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Waiting for approval (up to 10 minutes)" -NoNewline -ForegroundColor Gray
}

$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
    Start-Sleep -Seconds 3
    if (& $ts ip -4 2>$null) { break }
    Write-Host "." -NoNewline -ForegroundColor Gray
}
Write-Host ""

if (-not (& $ts ip -4 2>$null)) {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Write-Host "Not joined." -ForegroundColor Red
    $txt = ((Get-Content $outFile, $errFile -Raw -ErrorAction SilentlyContinue) -join "`n").Trim()
    if ($txt) { $txt -split "`n" | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Gray } }
    Write-Host "Run the same command again when WorldViz is ready to approve," -ForegroundColor Yellow
    Write-Host "or use the auth-key line from WorldViz instead." -ForegroundColor Yellow
    return
}

Write-Host "Approved and joined. Running the final checks..." -ForegroundColor Green
Write-Host ""
# The installer with -Site skips what is done and prints the usual summary,
# including the tag assertion. On a prepped PC this takes about a minute.
& $installer -Site $siteName
