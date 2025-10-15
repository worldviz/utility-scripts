#!/usr/bin/env python3
"""
CARLA Client Station Doctor
Checks if a CARLA UE4 driving simulator client station is fully configured.
Similar to 'flutter doctor' - provides comprehensive system validation.
"""

import os
import sys
import subprocess
import winreg
import platform
from pathlib import Path
from typing import Tuple, List, Optional

# ANSI color codes for terminal output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def print_header():
    """Print the doctor header."""
    print(f"\n{Colors.CYAN}{'=' * 70}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.CYAN}CARLA Client Station Doctor{Colors.RESET}")
    print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")

def print_section(title: str):
    """Print a section header."""
    print(f"\n{Colors.BOLD}{Colors.BLUE}[{title}]{Colors.RESET}")

def print_check(name: str, status: bool, message: str = "", optional: bool = False):
    """Print a check result."""
    if status:
        icon = f"{Colors.GREEN}✓{Colors.RESET}"
        status_text = f"{Colors.GREEN}OK{Colors.RESET}"
    else:
        icon = f"{Colors.RED}✗{Colors.RESET}"
        status_text = f"{Colors.RED}MISSING{Colors.RESET}"
        if optional:
            icon = f"{Colors.YELLOW}!{Colors.RESET}"
            status_text = f"{Colors.YELLOW}OPTIONAL{Colors.RESET}"
    
    print(f"  {icon} {name}: {status_text}", end="")
    if message:
        print(f" - {message}")
    else:
        print()

def check_windows():
    """Verify running on Windows."""
    return platform.system() == "Windows"

def check_command_exists(command: str) -> bool:
    """Check if a command exists in PATH."""
    try:
        result = subprocess.run(
            [command, "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode == 0
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return False

def check_service_running(service_name: str) -> Tuple[bool, str]:
    """Check if a Windows service is running."""
    try:
        result = subprocess.run(
            ["sc", "query", service_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            if "RUNNING" in result.stdout:
                return True, "Running"
            else:
                return False, "Not running"
        else:
            return False, "Not installed"
    except (subprocess.SubprocessError, FileNotFoundError):
        return False, "Unable to check"

def check_registry_value(key_path: str, value_name: str, expected_value=None) -> Tuple[bool, Optional[str]]:
    """Check if a registry value exists and optionally matches expected value."""
    try:
        # Parse the key path
        if key_path.startswith("HKLM\\"):
            root_key = winreg.HKEY_LOCAL_MACHINE
            sub_key = key_path[5:]
        elif key_path.startswith("HKCU\\"):
            root_key = winreg.HKEY_CURRENT_USER
            sub_key = key_path[5:]
        else:
            return False, None
        
        # Open and query the registry key
        key = winreg.OpenKey(root_key, sub_key, 0, winreg.KEY_READ)
        value, _ = winreg.QueryValueEx(key, value_name)
        winreg.CloseKey(key)
        
        if expected_value is not None:
            return value == expected_value, str(value)
        return True, str(value)
    except (OSError, FileNotFoundError):
        return False, None

def check_python_version(version: str) -> Tuple[bool, str]:
    """Check if a specific Python version is installed."""
    python_cmd = f"py -{version}"
    try:
        result = subprocess.run(
            [python_cmd, "--version"],
            capture_output=True,
            text=True,
            timeout=5,
            shell=True
        )
        if result.returncode == 0:
            installed_version = result.stdout.strip()
            return True, installed_version
        else:
            return False, "Not found"
    except (subprocess.SubprocessError, FileNotFoundError):
        return False, "Not found"

def check_path_exists(path: str) -> bool:
    """Check if a path exists."""
    return Path(path).exists()

def check_file_exists(path: str) -> bool:
    """Check if a file exists."""
    p = Path(path)
    return p.exists() and p.is_file()

def check_directory_exists(path: str) -> bool:
    """Check if a directory exists."""
    p = Path(path)
    return p.exists() and p.is_dir()

def check_env_variable(var_name: str, expected_value: str = None) -> Tuple[bool, Optional[str]]:
    """Check if an environment variable exists and optionally matches expected value."""
    value = os.environ.get(var_name)
    if value is None:
        return False, None
    if expected_value is not None:
        return value.lower() == expected_value.lower(), value
    return True, value

def check_startup_shortcut(shortcut_name: str) -> Tuple[bool, str]:
    """Check if a startup shortcut exists."""
    startup_path = Path(os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"))
    shortcut_path = startup_path / f"{shortcut_name}.lnk"
    
    if shortcut_path.exists():
        return True, str(shortcut_path)
    return False, "Not found"

def run_diagnostics():
    """Run all diagnostic checks."""
    print_header()
    
    issues = []
    optional_issues = []
    
    # Platform check
    if not check_windows():
        print(f"{Colors.RED}Error: This script must be run on Windows.{Colors.RESET}")
        return 1
    
    # Developer Mode & System Settings
    print_section("Developer Mode & System Settings")
    
    dev_mode, _ = check_registry_value(
        r"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock",
        "AllowDevelopmentWithoutDevLicense",
        1
    )
    print_check("Developer Mode", dev_mode)
    if not dev_mode:
        issues.append("Developer Mode not enabled - Run install-devmode.ps1")
    
    long_paths, _ = check_registry_value(
        r"HKLM\SYSTEM\CurrentControlSet\Control\FileSystem",
        "LongPathsEnabled",
        1
    )
    print_check("Long Paths Support", long_paths)
    if not long_paths:
        issues.append("Long Paths not enabled - Run install-devmode.ps1")
    
    # Development Tools
    print_section("Development Tools")
    
    git_installed = check_command_exists("git")
    print_check("Git", git_installed)
    if not git_installed:
        issues.append("Git not installed - Run install-vscode-git.ps1")
    
    git_lfs_installed = check_command_exists("git-lfs")
    print_check("Git LFS", git_lfs_installed)
    if not git_lfs_installed:
        issues.append("Git LFS not installed - Run install-vscode-git.ps1")
    
    vscode_installed = check_command_exists("code")
    print_check("Visual Studio Code", vscode_installed)
    if not vscode_installed:
        issues.append("VS Code not installed - Run install-vscode-git.ps1")
    
    # Python Installations
    print_section("Python Installations")
    
    py37_installed, py37_version = check_python_version("3.7")
    print_check("Python 3.7", py37_installed, py37_version if py37_installed else "")
    if not py37_installed:
        issues.append("Python 3.7 not installed - Install from python.org")
    
    py310_installed, py310_version = check_python_version("3.10")
    print_check("Python 3.10", py310_installed, py310_version if py310_installed else "")
    if not py310_installed:
        issues.append("Python 3.10 not installed - Install from python.org")
    
    # Syncthing
    print_section("Syncthing")
    
    syncthing_exe = check_file_exists(r"C:\wvlab\syncthing\syncthing.exe")
    print_check("Syncthing installed", syncthing_exe, r"C:\wvlab\syncthing\syncthing.exe")
    if not syncthing_exe:
        issues.append("Syncthing not installed - Run install-syncthing.ps1")
    
    syncthing_startup, startup_path = check_startup_shortcut("Syncthing")
    print_check("Syncthing startup shortcut", syncthing_startup, startup_path if syncthing_startup else "")
    if not syncthing_startup:
        issues.append("Syncthing startup shortcut missing - Run install-syncthing.ps1")
    
    # SSH & WSL (Optional)
    print_section("SSH & WSL (Optional)")
    
    ssh_running, ssh_status = check_service_running("sshd")
    print_check("OpenSSH Server", ssh_running, ssh_status, optional=not ssh_running)
    if not ssh_running:
        optional_issues.append("OpenSSH Server not running - Run install-ssh-wsl.ps1 (optional)")
    
    wsl_installed = check_command_exists("wsl")
    print_check("WSL", wsl_installed, optional=not wsl_installed)
    if not wsl_installed:
        optional_issues.append("WSL not installed - Run install-ssh-wsl.ps1 (optional)")
    
    # CARLA Lab Folders
    print_section("CARLA Lab Folders")
    
    folders_to_check = [
        (r"C:\wvlab", "WVLab root"),
        (r"C:\wvlab\runtime", "Runtime folder"),
        (r"C:\wvlab\runtime\carla", "CARLA folder"),
        (r"C:\wvlab\runtime\carla-backup", "CARLA backup folder"),
    ]
    
    for folder_path, folder_name in folders_to_check:
        exists = check_directory_exists(folder_path)
        print_check(folder_name, exists, folder_path)
        if not exists:
            issues.append(f"{folder_name} missing - Run install-wvlab-folders.ps1")
    
    # CARLA Configuration
    print_section("CARLA Configuration")
    
    stignore_exists = check_file_exists(r"C:\wvlab\runtime\carla\.stignore")
    print_check(".stignore file", stignore_exists, r"C:\wvlab\runtime\carla\.stignore")
    if not stignore_exists:
        issues.append(".stignore file missing in C:\\wvlab\\runtime\\carla")
    
    carla_root_set, carla_root_value = check_env_variable("CARLA_ROOT", r"c:\wvlab\runtime\carla\carla")
    expected_carla_root = r"c:\wvlab\runtime\carla\carla"
    print_check(
        "CARLA_ROOT env variable",
        carla_root_set,
        f"Set to: {carla_root_value}" if carla_root_value else f"Should be: {expected_carla_root}"
    )
    if not carla_root_set:
        issues.append(f"CARLA_ROOT not set correctly - Should be: {expected_carla_root}")
    
    # Virtual Environments
    print_section("Virtual Environments")
    
    venv_carla_exists = check_directory_exists(r"C:\wvlab\venv-carla")
    print_check("venv-carla", venv_carla_exists, r"C:\wvlab\venv-carla")
    if not venv_carla_exists:
        issues.append(r"venv-carla missing - Run: c:\wvlab\carla\source\SCSU\setup_external_venv.ps1")
    
    venv_orchestrator_exists = check_directory_exists(r"C:\wvlab\venv-orchestrator")
    print_check("venv-orchestrator", venv_orchestrator_exists, r"C:\wvlab\venv-orchestrator")
    if not venv_orchestrator_exists:
        issues.append(r"venv-orchestrator missing - Run: c:\wvlab\carla\source\SCSU\setup_external_venv.ps1")
    
    # Startup Shortcuts
    print_section("Startup Configuration")
    
    agent_startup, agent_path = check_startup_shortcut("run_agent")
    print_check("run_agent startup shortcut", agent_startup, agent_path if agent_startup else "")
    if not agent_startup:
        issues.append("run_agent startup shortcut missing")
    
    # Summary
    print(f"\n{Colors.CYAN}{'=' * 70}{Colors.RESET}")
    print(f"{Colors.BOLD}Summary{Colors.RESET}")
    print(f"{Colors.CYAN}{'=' * 70}{Colors.RESET}\n")
    
    if not issues and not optional_issues:
        print(f"{Colors.GREEN}{Colors.BOLD}✓ All checks passed! Your CARLA client station is fully configured.{Colors.RESET}\n")
        return 0
    
    if issues:
        print(f"{Colors.RED}{Colors.BOLD}✗ {len(issues)} issue(s) found:{Colors.RESET}\n")
        for i, issue in enumerate(issues, 1):
            print(f"  {i}. {issue}")
        print()
    
    if optional_issues:
        print(f"{Colors.YELLOW}{Colors.BOLD}! {len(optional_issues)} optional item(s):{Colors.RESET}\n")
        for i, issue in enumerate(optional_issues, 1):
            print(f"  {i}. {issue}")
        print()
    
    return 1 if issues else 0

if __name__ == "__main__":
    try:
        sys.exit(run_diagnostics())
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Diagnostic interrupted.{Colors.RESET}")
        sys.exit(130)
    except Exception as e:
        print(f"\n{Colors.RED}Error running diagnostics: {e}{Colors.RESET}")
        sys.exit(1)
