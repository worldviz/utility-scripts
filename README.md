# Utility Scripts

PowerShell installation scripts for Windows development environment setup. Run remotely via:

```powershell
iwr -useb util.worldviz.com/install-vscode-git.ps1 | iex
```

## Scripts

- **install-devmode.ps1** - Enables Windows Developer Mode and long paths support
- **install-ssh-wsl.ps1** - Installs OpenSSH Server and WSL Ubuntu 22.04
- **install-syncthing.ps1** - Downloads and installs Syncthing file synchronization tool
- **install-vscode-git.ps1** - Installs VS Code, Git, Git LFS, and Python extension
- **install-wlab-folders.ps1** - Creates CARLA Lab folder structure for runtime synchronization

All scripts require Administrator privileges.
