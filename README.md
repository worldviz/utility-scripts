# Utility Scripts

PowerShell installation scripts for Windows development environment setup. Run remotely via:

```powershell
iwr -useb util.worldviz.com/install-vscode-git.ps1 | iex
```

## Scripts

- **install-prism-support.ps1** - WorldViz remote support setup for PRISM machines: rig-LAN network guard, Tailscale (MSI, tagged/unattended join), OpenSSH scoped to the tailnet, WV support key, optional customer on/off switch. `-Prep` does everything except the join; `-Site`/`-AuthKey` (from WorldViz) joins. Fail-soft and safe to re-run.
- **prep-prism.ps1** - Short form of `install-prism-support.ps1 -Prep`: `iwr -useb util.worldviz.com/prep-prism.ps1 | iex`. No key, no questions.
- **join-prism.ps1** - Join without an auth key: `iwr -useb util.worldviz.com/join-prism.ps1 | iex`, type the site name, and the PC shows a login link for a WorldViz admin to approve. The PC requests its site tag, which only an admin can grant, so the link is not a secret.
- **prism-support-status.ps1** - Read-only health readout of the support tunnel and network ("run this and read me the screen"). No admin needed.
- **install-devmode.ps1** - Enables Windows Developer Mode and long paths support
- **install-ssh-wsl.ps1** - Installs OpenSSH Server and WSL Ubuntu 22.04
- **install-syncthing.ps1** - Downloads and installs Syncthing file synchronization tool
- **install-vscode-git.ps1** - Installs VS Code, Git, Git LFS, and Python extension
- **install-wlab-folders.ps1** - Creates CARLA Lab folder structure for runtime synchronization

All scripts require Administrator privileges.
