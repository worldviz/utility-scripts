# Utility Scripts

PowerShell installation scripts for Windows development environment setup. Run remotely via:

```powershell
iwr -useb util.worldviz.com/install-vscode-git.ps1 | iex
```

## Scripts

- **install-prism-support.ps1** - WorldViz remote support setup for PRISM machines: rig-LAN network guard, Tailscale (tagged/unattended), OpenSSH scoped to the tailnet, optional customer on/off switch. Interactive; needs a site name + auth key from WorldViz.
- **prism-support-status.ps1** - Read-only health readout of the support tunnel and network ("run this and read me the screen"). No admin needed.
- **install-devmode.ps1** - Enables Windows Developer Mode and long paths support
- **install-ssh-wsl.ps1** - Installs OpenSSH Server and WSL Ubuntu 22.04
- **install-syncthing.ps1** - Downloads and installs Syncthing file synchronization tool
- **install-vscode-git.ps1** - Installs VS Code, Git, Git LFS, and Python extension
- **install-wlab-folders.ps1** - Creates CARLA Lab folder structure for runtime synchronization

All scripts require Administrator privileges.
