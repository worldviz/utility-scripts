<#
  install-prism-support.ps1
  Run as: PowerShell (Admin)
  Purpose: Set up WorldViz remote support access on a PRISM machine.
           Tailscale (tagged, unattended) + OpenSSH scoped to the tailnet
           + rig-LAN network guard + optional customer on/off switch.
  Run remotely:  iwr -useb util.worldviz.com/install-prism-support.ps1 | iex
  Idempotent - safe to re-run; completed steps are skipped.
  Writes a transcript to C:\wvlab\install-prism-support-<timestamp>.log

  Zero-prompt form (paste ONE line, type nothing):
    & ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://util.worldviz.com/install-prism-support.ps1'))) -Site ccreek -AuthKey tskey-auth-XXXX

  Not (iwr ...).Content: GitHub Pages serves .ps1 as application/octet-stream,
  so on Windows PowerShell 5.1 .Content is a byte[] and Create() fails.

  Supplying -Site implies unattended mode: the rig-LAN question and the
  desktop-switch question are skipped unless -RigLanAlias (or -RigLanIndex) /
  -DesktopSwitch are given, and a re-run checks the node identity itself.
  -Site without -AuthKey on an unjoined machine skips the join. With no
  parameters it prompts.

  On site, for a machine joined before shipping (no key needed):
    ... -Site ccreek -RigLanAlias "Ethernet 4"

  The join is fail-soft. If the Tailscale control plane is blocked or the join
  fails, the script says why, still installs OpenSSH (the slow part), and the
  SAME command can be re-run once the network is fixed.

  To convert the rig LAN unattended, name the adapter:
      -RigLanAlias "Ethernet 4"
  Get the name first from the read-only status script (no admin needed):
      iwr -useb util.worldviz.com/prism-support-status.ps1 | iex
#>

param(
    # Site short name, lowercase, WITHOUT the "prism-" prefix (the script adds it).
    [string]$Site,
    # Tailscale auth key, pre-tagged tag:prism-<site>.
    [string]$AuthKey,
    # Rig-LAN adapter BY NAME, e.g. -RigLanAlias "Ethernet 4". Preferred over
    # -RigLanIndex: a name is stable and knowable in advance, whereas a list
    # position shifts when an adapter appears or disappears.
    [string]$RigLanAlias,
    # Rig-LAN adapter by its number in the list the script prints. Omit both to
    # leave the network alone.
    [int]$RigLanIndex = -1,
    # Place the customer Enable/Disable shortcuts on the shared desktop.
    [switch]$DesktopSwitch
)

# -Site supplied => run without asking questions.
$unattended = [bool]$Site

# PowerShell variable names are case-insensitive: a local "$site" IS the -Site
# parameter, and assigning it wiped the value. Keep the working copy distinct.
$siteName = ""
if ($Site) { $siteName = $Site.Trim().ToLower() }

# Check for Administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Start menu -> type powershell -> right-click -> Run as administrator," -ForegroundColor Yellow
    Write-Host "then paste the command again. An elevated window's prompt reads" -ForegroundColor Yellow
    Write-Host "  PS C:\WINDOWS\system32>     (not PS C:\Users\...)" -ForegroundColor Yellow
    return
}

# Reject bad parameters BEFORE anything on the machine changes.
if ($siteName -and ($siteName -like "prism-*")) {
    Write-Host ("-Site must not include the 'prism-' prefix - the script adds it. Use '" +
                ($siteName -replace "^prism-", "") + "'.") -ForegroundColor Red
    return
}
if ($siteName -and ($siteName -notmatch "^[a-z0-9][a-z0-9-]*$")) {
    Write-Host "-Site must be one short word: lowercase letters, digits, hyphens." -ForegroundColor Red
    return
}
if ($AuthKey -and ($AuthKey.Trim() -notmatch "^tskey-")) {
    Write-Host "-AuthKey does not look like a Tailscale auth key (tskey-...)." -ForegroundColor Red
    return
}

# Older PowerShell 5.1 builds default to TLS 1.0; Tailscale and GitHub need 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Node name as the tailnet knows it (first label of the MagicDNS name, which
# shows a "-1" suffix on a collision), falling back to the advertised hostname.
function Get-NodeName($st) {
    if ($st.Self.DNSName) { return ($st.Self.DNSName -split "\.")[0] }
    return $st.Self.HostName
}

# HTTPS GET that must return 200 with $expect in the body. A bare TCP test is
# not enough: at Odessa, 443 to controlplane.tailscale.com connected and the
# campus firewall then silently dropped the session.
function Test-HttpsOk([string]$url, [string]$expect) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $body = $r.Content
        if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
        return ($r.StatusCode -eq 200 -and ((-not $expect) -or ($body -match $expect)))
    } catch { return $false }
}
$ctrlUrl = "https://controlplane.tailscale.com/key?v=71"

# Log everything. Close any stale transcript first so a re-run in the same
# window is still logged.
New-Item -ItemType Directory -Path "C:\wvlab" -Force | Out-Null
$logPath = "C:\wvlab\install-prism-support-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log"
try { Stop-Transcript | Out-Null } catch { }
$transcriptOn = $false
try { Start-Transcript -Path $logPath | Out-Null; $transcriptOn = $true } catch { }

Clear-Host
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "WorldViz PRISM Remote Support Setup" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

# ========== [1/6] NETWORK GUARD (rig-LAN gateway trap) ==========
Write-Host "[1/6] Network check" -ForegroundColor Cyan
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
# Resolve -RigLanAlias to a list position, so everything downstream works the
# same whether the adapter was named or numbered.
if ($RigLanAlias) {
    $match = -1
    for ($j = 0; $j -lt $cfgs.Count; $j++) {
        if ($cfgs[$j].InterfaceAlias -eq $RigLanAlias) { $match = $j; break }
    }
    if ($match -lt 0) {
        Write-Host ("No adapter named '" + $RigLanAlias + "'. Names present: " +
                    (($cfgs | ForEach-Object { "'" + $_.InterfaceAlias + "'" }) -join ", ")) -ForegroundColor Red
        Write-Host "Leaving the network as-is. Re-run with a name from that list." -ForegroundColor Yellow
    } else {
        if ($RigLanIndex -ge 0 -and $RigLanIndex -ne $match) {
            Write-Host ("-RigLanAlias '" + $RigLanAlias + "' is [" + $match +
                        "], not [" + $RigLanIndex + "]. Using the name.") -ForegroundColor Yellow
        }
        $RigLanIndex = $match
        Write-Host ("Rig-LAN adapter '" + $RigLanAlias + "' resolved to [" + $match + "].") -ForegroundColor Gray
    }
}

$ans = "n"
if ($RigLanIndex -ge 0) {
    $ans = "y"
    if (-not $RigLanAlias) {
        Write-Host ("Rig-LAN adapter given as parameter: [" + $RigLanIndex + "] " +
                    $cfgs[[Math]::Min($RigLanIndex, $cfgs.Count - 1)].InterfaceAlias) -ForegroundColor Gray
    }
} elseif (-not $unattended) {
    $ans = Read-Host "Is one of these adapters the PROJECTOR/RIG LAN (no internet)? (y/n)"
} else {
    Write-Host "Unattended: leaving the network alone (pass -RigLanAlias to change it)." -ForegroundColor Gray
}
if ($ans -match "^[yY]") {
    # Which adapter currently carries traffic to the internet? Never strip that
    # one - doing so kills the internet and drops any remote-support session.
    $inetIdx = (Find-NetRoute -RemoteIPAddress 1.1.1.1 -ErrorAction SilentlyContinue |
        Select-Object -First 1).InterfaceIndex
    $idx = "$RigLanIndex"
    if ($RigLanIndex -lt 0) { $idx = (Read-Host "Enter its number from the list above").Trim() }
    if ($idx -notmatch "^\d+$" -or [int]$idx -ge $cfgs.Count) {
        Write-Host ("Not one of the numbers listed (0-" + ($cfgs.Count - 1) + "). Leaving the network as-is.") -ForegroundColor Red
    } else {
        $rig = $cfgs[[int]$idx]
        if ($inetIdx -and $rig.InterfaceIndex -eq $inetIdx) {
            Write-Host ""
            Write-Host ("REFUSING: '" + $rig.InterfaceAlias + "' is the adapter this machine is") -ForegroundColor Red
            Write-Host "currently using to reach the internet." -ForegroundColor Red
            Write-Host "Stripping its gateway would cut internet access and drop any remote" -ForegroundColor Yellow
            Write-Host "support session. Re-run and pick the rig-LAN adapter instead." -ForegroundColor Yellow
        } else {
            $alias = $rig.InterfaceAlias
            $curIp = $rig.IPv4Address.IPAddress | Select-Object -First 1
            $curLen = ($rig.IPv4Address | Select-Object -First 1).PrefixLength
            if (-not $curLen) { $curLen = 24 }
            Write-Host ""
            Write-Host ("Converting '{0}' to STATIC {1}/{2}, NO gateway, NO DNS (fleet standard)..." -f $alias, $curIp, $curLen) -ForegroundColor Yellow
            $go = "y"
            if (-not $unattended) { $go = Read-Host "Proceed? (y/n)" }
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
    }
} else {
    Write-Host "OK - leaving network as-is." -ForegroundColor Gray
}
$defRoutes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)
Write-Host ("Default route(s) now: " + (($defRoutes | ForEach-Object { $_.InterfaceAlias + " via " + $_.NextHop }) -join " | ")) -ForegroundColor Gray

# ========== [2/6] TAILSCALE ==========
Write-Host ""
Write-Host "[2/6] Tailscale" -ForegroundColor Cyan
Write-Host ""

$ts = "C:\Program Files\Tailscale\tailscale.exe"
# Outcome of this stage, reported at the end:
#   joined | already | skipped | blocked | failed | notinstalled
$joinState = ""
$joinOut = @()

if (-not (Test-Path $ts)) {
    # MSI straight from Tailscale, not winget: winget is missing or broken on
    # plenty of fresh/LTSC/locked-down machines (it failed at Odessa).
    # TS_NOLAUNCH stops the MSI starting the tray app, which otherwise opens an
    # interactive browser login that blocks the auth-key join below.
    $msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi"
    $msi = "C:\wvlab\tailscale-setup-latest-amd64.msi"
    Write-Host "Downloading Tailscale..." -ForegroundColor Yellow
    try {
        (New-Object Net.WebClient).DownloadFile($msiUrl, $msi)
    } catch {
        Write-Host ("  [X] download failed: " + $_.Exception.Message) -ForegroundColor Red
    }
    if (Test-Path $msi) {
        Write-Host "Installing Tailscale (silent, about a minute)..." -ForegroundColor Yellow
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
            "/i", ('"' + $msi + '"'), "/qn", "/norestart", "TS_NOLAUNCH=true",
            "/l*v", '"C:\wvlab\tailscale-msi.log"')
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            Write-Host ("  [X] msiexec exit code " + $p.ExitCode + " - see C:\wvlab\tailscale-msi.log") -ForegroundColor Red
        }
        Start-Sleep -Seconds 3
    }
}

if (-not (Test-Path $ts)) {
    $joinState = "notinstalled"
    Write-Host "Tailscale is not installed. If the download failed, this network" -ForegroundColor Red
    Write-Host "blocks pkgs.tailscale.com - see the IT allowlist at the end." -ForegroundColor Red
    Write-Host "Continuing with the rest of the setup." -ForegroundColor Yellow
} else {
    $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne "Running") { Start-Service -Name Tailscale; Start-Sleep -Seconds 2 }

    $already = (& $ts ip -4 2>$null)
    if ($already) {
        $joinState = "already"
        # Every WV-imaged IG is hostname WV-PRISM-IG. If this box was imaged from
        # another site it may already carry THAT site's node name and tag.
        $selfName = ""
        $selfTags = @()
        try {
            $st = (& $ts status --json 2>$null | Out-String | ConvertFrom-Json)
            $selfName = Get-NodeName $st
            if ($st.Self.Tags) { $selfTags = @($st.Self.Tags) }
        } catch { }
        $tagTxt = "none"
        if ($selfTags.Count) { $tagTxt = ($selfTags -join ",") }
        Write-Host ("Tailscale already joined: " + ($already -join " ")) -ForegroundColor Gray
        Write-Host ("  node name: " + $selfName + "    tags: " + $tagTxt) -ForegroundColor Gray
        $sameSite = $true
        if ($siteName -and $selfName) {
            # -Site given: decide without asking.
            $sameSite = ($selfName -eq ("prism-" + $siteName))
        } elseif ($selfName) {
            Write-Host "If this machine was imaged from another site, that name and tag belong" -ForegroundColor Yellow
            Write-Host "to the OTHER site - it must not keep them." -ForegroundColor Yellow
            $ok = Read-Host "Is that the correct identity for THIS site? (y/n)"
            $sameSite = ($ok -match "^[yY]")
        }
        if (-not $sameSite) {
            Write-Host ""
            Write-Host "This machine carries another identity. Drop it, then re-run:" -ForegroundColor Red
            Write-Host '  & "C:\Program Files\Tailscale\tailscale.exe" logout' -ForegroundColor White
            try { if ($transcriptOn) { Stop-Transcript | Out-Null } } catch { }
            return
        }
    } else {
        $key = ""
        if ($AuthKey) {
            $key = $AuthKey.Trim()
            Write-Host "Using auth key supplied as a parameter." -ForegroundColor Gray
        } elseif ($unattended) {
            Write-Host "No -AuthKey given." -ForegroundColor Gray
        } else {
            while ($true) {
                $key = (Read-Host "Tailscale auth key from WorldViz (tskey-auth-...), or press Enter to SKIP the join for now").Trim()
                if (-not $key -or $key -match "^tskey-") { break }
                Write-Host "That does not look like a Tailscale auth key (they start with tskey-)." -ForegroundColor Red
                Write-Host "Paste ONLY the key on one line, or press Enter to skip the join." -ForegroundColor Yellow
            }
        }
        if (-not $key) {
            $joinState = "skipped"
            Write-Host "Skipping the join - continuing with the rest of the setup." -ForegroundColor Yellow
        } else {
            while ($siteName -notmatch "^[a-z0-9][a-z0-9-]*$" -or $siteName -like "prism-*") {
                if ($siteName -like "prism-*") {
                    # The node name is built as "prism-<site>"; a site name that
                    # already carries the prefix produces prism-prism-<site>.
                    Write-Host ("Do not include the 'prism-' prefix - the script adds it. Use '" +
                                ($siteName -replace "^prism-", "") + "'.") -ForegroundColor Red
                } elseif ($siteName -ne "") {
                    Write-Host "One short word: lowercase letters, digits, hyphens only." -ForegroundColor Red
                }
                $siteName = (Read-Host "Site short name from WorldViz (lowercase, e.g. sioux - no 'prism-' prefix)").Trim().ToLower()
            }

            Write-Host "Checking HTTPS to the Tailscale control plane..." -ForegroundColor Gray
            if (-not (Test-HttpsOk $ctrlUrl "publicKey")) {
                $joinState = "blocked"
                Write-Host ("  [X] " + $ctrlUrl + " did not answer") -ForegroundColor Red
                Write-Host "  The join cannot work from this network yet. Usual causes: the" -ForegroundColor Yellow
                Write-Host "  facility firewall blocks controlplane.tailscale.com, or the rig-LAN" -ForegroundColor Yellow
                Write-Host "  gateway trap (step 1). Skipping the join; continuing setup." -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] control plane reachable" -ForegroundColor Green
                # A tray app left over from the install (or an earlier attempt) may
                # be mid-way through an interactive browser login, which makes the
                # service ignore the auth key. Interactive login would also join
                # the node UNTAGGED. Clear it before joining.
                Get-Process -Name "tailscale-ipn" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Restart-Service -Name Tailscale -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                Write-Host ("Joining as prism-" + $siteName + " (up to 60 s)...") -ForegroundColor Yellow
                # Foreground, so its error text is shown instead of lost in a job.
                $joinOut = @(& $ts up --authkey $key --hostname ("prism-" + $siteName) --unattended --timeout 60s 2>&1 |
                    ForEach-Object { "$_" })
                $joinOut | Where-Object { $_ } | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Gray }
                if (& $ts ip -4 2>$null) {
                    $joinState = "joined"
                } else {
                    $joinState = "failed"
                    Write-Host "  [X] join failed - the lines above say why. Continuing setup." -ForegroundColor Red
                }
            }
        }
    }
}
$tsip = ""
if (Test-Path $ts) { $tsip = (& $ts ip -4 2>$null | Select-Object -First 1) }
if ($tsip) { Write-Host ("Tailscale address: " + $tsip) -ForegroundColor Green }

# ---- TAG ASSERTION -------------------------------------------------------
# The entire isolation model depends on this node being TAGGED. A tagged node
# is not in autogroup:member, so with no src grant it can reach nothing. An
# UNTAGGED node joins as one of Andy's own devices and inherits the
# member->member grant: full access to his Mac, phone and every VPS.
# An auth key generated without its tag selected produces exactly that, and
# it otherwise looks like a completely successful install.
$tagOK = $false
$tagNote = ""
if ($tsip) {
    $selfTags = @()
    $selfName = ""
    try {
        $st = (& $ts status --json 2>$null | Out-String | ConvertFrom-Json)
        $selfName = Get-NodeName $st
        if ($st.Self.Tags) { $selfTags = @($st.Self.Tags) }
    } catch { }

    if ($selfTags.Count -gt 0) {
        $tagOK = $true
        Write-Host ("Tags: " + ($selfTags -join ", ")) -ForegroundColor Green
        if ($siteName -and ($selfTags -notcontains ("tag:prism-" + $siteName))) {
            $tagNote = "node is tagged, but not with tag:prism-$siteName"
            Write-Host ("  NOTE: expected tag:prism-" + $siteName) -ForegroundColor Yellow
        }
    } else {
        $tagNote = "NODE JOINED UNTAGGED"
        Write-Host ""
        Write-Host ("!" * 60) -ForegroundColor Red
        Write-Host " THIS NODE JOINED UNTAGGED - STOP AND TELL WORLDVIZ NOW" -ForegroundColor Yellow -BackgroundColor DarkRed
        Write-Host ("!" * 60) -ForegroundColor Red
        Write-Host " The auth key was not carrying its tag, so this machine has" -ForegroundColor Yellow
        Write-Host " joined as a regular member device instead of an isolated site" -ForegroundColor Yellow
        Write-Host " node. Until it is tagged it can reach other machines on the" -ForegroundColor Yellow
        Write-Host " tailnet - the one-way door is NOT in place." -ForegroundColor Yellow
        Write-Host ""
        Write-Host " Fix (WorldViz): newsite.py tag <site>  - no reinstall needed." -ForegroundColor Gray
        Write-Host ("!" * 60) -ForegroundColor Red
        Write-Host ""
    }
    if ($selfName -and $siteName -and $selfName -ne ("prism-" + $siteName)) {
        Write-Host ("NOTE: node name is '" + $selfName + "', expected 'prism-" + $siteName + "'.") -ForegroundColor Yellow
        if (-not $tagNote) { $tagNote = "node name is $selfName" }
    }
}

# ========== [3/6] OPTIONAL: CUSTOMER ON/OFF SWITCH ==========
Write-Host ""
Write-Host "[3/6] Customer on/off switch (optional)" -ForegroundColor Cyan
Write-Host ""
$ans = "n"
if ($DesktopSwitch) { $ans = "y" }
elseif (-not $unattended) { $ans = Read-Host "Place Enable/Disable WorldViz Support shortcuts on the shared desktop? (y/n)" }
if ($ans -match "^[yY]") {
    $desk = Join-Path $env:PUBLIC "Desktop"
    $enable = "@echo off`r`nREM Turns the WorldViz support tunnel ON.`r`n`"C:\Program Files\Tailscale\tailscale.exe`" up`r`necho.`r`necho WorldViz support tunnel is ON.`r`npause`r`n"
    $disable = "@echo off`r`nREM Turns the WorldViz support tunnel OFF. Nothing is connected while off.`r`n`"C:\Program Files\Tailscale\tailscale.exe`" down`r`necho.`r`necho WorldViz support tunnel is OFF. No remote access is possible.`r`npause`r`n"
    Set-Content -Path (Join-Path $desk "Enable WorldViz Support.cmd") -Value $enable -Encoding ASCII
    Set-Content -Path (Join-Path $desk "Disable WorldViz Support.cmd") -Value $disable -Encoding ASCII
    Write-Host "Shortcuts placed on the shared desktop." -ForegroundColor Green
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Yellow
Write-Host "ALL QUESTIONS DONE - the rest runs unattended (15-20 min)." -ForegroundColor Yellow -BackgroundColor DarkBlue
Write-Host "You may leave this window running. Do NOT close it or reboot." -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Yellow

# ========== [4/6] OPENSSH SERVER ==========
Write-Host ""
Write-Host "[4/6] OpenSSH Server" -ForegroundColor Cyan
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
    try { if ($transcriptOn) { Stop-Transcript | Out-Null } } catch { }
    return
}
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd -ErrorAction SilentlyContinue
Write-Host "OpenSSH Server installed and running." -ForegroundColor Green

# ========== [5/6] FIREWALL: SSH visible ONLY over the tunnel ==========
Write-Host ""
Write-Host "[5/6] Firewall scoping" -ForegroundColor Cyan
Write-Host ""

$tailnet = "100.64.0.0/10"
$scoped = 0
# Deliberately NOT filtered to -Enabled True: a disabled port-22 rule left at
# RemoteAddress=Any is a loaded gun. Anything that later enables it (sshd
# reinstall, an admin clicking "allow") would expose SSH on the customer LAN.
Get-NetFirewallRule -Direction Inbound -Action Allow -ErrorAction SilentlyContinue | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter
    if ($pf.Protocol -eq "TCP" -and $pf.LocalPort -eq 22) {
        Set-NetFirewallRule -Name $_.Name -RemoteAddress $tailnet
        $state = "enabled"
        if ($_.Enabled -ne "True") { $state = "disabled" }
        Write-Host ("  scoped rule: " + $_.DisplayName + " (" + $state + ")") -ForegroundColor Green
        $scoped++
    }
}
if ($scoped -eq 0) {
    New-NetFirewallRule -DisplayName "OpenSSH tailnet only" -Direction Inbound `
        -Protocol TCP -LocalPort 22 -RemoteAddress $tailnet -Action Allow | Out-Null
    Write-Host "  created scoped rule 'OpenSSH tailnet only'" -ForegroundColor Green
}
Write-Host "SSH is now invisible on the local network - reachable only via the tunnel." -ForegroundColor Green

# ========== [6/6] WORLDVIZ SUPPORT KEY ==========
Write-Host ""
Write-Host "[6/6] WorldViz support SSH key" -ForegroundColor Cyan
Write-Host ""
# One source of truth for the public key: the standalone script.
$keyOK = $false
try {
    & ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://util.worldviz.com/install-wv-ssh-key.ps1')))
    $keyOK = $true
} catch {
    Write-Host ("  [X] could not fetch install-wv-ssh-key.ps1: " + $_.Exception.Message) -ForegroundColor Red
}
# sshd only reads administrators_authorized_keys for accounts in the local
# Administrators group (SID S-1-5-32-544).
$acct = (Get-CimInstance Win32_ComputerSystem).UserName
$isAdmin = "unknown"
try {
    $admins = @(Get-LocalGroupMember -SID "S-1-5-32-544" -ErrorAction Stop | ForEach-Object { $_.Name })
    if ($acct) {
        $isAdmin = "NO"
        if ($admins -contains $acct) { $isAdmin = "yes" }
    }
} catch { }

# ========== SUMMARY ==========
$svc = Get-Service sshd -ErrorAction SilentlyContinue
$sshTxt = "[X] not running"
if ($svc -and $svc.Status -eq "Running") { $sshTxt = "[OK] running" }
$scopes = @(Get-NetFirewallRule -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
    Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq 22 } |
    ForEach-Object { ($_ | Get-NetFirewallAddressFilter).RemoteAddress } | Select-Object -Unique)
$tunnelOK = [bool]$tsip

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
if ($tunnelOK) { Write-Host "Setup Complete" -ForegroundColor Yellow }
else { Write-Host "Setup done EXCEPT the Tailscale join" -ForegroundColor Yellow }
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
$tsTxt = $tsip
switch ($joinState) {
    "blocked"      { $tsTxt = "[X] not joined - control plane BLOCKED by this network" }
    "failed"       { $tsTxt = "[X] not joined - join failed (see output above)" }
    "skipped"      { $tsTxt = "[ ] not joined - skipped (no key)" }
    "notinstalled" { $tsTxt = "[X] Tailscale not installed - download blocked?" }
}
Write-Host ("  Tailscale:      " + $tsTxt) -ForegroundColor White
if ($tunnelOK) {
    if ($tagOK -and -not $tagNote) {
        Write-Host "  Tag check:      [OK] tagged - isolation in place" -ForegroundColor Green
    } elseif ($tagOK) {
        Write-Host ("  Tag check:      [!] " + $tagNote) -ForegroundColor Yellow
    } else {
        Write-Host "  Tag check:      [X] UNTAGGED - NOT ISOLATED - tell WorldViz" -ForegroundColor Yellow -BackgroundColor DarkRed
    }
}
Write-Host ("  OpenSSH:        " + $sshTxt) -ForegroundColor White
Write-Host ("  SSH visibility: " + ($scopes -join ", ")) -ForegroundColor White
$keyTxt = "[X] not installed"
if ($keyOK) { $keyTxt = "[OK]" }
Write-Host ("  Support key:    " + $keyTxt) -ForegroundColor White
Write-Host ("  SSH user:       " + $acct + "   (Administrator: " + $isAdmin + ")") -ForegroundColor White
if ($isAdmin -eq "NO") {
    Write-Host "    Key login only works for Administrators - tell WorldViz." -ForegroundColor Yellow
}
Write-Host ("  Log file:       " + $logPath) -ForegroundColor White
Write-Host ""

if ($joinState -eq "blocked" -or $joinState -eq "notinstalled") {
    Write-Host "This network blocks Tailscale. Send this to the site's IT team:" -ForegroundColor Yellow -BackgroundColor DarkBlue
    Write-Host "  Please allow outbound HTTPS (TCP 443, and TCP 80) to *.tailscale.com" -ForegroundColor White
    Write-Host "  and *.tailscale.io from this PC. Optional, for faster direct links:" -ForegroundColor White
    Write-Host "  outbound UDP 3478 and UDP 41641." -ForegroundColor White
    Write-Host ("  Test: open " + $ctrlUrl + " in a browser on") -ForegroundColor White
    Write-Host "  this PC. Working = a short page containing 'publicKey'." -ForegroundColor White
    Write-Host ""
}
if ($tunnelOK) {
    Write-Host "READ THIS ADDRESS TO WORLDVIZ:  $tsip" -ForegroundColor Yellow -BackgroundColor DarkBlue
} else {
    Write-Host "When the network is fixed, run the SAME command again." -ForegroundColor Yellow -BackgroundColor DarkBlue
    Write-Host "Everything already done is skipped; only the join remains." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "WorldViz completes their side (key-expiry disable, isolation checks)." -ForegroundColor Gray
Write-Host ""
try { if ($transcriptOn) { Stop-Transcript | Out-Null } } catch { }
