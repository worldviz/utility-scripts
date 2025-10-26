# Setup CARLA Lab Folders
# Creates the folder structure for direct CARLA sync

Write-Host "Setting up CARLA Lab folders..." -ForegroundColor Green
Write-Host ""

# Define folder structure (simplified!)
$folders = @(
    "C:\wvlab",
    "C:\wvlab\carla"
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