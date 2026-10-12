<#
  prep-prism.ps1
  Run as: PowerShell (Admin)
  Purpose: Prep a PRISM PC for WorldViz remote support - everything except
           the Tailscale join. No key, no questions. Short form of
           install-prism-support.ps1 -Prep, so it can be typed if a paste fails.
  Run remotely:  iwr -useb util.worldviz.com/prep-prism.ps1 | iex
  The join is a separate step with a one-time key from WorldViz.
#>

# iex cannot pass parameters, so call the installer as a scriptblock.
# DownloadString, not (iwr).Content: GitHub Pages serves .ps1 as
# application/octet-stream, which is a byte[] on PowerShell 5.1.
& ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://util.worldviz.com/install-prism-support.ps1'))) -Prep
