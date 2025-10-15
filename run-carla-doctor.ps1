#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads and runs the CARLA Doctor diagnostic script.

.DESCRIPTION
    This script downloads carla-doctor.py from the utility scripts server
    and executes it using Python. Can be run with:
    iwr -useb util.worldviz.com/run-carla-doctor.ps1 | iex

.EXAMPLE
    iwr -useb util.worldviz.com/run-carla-doctor.ps1 | iex
    
.EXAMPLE
    .\run-carla-doctor.ps1
#>

$ErrorActionPreference = "Stop"

# URL to the carla-doctor.py script
$scriptUrl = "http://util.worldviz.com/carla-doctor.py"

Write-Host "CARLA Doctor - Diagnostic Tool" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# Check if Python is available
$pythonCmd = $null
$pythonCommands = @("python", "python3", "py")

foreach ($cmd in $pythonCommands) {
    try {
        $null = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pythonCmd = $cmd
            break
        }
    }
    catch {
        continue
    }
}

if (-not $pythonCmd) {
    Write-Host "ERROR: Python is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Python from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Python: $pythonCmd" -ForegroundColor Green

# Create a temporary file for the script
$tempFile = [System.IO.Path]::GetTempFileName()
$tempPyFile = [System.IO.Path]::ChangeExtension($tempFile, ".py")
Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

try {
    Write-Host "Downloading carla-doctor.py..." -ForegroundColor Cyan
    
    # Download the Python script
    Invoke-WebRequest -Uri $scriptUrl -OutFile $tempPyFile -UseBasicParsing
    
    Write-Host "Running diagnostics..." -ForegroundColor Cyan
    Write-Host ""
    
    # Run the Python script
    & $pythonCmd $tempPyFile
    
    $exitCode = $LASTEXITCODE
    
    # Clean up
    Remove-Item $tempPyFile -Force -ErrorAction SilentlyContinue
    
    exit $exitCode
}
catch {
    Write-Host ""
    Write-Host "ERROR: Failed to download or run carla-doctor.py" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    # Clean up
    if (Test-Path $tempPyFile) {
        Remove-Item $tempPyFile -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
