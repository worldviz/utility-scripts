# Setup CARLA Lab Folders
# Creates the folder structure for direct CARLA sync

Write-Host "Setting up CARLA Lab folders..." -ForegroundColor Green
Write-Host ""

# Define folder structure (simplified!)
$folders = @(
    "C:\wvlab",
    "C:\wvlab\runtime",
    "C:\wvlab\runtime\carla",
    "C:\wvlab\runtime\carla-backup"
)

# Create each folder
foreach ($folder in $folders) {
    if (Test-Path $folder) {
        Write-Host "* $folder already exists" -ForegroundColor Gray
    } else {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Write-Host "* Created $folder" -ForegroundColor Green
    }
}

# Create a README
$readmeContent = @"
# CARLA Lab Runtime Folder

This folder contains the active CARLA installation that syncs across all lab nodes.

## How It Works

**Controller**: Manages the master CARLA installation in C:\lab\runtime\carla
**Nodes**: Automatically sync to match the controller's installation
**Deployment**: Just update CARLA on controller, all nodes follow automatically

## Deploying Updates

1. **Backup current** (on controller):
   ``````
   xcopy /E /I "C:\lab\runtime\carla" "C:\lab\runtime\carla-backup"
   ``````

2. **Deploy new version** (on controller):
   ``````
   xcopy /E /I "D:\CARLA_Build_v0.9.15" "C:\lab\runtime\carla"
   ``````

3. **Automatic sync**: Syncthing distributes to all nodes

## Benefits

 **Simple**: One folder, direct sync
 **Automatic**: Nodes always match controller  
 **Fast**: No intermediate copying steps
 **Reliable**: Standard Syncthing folder sync
"@

$readmeContent | Out-File "C:\lab\runtime\README.md" -Encoding UTF8
Write-Host "* Created README.md" -ForegroundColor Green

Write-Host ""
Write-Host "=== Folder Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Created folders:" -ForegroundColor Cyan
foreach ($folder in $folders) {
    Write-Host "  * $folder" -ForegroundColor White
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Install Syncthing using install-syncthing-simple.ps1" -ForegroundColor White
Write-Host "  2. Configure Syncthing to sync C:\lab\runtime\carla" -ForegroundColor White
Write-Host "  3. Place CARLA build in carla\ folder on controller" -ForegroundColor White
Write-Host ""
Write-Host "For detailed instructions, see SYNCTHING_SIMPLE_GUIDE.md" -ForegroundColor Cyan