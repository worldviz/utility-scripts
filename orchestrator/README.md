# LAN Orchestrator

A lightweight server–client system to start, monitor, and stop external processes (like CARLA/Unreal)
on multiple Windows 11 PCs from a single controller.

- **Agent**: FastAPI app that runs on each client and launches/manages processes.
- **Controller**: Python CLI that sends start/stop/status to all clients concurrently.
- **Monitoring**: CPU%, memory, uptime, "possibly hung" detection (configurable).
- **Kill**: Reliable Windows process termination with escalation (terminate → kill → tree_kill) and confirmation.
- **Auth**: Simple bearer token.

> This is intentionally minimal and Python-only. It avoids heavier stacks (Salt/Ansible/Celery)
while giving you robust process control on Windows.

## Install (clients)

1) Be sure Python 3.10 is installed (check using `py -0p` in powershell); otherwise install with:
    `winget install Python.Python.3.10`
2) You can run this one-liner to setup the venv:
```
iwr -UseBasicParsing https://util.worldviz.com/install-venv.ps1 -OutFile "$env:TEMP\install-venv.ps1"; & "$env:TEMP\install-venv.ps1" -PythonVersion 3.10 -VenvPath 'C:\wvlab\venv-orchestrator' -RequirementsFile 'C:\wvlab\orchestrator\requirements.txt'
```

3) Download orchestrator folder:
   https://github.com/worldviz/utility-scripts/archive/refs/heads/main.zip
4) Launch by running run_agent.bat (first edit line 41 for site specific password)



Run the agent (PowerShell):

```
uvicorn agent:app --host 0.0.0.0 --port 8081
```

**Easy startup options:**

`start-agent.ps1` (PowerShell):

```powershell
Set-Location "C:\path\to\orchestrator"
$env:CARLA_AGENT_TOKEN = "replace-with-a-strong-token"
python -m uvicorn agent:app --host 0.0.0.0 --port 8081
```

Place in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup` for auto-start at login.



**Windows service option (runs without login):**

Using NSSM:
```
nssm install carla-agent "C:\Python311\python.exe" "-m uvicorn agent:app --host 0.0.0.0 --port 8081"
nssm set carla-agent AppDirectory "C:\path\to\orchestrator"
nssm set carla-agent AppEnvironmentExtra CARLA_AGENT_TOKEN=replace-with-a-strong-token
nssm start carla-agent
```

> If CARLA needs a logged-in desktop session to render, use the .bat/.ps1 startup scripts instead of a Windows service, or configure the service to "Log on" as a real user.



## Controller (master PC)

1) Copy `controller.py` and `inventory.yml` to the master PC.

2) Edit `inventory.yml` with client IPs/ports and the shared token.

Example `inventory.yml`:
```yaml
# Inventory of client machines running the agent
# Set the same token on agent env CARLA_AGENT_TOKEN and here.
token: "scsu-bect"

clients:
  - name: rig-02
    host: 10.24.0.51
    port: 8081
  - name: laptop-pc
    host: 10.24.0.13
    port: 8081
  # - name: sim03
  #   host: 192.168.10.103
  #   port: 8081
```

3) Use the controller commands below to manage all clients.

### Controller Commands

#### `start` - Launch a process on clients
```bash
python controller.py start --exe "C:\path\to\program.exe" [OPTIONS]
```

**Options:**
- `--job-id <name>` - Job identifier (default: auto-generated from script/exe name). Same job_id automatically replaces running instance. If command includes a script file (.py, .ps1, .bat, etc.), uses the script's name without extension (e.g., `gallery`). Otherwise uses exe name without extension (e.g., `winviz`).
- `--exe <path>` - **Required**. Path to executable on client machines.
- `--args <arg1> <arg2> ...` - Pass arguments to the executable (everything after `--args` is forwarded).
- `--cwd <path>` - Working directory (default: exe's parent directory).
- `--log-dir <path>` - Log directory on clients (default: `C:/wvlab/logs-orchestrator`).
- `--clients <names>` - Target specific clients (comma-separated, e.g., `lab-pc-01,lab-pc-03`). Default: all clients.
- `--wait` - Block until process exits and report returncode (useful for startup scripts).
- `--timeout <seconds>` - **Only applies with `--wait`**. Max seconds to wait for process completion (default: 300). Ignored without `--wait`.

**Examples:**
```bash
# Start CARLA on all clients
python controller.py start --exe "C:\CARLA\CarlaUE4.exe" --args -RenderOffScreen -quality-level=Low

# Start Syncthing on all clients
python controller.py start --job-id syncthing --exe "C:\Program Files\Syncthing\syncthing.exe" --args -no-browser

# Start on specific clients only
python controller.py start --exe "C:\CARLA\CarlaUE4.exe" --clients lab-pc-01,lab-pc-03

# Multiple jobs per client (unique job IDs)
python controller.py start --job-id carla-town01 --exe "C:\CARLA\CarlaUE4.exe" --args -carla-rpc-port=2000
python controller.py start --job-id carla-town02 --exe "C:\CARLA\CarlaUE4.exe" --args -carla-rpc-port=2001

# Start and wait for completion (useful for initialization scripts)
python controller.py start --exe "C:\scripts\setup.bat" --wait --timeout 60
```

**Behavior:**
- Launches process on selected clients concurrently
- With default `job-id`, automatically kills and replaces any running instance
- Waits for old process to fully exit before starting new one (prevents port conflicts)
- Returns immediately unless `--wait` is specified

**Important Notes:**
- The `--timeout` flag does NOT automatically kill processes after N seconds - it only controls how long to wait when using `--wait`
- To run a process for a limited time then stop it, use: `start` to launch, wait N seconds, then `stop` to terminate
- Flags appearing after `--args` are passed to the executable, not to the controller. Always place controller flags before `--args`
- The controller will warn you if flags are misplaced or ignored

#### `status` - Check running jobs on clients
```bash
python controller.py status [--clients <names>]
```

**Options:**
- `--clients <names>` - Target specific clients (default: all)

**Output columns:**
- `NAME` - Client hostname from inventory
- `JOB_ID` - Job identifier (shows `(no jobs)` if agent is idle)
- `PID` - Process ID
- `STATUS` - `running`, `exited`, `idle` (no jobs running), or `unreachable`
- `CPU%` - Current CPU usage
- `MEM(MB)` - Memory usage in MB
- `HUNG` - `True` if CPU < 1% for 30+ seconds (configurable)

**Example output:**
```
NAME         JOB_ID                               PID    STATUS     CPU%   MEM(MB)  HUNG
------------------------------------------------------------------------
lab-pc-01    carla                                4532   running    45.2   2048.3   False
lab-pc-02    (no jobs)                            -      idle       -      -        -
lab-pc-03    carla                                -      exited     -      -        -
lab-pc-04    -                                    -      unreachable -     -        -
```

#### `stop` - Stop all jobs on clients
```bash
python controller.py stop [OPTIONS]
```

**Options:**
- `--mode <term|kill|tree_kill>` - Termination mode (default: `tree_kill`)
  - `term` - Graceful terminate, escalates to kill if needed (waits 5s)
  - `kill` - Hard kill, escalates to tree_kill if needed (waits 5s)
  - `tree_kill` - Kill process and all children recursively (recommended)
- `--clients <names>` - Target specific clients (default: all)

**Examples:**
```bash
# Stop all jobs on all clients
python controller.py stop --mode tree_kill

# Stop jobs on specific clients only
python controller.py stop --clients lab-pc-01,lab-pc-02

# Try graceful shutdown first
python controller.py stop --mode term
```

**Behavior:**
- Stops all jobs on selected clients concurrently
- Waits up to 15 seconds for processes to exit
- Closes log file handles
- Does NOT remove jobs from agent memory (they stay visible in `status` as `exited`)

#### `exec` - Execute a one-shot command and wait for completion
```bash
python controller.py exec --exe "C:\path\to\command.exe" [OPTIONS]
```

**Use cases:** File operations, Python scripts, batch files, configuration tasks

**Options:**
- `--job-id <name>` - Job identifier (default: auto-generated from script/exe name, e.g., `gallery` from `gallery.py`)
- `--exe <path>` - **Required**. Path to executable on client machines
- `--args <arg1> <arg2> ...` - Arguments to pass to executable
- `--cwd <path>` - Working directory (default: exe's parent directory)
- `--log-dir <path>` - Log directory on clients (default: `C:/wvlab/logs-orchestrator`)
- `--clients <names>` - Target specific clients (default: all)
- `--timeout <seconds>` - Max wait time for completion (default: 300)

**Examples:**
```bash
# Copy a file on all clients
python controller.py exec --exe "cmd.exe" --args /c copy C:\source\file.txt C:\dest\file.txt

# Run a Python script on specific clients
python controller.py exec --exe "python" --args C:\scripts\maintenance.py --clients lab-pc-01,lab-pc-02

# Execute a batch file
python controller.py exec --exe "C:\tasks\cleanup.bat" --timeout 60

# PowerShell command
python controller.py exec --exe "powershell.exe" --args -Command "Get-Process | Out-File C:\processes.txt"
```

**Behavior:**
- Starts command on selected clients concurrently
- Auto-generates meaningful job_id from script name (visible in status output)
- Polls every 1 second for completion
- Reports returncode for each client (0 = success, non-zero = failure)
- Exits with code 0 if all clients succeed, 1 if any fail or timeout
- Good for tasks that complete in < 5 minutes

## Common Use Cases

### Starting long-running applications (CARLA, Syncthing, etc.)
Use `start` for processes that run indefinitely:
```bash
# Launch CARLA simulator on all lab PCs
python controller.py start --exe "C:\CARLA\CarlaUE4.exe" --args -RenderOffScreen

# Start Syncthing for file synchronization
python controller.py start --job-id syncthing --exe "C:\Syncthing\syncthing.exe"
```

### Running one-shot tasks (file copy, scripts, maintenance)
Use `exec` for commands that complete and exit:
```bash
# Copy a file to all clients
python controller.py exec --exe "cmd.exe" --args /c copy C:\source\data.csv C:\dest\data.csv

# Run a Python maintenance script
python controller.py exec --exe "python" --args C:\scripts\cleanup.py --timeout 120

# Execute a batch file
python controller.py exec --exe "C:\scripts\update-config.bat"
```

### Targeting specific clients
All commands support `--clients` to target a subset:
```bash
# Launch Python script on just two clients
python controller.py exec --exe "python" --args C:\scripts\collect-logs.py --clients lab-pc-01,lab-pc-03

# Start CARLA on specific GPU nodes
python controller.py start --exe "C:\CARLA\CarlaUE4.exe" --clients gpu-node-01,gpu-node-02
```

### Checking if the agent is running
Use the `/health` endpoint (no auth required) to verify agents are responding:
```bash
curl http://lab-pc-01:8081/health
# Returns: {"status": "ok", "time_utc": "2025-01-15T10:30:00Z", "jobs": 2}
```

## Real-World Examples

### Vizard VR Gallery Demo
Launch the Vizard gallery example on all clients:
```bash
python controller.py start --exe "C:\Program Files\WorldViz\Vizard8\bin\winviz.exe" --args "C:\Program Files\WorldViz\Vizard8\examples\gallery\gallery.py"
# Auto-generated job_id: gallery
```

### CARLA Quickstart Script
Run the CARLA Python quickstart with venv Python:
```bash
python controller.py start --exe "C:\wvlab\venv-carla\Scripts\python.exe" --args "C:\Users\WorldViz\Documents\SCSU\PythonAPI\quickstart.py"
# Auto-generated job_id: quickstart
```

### Streamlit CARLA Dashboard
Launch a Streamlit app for CARLA monitoring:
```bash
python controller.py start --exe "C:\wvlab\venv-carla\Scripts\python.exe" --args -m streamlit run "C:\Users\WorldViz\Documents\SCSU\carla_streamlit_app.py"
# Auto-generated job_id: carla_streamlit_app
```

### Kill CARLA Processes
Execute batch file to clean up any stray CARLA processes:
```bash
python controller.py exec --exe "C:\wvlab\carla\source\SCSU\kill_carla.bat"
# Auto-generated job_id: kill_carla
```

### Restart Client Machines
Force restart of all client PCs (use with caution):
```bash
python controller.py exec --exe "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" --args "Restart-Computer -Force"
# Auto-generated job_id: powershell
```

### CARLA Doctor Diagnostic Tool
Run diagnostic script with window kept open to view results:
```bash
python controller.py exec --exe "powershell.exe" --args -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoExit','-Command','iwr -useb util.worldviz.com/run-carla-doctor.ps1 | iex'"
# Auto-generated job_id: powershell
# The -NoExit flag keeps the PowerShell window open after script completes
```

## Notes for CARLA

- The `--job-id` is auto-generated from your script name without extension (e.g., `quickstart` from `quickstart.py`), which enables automatic replacement of running instances when you restart. To run multiple jobs per client, specify unique job IDs with `--job-id`.
- Make sure the `--cwd` is a folder where CARLA expects to run if needed (defaults to the exe's directory if not specified).
- If running offscreen on Windows, flags often include `-RenderOffScreen` and sometimes `-unattended`.
- If you need unique ports per machine, pass them via `--args` (e.g., `-carla-rpc-port=2001` etc.).
- Logs are written per-job to the client `log_dir` (default: `C:\wvlab\logs-orchestrator`).

## Security

- The agent enforces a bearer token (set `CARLA_AGENT_TOKEN` on each client and `token:` in `inventory.yml`).
- Consider firewalling the agent port to your master machine only.

---

## Advanced Topics

### Agent REST API (Direct Access)

The controller wraps these endpoints, but you can call them directly if needed for custom integrations or debugging.

#### `GET /health` (no auth)
Health check endpoint
```bash
curl http://lab-pc-01:8081/health
# Returns: {"status": "ok", "time_utc": "2025-01-15T10:30:00Z", "jobs": 2}
```

#### `POST /start` (requires auth)
Start a single job on one agent
```bash
curl -X POST http://lab-pc-01:8081/start \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": "carla",
    "cmd": ["C:/CARLA/CarlaUE4.exe", "-RenderOffScreen"],
    "cwd": null,
    "log_dir": "C:/wvlab/logs-orchestrator",
    "kill_existing": true
  }'
```

#### `GET /status` (requires auth)
Get status of all jobs on one agent
```bash
curl http://lab-pc-01:8081/status -H "Authorization: Bearer YOUR_TOKEN"
```

#### `POST /stop` (requires auth)
Stop a specific job by job_id
```bash
curl -X POST http://lab-pc-01:8081/stop \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"job_id": "carla", "mode": "tree_kill"}'
```

#### `POST /stop_all` (requires auth)
Stop all jobs on one agent
```bash
curl -X POST "http://lab-pc-01:8081/stop_all?mode=tree_kill" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Extending the System

Ideas for future enhancements:
- Add a `/logs` endpoint to stream last N lines from stdout/stderr
- Add WebSocket push for live status updates
- Integrate with Prometheus (expose metrics) or build a web dashboard with Grafana
- Add support for scheduled tasks or cron-like job execution
