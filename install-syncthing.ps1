# Simple Syncthing Installer for CARLA Lab
# Just downloads and installs Syncthing - no automation, no services

param(
    [string]$InstallPath = "C:\wvlab\syncthing"
)

Write-Host "Simple Syncthing Installer" -ForegroundColor Green
Write-Host "This will download and install Syncthing to: $InstallPath" -ForegroundColor Yellow
Write-Host ""

# Check if already installed
$syncthingExe = "$InstallPath\syncthing.exe"
if (Test-Path $syncthingExe) {
    Write-Host "Syncthing is already installed at $InstallPath" -ForegroundColor Green
    Write-Host "To start Syncthing, run: $syncthingExe" -ForegroundColor Yellow
    exit 0
}

# Create install directory
Write-Host "Creating installation directory..." -ForegroundColor Yellow
New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null

# Download latest Syncthing
Write-Host "Downloading latest Syncthing..." -ForegroundColor Yellow
try {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/syncthing/syncthing/releases/latest"
    $windowsAsset = $releases.assets | Where-Object { $_.name -match "windows-amd64" -and $_.name -match "\.zip$" }
    
    if (-not $windowsAsset) {
        throw "Could not find Windows release"
    }
    
    $downloadUrl = $windowsAsset.browser_download_url
    $zipPath = "$env:TEMP\syncthing.zip"
    
    Write-Host "Downloading from: $downloadUrl" -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    
    # Extract
    Write-Host "Extracting files..." -ForegroundColor Yellow
    Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\syncthing_extract" -Force
    
    # Copy files (the zip contains a versioned folder)
    $extractedFolder = Get-ChildItem "$env:TEMP\syncthing_extract" | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    Copy-Item "$($extractedFolder.FullName)\*" -Destination $InstallPath -Recurse -Force
    
    # Cleanup
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\syncthing_extract" -Recurse -ErrorAction SilentlyContinue
    
    Write-Host "* Syncthing installed successfully!" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to download Syncthing: $($_.Exception.Message)"
    Write-Host "You can download manually from: https://syncthing.net/downloads/" -ForegroundColor Yellow
    exit 1
}

# Create config directory
Write-Host "Creating config directory..." -ForegroundColor Yellow
$configPath = "$InstallPath\config"
New-Item -Path $configPath -ItemType Directory -Force | Out-Null

# Create Start Menu shortcut
Write-Host "Creating Start Menu shortcut..." -ForegroundColor Yellow
$WshShell = New-Object -ComObject WScript.Shell
$StartMenu = [Environment]::GetFolderPath("CommonStartMenu")
$Shortcut = $WshShell.CreateShortcut("$StartMenu\Programs\Syncthing.lnk")
$Shortcut.TargetPath = $syncthingExe
$Shortcut.Arguments = "--home=`"$configPath`""
$Shortcut.WorkingDirectory = $InstallPath
$Shortcut.IconLocation = "$syncthingExe,0"
$Shortcut.Description = "Syncthing - File Synchronization"
$Shortcut.Save()

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "To start Syncthing:" -ForegroundColor Cyan
Write-Host "  1. Click Start Menu > Syncthing" -ForegroundColor White
Write-Host "     OR" -ForegroundColor Gray
Write-Host "  2. Run: $syncthingExe" -ForegroundColor White
Write-Host ""
Write-Host "Syncthing will:" -ForegroundColor Yellow
Write-Host "  * Start automatically and open http://localhost:8384" -ForegroundColor White
Write-Host "  * Create config in: $configPath" -ForegroundColor White
Write-Host "  * Show its device ID in the web interface" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run setup-release-folders.ps1 to create folder structure" -ForegroundColor White
Write-Host "  2. Follow SYNCTHING_SIMPLE_GUIDE.md for configuration" -ForegroundColor White