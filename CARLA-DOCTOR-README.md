# CARLA Client Station Doctor

A comprehensive diagnostic tool for validating CARLA UE4 driving simulator client station configurations, inspired by `flutter doctor`.

## Features

✓ Comprehensive system validation with color-coded output  
✓ Checks all installation scripts: devmode, VS Code, Git, Syncthing, SSH/WSL, folders  
✓ Validates Python 3.7 and 3.10 installations  
✓ Verifies CARLA folder structure and configuration  
✓ Checks environment variables and virtual environments  
✓ Validates startup shortcuts  
✓ Clear actionable recommendations for fixing issues

## Usage

### Run the Doctor

```bash
python carla-doctor.py
```

Or on Windows:

```bash
py carla-doctor.py
```

### Example Output

```
======================================================================
CARLA Client Station Doctor
======================================================================

[Developer Mode & System Settings]
  ✓ Developer Mode: OK
  ✓ Long Paths Support: OK

[Development Tools]
  ✓ Git: OK
  ✓ Git LFS: OK
  ✓ Visual Studio Code: OK

[Python Installations]
  ✓ Python 3.7: OK - Python 3.7.9
  ✓ Python 3.10: OK - Python 3.10.11

[Syncthing]
  ✓ Syncthing installed: OK - C:\wvlab\syncthing\syncthing.exe
  ✓ Syncthing startup shortcut: OK

[SSH & WSL (Optional)]
  ! OpenSSH Server: OPTIONAL - Not running
  ! WSL: OPTIONAL

[CARLA Lab Folders]
  ✓ WVLab root: OK - C:\wvlab
  ✓ Runtime folder: OK - C:\wvlab\runtime
  ✓ CARLA folder: OK - C:\wvlab\runtime\carla
  ✓ CARLA backup folder: OK - C:\wvlab\runtime\carla-backup

[CARLA Configuration]
  ✓ .stignore file: OK - C:\wvlab\runtime\carla\.stignore
  ✓ CARLA_ROOT env variable: OK - Set to: c:\wvlab\runtime\carla\carla

[Virtual Environments]
  ✓ venv-carla: OK - C:\wvlab\venv-carla
  ✓ venv-orchestrator: OK - C:\wvlab\venv-orchestrator

[Startup Configuration]
  ✓ run_agent startup shortcut: OK

======================================================================
Summary
======================================================================

✓ All checks passed! Your CARLA client station is fully configured.
```

## What It Checks

### 1. Developer Mode & System Settings
- **Developer Mode**: Enabled via registry
- **Long Paths Support**: Enabled via registry
- **Fix**: Run `install-devmode.ps1`

### 2. Development Tools
- **Git**: Command available in PATH
- **Git LFS**: Command available in PATH
- **Visual Studio Code**: Command available in PATH
- **Fix**: Run `install-vscode-git.ps1`

### 3. Python Installations
- **Python 3.7**: Installed and accessible via `py -3.7`
- **Python 3.10**: Installed and accessible via `py -3.10`
- **Fix**: Download from [python.org](https://www.python.org/downloads/)

### 4. Syncthing
- **Syncthing executable**: Exists at `C:\wvlab\syncthing\syncthing.exe`
- **Startup shortcut**: Exists in Startup folder
- **Fix**: Run `install-syncthing.ps1`

### 5. SSH & WSL (Optional)
- **OpenSSH Server**: Service installed and running
- **WSL**: Command available in PATH
- **Fix**: Run `install-ssh-wsl.ps1` (optional feature)

### 6. CARLA Lab Folders
- `C:\wvlab` - Root directory
- `C:\wvlab\runtime` - Runtime folder
- `C:\wvlab\runtime\carla` - CARLA installation folder
- `C:\wvlab\runtime\carla-backup` - Backup folder
- **Fix**: Run `install-wvlab-folders.ps1`

### 7. CARLA Configuration
- **.stignore file**: Exists in `C:\wvlab\runtime\carla\.stignore`
- **CARLA_ROOT**: Environment variable set to `c:\wvlab\runtime\carla\carla`
- **Fix**: Create `.stignore` file and set environment variable

### 8. Virtual Environments
- **venv-carla**: Exists at `C:\wvlab\venv-carla`
- **venv-orchestrator**: Exists at `C:\wvlab\venv-orchestrator`
- **Fix**: Run `c:\wvlab\carla\source\SCSU\setup_external_venv.ps1`
  - Example: `setup_external_venv.ps1 -PythonVersion "3.7" -VenvPath "c:\wvlab\venv-carla" -RequirementsFile .\requirements.txt`

### 9. Startup Configuration
- **run_agent**: Shortcut exists in Startup folder
- **Syncthing**: Shortcut exists in Startup folder
- **Fix**: Create shortcuts manually or re-run installation scripts

## Exit Codes

- **0**: All required checks passed
- **1**: One or more required checks failed
- **130**: Diagnostic interrupted (Ctrl+C)

## Color Legend

- 🟢 **Green (✓)**: Check passed - everything is configured correctly
- 🔴 **Red (✗)**: Check failed - required configuration is missing
- 🟡 **Yellow (!)**: Optional - feature not configured but not required

## Requirements

- **Windows OS**: This script only runs on Windows
- **Python 3.x**: Any Python 3.x version to run the script

## Troubleshooting

### Script won't run
```bash
# Make sure Python is installed
py --version

# Run with full path
py C:\path\to\carla-doctor.py
```

### False negatives
Some checks may fail if:
- You need to restart your terminal after installations
- Environment variables haven't been refreshed
- Services haven't been started after installation

**Solution**: Restart your terminal or computer and run again.

### Permission errors
Some registry checks require appropriate permissions. Run PowerShell as Administrator if you encounter access denied errors.

## Integration

You can integrate this into your workflow:

### Pre-deployment Check
```bash
py carla-doctor.py
if %ERRORLEVEL% NEQ 0 (
    echo Fix issues before deploying
    exit /b 1
)
```

### Automated Setup Validation
Run after your setup scripts complete to verify everything is configured correctly.

## Related Scripts

- `install-devmode.ps1` - Enable Developer Mode and Long Paths
- `install-vscode-git.ps1` - Install VS Code and Git
- `install-syncthing.ps1` - Install Syncthing
- `install-ssh-wsl.ps1` - Install SSH and WSL (optional)
- `install-wvlab-folders.ps1` - Create CARLA folder structure

## License

Same as parent repository.
