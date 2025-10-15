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
import json
import re
import urllib.request
import urllib.error
from pathlib import Path
from typing import Tuple, List, Optional, Dict, Any

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

def check_vscode_installed() -> Tuple[bool, str]:
    """Check if VS Code is installed on Windows."""
    # Method 1: Check if 'code' command is in PATH
    try:
        result = subprocess.run(
            ["code", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            version = result.stdout.split('\n')[0].strip()
            return True, f"Found in PATH (v{version})"
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        pass
    
    # Method 2: Check common installation paths
    common_paths = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Microsoft VS Code" / "Code.exe",
        Path(os.environ.get("PROGRAMFILES", "")) / "Microsoft VS Code" / "Code.exe",
        Path(os.environ.get("PROGRAMFILES(X86)", "")) / "Microsoft VS Code" / "Code.exe",
    ]
    
    for vscode_path in common_paths:
        if vscode_path.exists():
            return True, f"Found at {vscode_path}"
    
    # Method 3: Check registry for uninstall information
    registry_keys = [
        r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    ]
    
    for registry_key in registry_keys:
        try:
            key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, registry_key)
            for i in range(winreg.QueryInfoKey(key)[0]):
                try:
                    subkey_name = winreg.EnumKey(key, i)
                    subkey = winreg.OpenKey(key, subkey_name)
                    try:
                        name, _ = winreg.QueryValueEx(subkey, "DisplayName")
                        if "Visual Studio Code" in name:
                            winreg.CloseKey(subkey)
                            winreg.CloseKey(key)
                            return True, f"Foundx in registry: {name}"
                    except OSError:
                        pass
                    winreg.CloseKey(subkey)
                except OSError:
                    continue
            winreg.CloseKey(key)
        except OSError:
            continue
    
    return False, "Not found"

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
    """Check if a specific Python version is installed using py launcher."""
    try:
        # Use py launcher with separate arguments
        result = subprocess.run(
            ["py", f"-{version}", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Get version from stdout
            installed_version = result.stdout.strip()
            return True, installed_version
        else:
            return False, "Not found"
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
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

def get_syncthing_config() -> Tuple[bool, Optional[Dict[str, Any]]]:
    """Get Syncthing configuration via REST API."""
    # Try multiple possible config locations
    config_paths = [
        # Portable mode (in syncthing/config directory)
        Path(r"C:\wvlab\syncthing\config\config.xml"),
        # Portable mode (in syncthing directory)
        Path(r"C:\wvlab\syncthing\config.xml"),
        # Standard installation
        Path(os.path.expandvars(r"%LOCALAPPDATA%\Syncthing\config.xml")),
    ]
    
    api_key = None
    
    for config_path in config_paths:
        if config_path.exists():
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    # Simple extraction of API key from XML
                    match = re.search(r'<apikey>(.*?)</apikey>', content)
                    if match:
                        api_key = match.group(1)
                        break
            except Exception:
                continue
    
    if not api_key:
        return False, None
    
    # Query Syncthing REST API
    try:
        url = "http://127.0.0.1:8384/rest/config"
        req = urllib.request.Request(url)
        req.add_header('X-API-Key', api_key)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            config = json.loads(response.read().decode('utf-8'))
            return True, config
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, Exception):
        return False, None

def check_syncthing_folder_defaults(config: Optional[Dict[str, Any]]) -> Tuple[bool, str]:
    """Check if Syncthing folder defaults are configured correctly."""
    if not config:
        return False, "Cannot check - Syncthing not accessible"
    
    defaults = config.get('defaults', {}).get('folder', {})
    path = defaults.get('path', '')
    folder_type = defaults.get('type', '')
    
    issues = []
    if path.lower() != r"c:\wvlab":
        issues.append(f"Path is '{path}' (should be c:\\wvlab)")
    if folder_type.lower() != "receiveonly":
        issues.append(f"Type is '{folder_type}' (should be receiveonly)")
    
    if issues:
        return False, "; ".join(issues)
    return True, "Path: c:\\wvlab, Type: receiveonly"

def check_syncthing_device_auto_accept(config: Optional[Dict[str, Any]]) -> Tuple[bool, str]:
    """Check if any device has auto-accept enabled."""
    if not config:
        return False, "Cannot check - Syncthing not accessible"
    
    devices = config.get('devices', [])
    auto_accept_devices = []
    
    for device in devices:
        if device.get('autoAcceptFolders', False):
            device_name = device.get('name', device.get('deviceID', 'Unknown'))
            auto_accept_devices.append(device_name)
    
    if auto_accept_devices:
        return True, f"Enabled for: {', '.join(auto_accept_devices)}"
    else:
        return False, "No devices with auto-accept enabled"

def run_diagnostics():
    """Run all diagnostic checks."""
    print_header()
    
    issues = []
    optional_issues = []
    
    # Platform check
    if not check_windows():
        print(f"{Colors.RED}Error: This script must be run on Windows.{Colors.RESET}")
        return 1
    
    # Development Tools & System Settings
    print_section("Development Tools & System Settings")
    
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
    
    git_installed = check_command_exists("git")
    print_check("Git", git_installed)
    if not git_installed:
        issues.append("Git not installed - Run install-vscode-git.ps1")
    
    git_lfs_installed = check_command_exists("git-lfs")
    print_check("Git LFS", git_lfs_installed)
    if not git_lfs_installed:
        issues.append("Git LFS not installed - Run install-vscode-git.ps1")
    
    vscode_installed, vscode_info = check_vscode_installed()
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
    
    # Admin Tools
    print_section("Admin Tools")
    
    stignore_exists = check_file_exists(r"C:\wvlab\carla\.stignore")
    print_check(".stignore file", stignore_exists, r"C:\wvlab\carla\.stignore")
    if not stignore_exists:
        issues.append(".stignore file missing in C:\\wvlab\\carla")
    
    syncthing_exe = check_file_exists(r"C:\wvlab\syncthing\syncthing.exe")
    print_check("Syncthing installed", syncthing_exe, r"C:\wvlab\syncthing\syncthing.exe")
    if not syncthing_exe:
        issues.append("Syncthing not installed - Run install-syncthing.ps1")
    
    # Check Syncthing configuration via REST API
    syncthing_config_available, syncthing_config = get_syncthing_config()
    
    if syncthing_config_available:
        # Check folder defaults
        folder_defaults_ok, folder_defaults_msg = check_syncthing_folder_defaults(syncthing_config)
        print_check("Syncthing folder defaults", folder_defaults_ok, folder_defaults_msg)
        if not folder_defaults_ok:
            issues.append(f"Syncthing folder defaults incorrect - {folder_defaults_msg}")
        
        # Check device auto-accept
        auto_accept_ok, auto_accept_msg = check_syncthing_device_auto_accept(syncthing_config)
        print_check("Syncthing device auto-accept", auto_accept_ok, auto_accept_msg)
        if not auto_accept_ok:
            issues.append(f"Syncthing device auto-accept not configured - {auto_accept_msg}")
    else:
        print_check("Syncthing configuration", False, "Cannot access Syncthing API (is it running?)")
        issues.append("Syncthing configuration cannot be verified - Ensure Syncthing is running")
    
    ssh_running, ssh_status = check_service_running("sshd")
    print_check("OpenSSH Server", ssh_running, ssh_status, optional=not ssh_running)
    if not ssh_running:
        optional_issues.append("OpenSSH Server not running - Run install-ssh-wsl.ps1 (optional)")
    
    wsl_installed = check_command_exists("wsl")
    print_check("WSL", wsl_installed, optional=not wsl_installed)
    if not wsl_installed:
        optional_issues.append("WSL not installed - Run install-ssh-wsl.ps1 (optional)")
    
    # CARLA Lab Folders & Configuration
    print_section("CARLA Lab Folders & Configuration")
    
    folders_to_check = [
        (r"C:\wvlab", "WVLab root"),
        (r"C:\wvlab\carla", "Runtime folder"),
    ]
    
    for folder_path, folder_name in folders_to_check:
        exists = check_directory_exists(folder_path)
        print_check(folder_name, exists, folder_path)
        if not exists:
            issues.append(f"{folder_name} missing - Run install-wvlab-folders.ps1")
    
    carla_root_set, carla_root_value = check_env_variable("CARLA_ROOT")
    expected_carla_root = r"c:\wvlab\carla\carla"
    carla_root_correct = carla_root_set and carla_root_value and carla_root_value.lower() == expected_carla_root.lower()
    
    if carla_root_correct:
        print_check("CARLA_ROOT env variable", True, f"Correctly set to: {carla_root_value}")
    elif carla_root_value:
        print_check("CARLA_ROOT env variable", False, f"Currently: {carla_root_value}, Should be: {expected_carla_root}")
        issues.append(f"CARLA_ROOT set incorrectly - Currently: {carla_root_value}, Should be: {expected_carla_root}")
    else:
        print_check("CARLA_ROOT env variable", False, f"Not set - Should be: {expected_carla_root}")
        issues.append(f"CARLA_ROOT not set - Should be: {expected_carla_root}")
    
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
    
    syncthing_startup, startup_path = check_startup_shortcut("Syncthing")
    print_check("Syncthing startup shortcut", syncthing_startup, startup_path if syncthing_startup else "")
    if not syncthing_startup:
        issues.append("Syncthing startup shortcut missing - Run install-syncthing.ps1")
    
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
