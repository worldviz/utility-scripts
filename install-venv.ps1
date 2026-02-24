# PowerShell script to create and manage external venv
# Reusable script that can be called from anywhere
#
# Usage Examples:
#   .\install-venv_venv.ps1 -PythonVersion "3.7" -VenvPath "C:\wvlab\venv-carla" -RequirementsFile ".\requirements.txt"
#   .\install-venv_venv.ps1 -PythonVersion "3.10" -VenvPath "C:\wvlab\venv-test" -Recreate
#   .\install-venv_venv.ps1  # Uses defaults

param(
    [Parameter(Mandatory=$false)]
    [string]$PythonVersion = "3.7",
    
    [Parameter(Mandatory=$false)]
    [string]$VenvPath = "C:\wvlab\venv-carla",
    
    [Parameter(Mandatory=$false)]
    [string]$RequirementsFile = "",
    
    [switch]$Recreate = $false
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "External venv Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Python Version: $PythonVersion" -ForegroundColor Gray
Write-Host "  venv Path: $VenvPath" -ForegroundColor Gray
if ($RequirementsFile) {
    Write-Host "  Requirements: $RequirementsFile" -ForegroundColor Gray
} else {
    Write-Host "  Requirements: None specified" -ForegroundColor Gray
}
Write-Host ""

# Ensure the parent directory exists
$VenvParent = Split-Path -Parent $VenvPath
if (-not (Test-Path $VenvParent)) {
    Write-Host "Creating venv parent directory: $VenvParent" -ForegroundColor Green
    New-Item -ItemType Directory -Path $VenvParent -Force | Out-Null
}

# Check if venv already exists
$CreateVenv = $true
if (Test-Path $VenvPath) {
    if ($Recreate) {
        Write-Host "Removing existing venv at: $VenvPath" -ForegroundColor Yellow
        Remove-Item -Path $VenvPath -Recurse -Force
    } else {
        Write-Host "venv already exists at: $VenvPath" -ForegroundColor Green
        Write-Host "To recreate, run with -Recreate flag" -ForegroundColor Yellow
        $CreateVenv = $false
    }
}

if ($CreateVenv) {

# Verify specified Python version is available via py launcher
Write-Host "Checking for Python $PythonVersion via py launcher..." -ForegroundColor Cyan
try {
    $PyVersion = py -$PythonVersion --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Found Python $PythonVersion`: $PyVersion" -ForegroundColor Green
    } else {
        throw "Python $PythonVersion not available"
    }
} catch {
    Write-Host "ERROR: Python $PythonVersion not found!" -ForegroundColor Red
    Write-Host "Please install Python $PythonVersion and ensure 'py -$PythonVersion' works from the command line" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available Python versions:" -ForegroundColor Yellow
    py --list 2>&1 | Write-Host
    exit 1
}

# Create the venv using specified Python version
Write-Host "Creating new venv at: $VenvPath" -ForegroundColor Green
py -$PythonVersion -m venv $VenvPath

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create venv!" -ForegroundColor Red
    exit 1
}

Write-Host "venv created successfully!" -ForegroundColor Green
Write-Host ""

} # End if ($CreateVenv)

# Activate the venv
Write-Host "Activating venv..." -ForegroundColor Cyan
& "$VenvPath\Scripts\Activate.ps1"

# Upgrade pip
Write-Host ""
Write-Host "Upgrading pip..." -ForegroundColor Cyan
python -m pip install --upgrade pip

# Install requirements if specified
if ($RequirementsFile) {
    # Convert to absolute path if relative
    if (-not [System.IO.Path]::IsPathRooted($RequirementsFile)) {
        $RequirementsFile = Join-Path (Get-Location) $RequirementsFile
    }
    
    if (Test-Path $RequirementsFile) {
        Write-Host ""
        Write-Host "Installing requirements from: $RequirementsFile" -ForegroundColor Cyan
        pip install -r $RequirementsFile
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Some packages may have failed to install" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "WARNING: Requirements file not found: $RequirementsFile" -ForegroundColor Yellow
        Write-Host "Skipping requirements installation" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "No requirements file specified, skipping package installation" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "venv Location: $VenvPath" -ForegroundColor Yellow
Write-Host "Python Version:" -ForegroundColor Yellow
python --version
Write-Host ""
Write-Host "To activate this venv manually, run:" -ForegroundColor Cyan
Write-Host "  $VenvPath\Scripts\Activate.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Or in batch file:" -ForegroundColor Cyan
Write-Host "  call $VenvPath\Scripts\activate.bat" -ForegroundColor White
Write-Host ""

# # Create a reference file in the project root
# $RefFile = "$ProjectRoot\.venv-location"
# $VenvPath | Out-File -FilePath $RefFile -Encoding utf8
# Write-Host "Created reference file: .venv-location" -ForegroundColor Green
# Write-Host "(This file tells scripts where to find the venv)" -ForegroundColor Gray
