<# 
  install-vscode-git.ps1
  Run as: PowerShell (Admin)
  Purpose: Install Visual Studio Code and Git on Windows
#>

# Check for Administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

function Test-CommandExists($Command) {
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Install-Package($PackageId) {
    Write-Host "Installing $PackageId..." -ForegroundColor Yellow
    
    # Check if already installed
    $installed = winget list --id $PackageId 2>$null | Select-String $PackageId
    if ($installed) {
        Write-Host "$PackageId already installed." -ForegroundColor Gray
        return $true
    }
    
    # Install package
    $result = winget install --id $PackageId -e --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$PackageId installed successfully." -ForegroundColor Green
        return $true
    } else {
        Write-Warning "$PackageId installation failed. You may need to install it manually."
        return $false
    }
}

Clear-Host
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Installing Visual Studio Code and Git" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Check winget availability
if (-not (Test-CommandExists "winget")) {
    Write-Error "winget not found. Please install App Installer from Microsoft Store."
    exit 1
}

# Install Git
$gitInstalled = Install-Package "Git.Git"

# Install Git LFS
$gitLfsInstalled = Install-Package "GitHub.GitLFS"

# Configure Git LFS if both Git and Git LFS installed successfully
if ($gitInstalled -and $gitLfsInstalled) {
    Write-Host ""
    Write-Host "Configuring Git LFS..." -ForegroundColor Yellow
    & git lfs install 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Git LFS configured successfully." -ForegroundColor Green
    }
}

# Install Visual Studio Code
$vscodeInstalled = Install-Package "Microsoft.VisualStudioCode"

# Configure PowerShell execution policy for Python venv activation
Write-Host ""
Write-Host "Configuring PowerShell execution policy for Python virtual environments..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host "Execution policy set to RemoteSigned for CurrentUser." -ForegroundColor Green
    Write-Host "(This allows Python venv activation scripts to run in VS Code)" -ForegroundColor Gray
} catch {
    Write-Warning "Failed to set execution policy. You may need to run this manually:"
    Write-Host "  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" -ForegroundColor Yellow
}

# Install Python extension for VS Code
if ($vscodeInstalled) {
    Write-Host ""
    Write-Host "Installing Python extension for VS Code..." -ForegroundColor Yellow
    
    # Wait a moment for VS Code to be fully available
    Start-Sleep -Seconds 2
    
    # Try to install the Python extension
    $codeCommand = Get-Command code -ErrorAction SilentlyContinue
    if ($codeCommand) {
        try {
            & code --install-extension ms-python.python --force 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Python extension installed successfully." -ForegroundColor Green
            } else {
                Write-Warning "Python extension installation may have failed."
                Write-Host "You can install it manually in VS Code by searching for 'Python' in the Extensions view." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Could not install Python extension automatically."
            Write-Host "You can install it manually in VS Code by searching for 'Python' in the Extensions view." -ForegroundColor Yellow
        }
    } else {
        Write-Host "VS Code 'code' command not yet available in PATH." -ForegroundColor Yellow
        Write-Host "After restarting your terminal, you can install the Python extension with:" -ForegroundColor Cyan
        Write-Host "  code --install-extension ms-python.python" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""

# Verify installations
Write-Host "Verification:" -ForegroundColor Cyan
$checks = @(
    @{Name="Git"; Command="git"},
    @{Name="Git LFS"; Command="git-lfs"},
    @{Name="VS Code"; Command="code"}
)

foreach ($check in $checks) {
    Write-Host -NoNewline "  $($check.Name): "
    if (Test-CommandExists $check.Command) {
        Write-Host "[OK] Installed" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found in PATH (may require restart)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Note: You may need to restart your terminal or computer for PATH updates to take effect." -ForegroundColor Yellow
Write-Host ""
