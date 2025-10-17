
import os
import sys
import time
import uuid
import signal
import threading
from datetime import datetime, timezone
from typing import Dict, Optional, List

import psutil
from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field
import subprocess

# ---------- Config ----------
# Read a shared bearer token from env (set this on each client)
AUTH_TOKEN = os.environ.get("CARLA_AGENT_TOKEN", "change-me")

# How often to refresh internal metrics (seconds)
METRICS_INTERVAL = float(os.environ.get("CARLA_AGENT_METRICS_INTERVAL", "2.0"))

# Consider a process "possibly hung" if CPU is below this % for this many seconds
HUNG_CPU_PCT = float(os.environ.get("CARLA_AGENT_HUNG_CPU_PCT", "1.0"))
HUNG_SECS = float(os.environ.get("CARLA_AGENT_HUNG_SECS", "30.0"))

app = FastAPI(title="CARLA Orchestrator Agent", version="0.1.0")

def require_auth(authorization: Optional[str] = Header(None)):
    if AUTH_TOKEN == "change-me":
        # Allow but warn in logs
        print("[WARN] CARLA_AGENT_TOKEN not set; running without real auth.", flush=True)
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    if token != AUTH_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid token")

class StartRequest(BaseModel):
    job_id: Optional[str] = Field(default=None, description="If omitted, a UUID will be assigned")
    cmd: List[str] = Field(..., description="Command list, e.g. ['C:/CARLA/CarlaUE4.exe','-RenderOffScreen']")
    cwd: Optional[str] = Field(default=None, description="Working directory")
    env: Optional[Dict[str, str]] = Field(default=None, description="Extra env vars")
    log_dir: Optional[str] = Field(default=None, description="Directory to store stdout/stderr logs")
    kill_existing: bool = Field(default=False, description="If same job_id running, kill it first")

class StopRequest(BaseModel):
    job_id: str
    mode: str = Field(default="term", description="term | kill | tree_kill")

class ProcInfo(BaseModel):
    job_id: str
    pid: int
    status: str
    returncode: Optional[int] = None
    start_time_utc: str
    uptime_sec: float
    cpu_percent: float
    mem_mb: float
    last_cpu_active_utc: str
    is_hung: bool
    cmdline: List[str]
    cwd: Optional[str]
    stdout_log: Optional[str]
    stderr_log: Optional[str]

class StartResponse(BaseModel):
    job_id: str
    pid: int
    stdout_log: Optional[str]
    stderr_log: Optional[str]

# In-memory job table
class _Job:
    def __init__(self, job_id: str, popen: subprocess.Popen, cwd: Optional[str], logs):
        self.job_id = job_id
        self.popen = popen
        self.cwd = cwd
        self.log_paths = logs  # (stdout_path, stderr_path) - for reporting
        self.log_files = None  # Will store (stdout_file, stderr_file) file objects
        self.start_ts = time.time()
        self.last_cpu_active_ts = self.start_ts
        self.cpu_percent = 0.0
        self.mem_mb = 0.0
        self.is_hung = False
        self.cmdline = popen.args if isinstance(popen.args, list) else [str(popen.args)]
        self.lock = threading.Lock()

    def close_logs(self):
        """Close log file handles if open."""
        if self.log_files:
            try:
                if self.log_files[0]:
                    self.log_files[0].close()
            except Exception:
                pass
            try:
                if self.log_files[1]:
                    self.log_files[1].close()
            except Exception:
                pass
            self.log_files = None

    def snapshot(self) -> ProcInfo:
        with self.lock:
            try:
                p = psutil.Process(self.popen.pid)
                cpu = p.cpu_percent(interval=0.1)  # Measure over 100ms for accurate reading
                mem = p.memory_info().rss / (1024*1024)
                now = time.time()
                if cpu > HUNG_CPU_PCT:
                    self.last_cpu_active_ts = now
                self.cpu_percent = cpu
                self.mem_mb = mem
                hung_elapsed = now - self.last_cpu_active_ts
                self.is_hung = (hung_elapsed >= HUNG_SECS)
                status = "running"
                ret = None
                if self.popen.poll() is not None:
                    status = "exited"
                    ret = self.popen.returncode
                return ProcInfo(
                    job_id=self.job_id,
                    pid=self.popen.pid,
                    status=status,
                    returncode=ret,
                    start_time_utc=datetime.fromtimestamp(self.start_ts, tz=timezone.utc).isoformat(),
                    uptime_sec=now - self.start_ts,
                    cpu_percent=self.cpu_percent,
                    mem_mb=self.mem_mb,
                    last_cpu_active_utc=datetime.fromtimestamp(self.last_cpu_active_ts, tz=timezone.utc).isoformat(),
                    is_hung=self.is_hung,
                    cmdline=[str(c) for c in self.cmdline],
                    cwd=self.cwd,
                    stdout_log=self.log_paths[0] if self.log_paths else None,
                    stderr_log=self.log_paths[1] if self.log_paths else None,
                )
            except psutil.NoSuchProcess:
                # Process no longer exists in process table, but popen may still have returncode
                ret = self.popen.poll()
                return ProcInfo(
                    job_id=self.job_id,
                    pid=self.popen.pid,
                    status="exited" if ret is not None else "unknown",
                    returncode=ret,
                    start_time_utc=datetime.fromtimestamp(self.start_ts, tz=timezone.utc).isoformat(),
                    uptime_sec=max(0.0, time.time() - self.start_ts),
                    cpu_percent=0.0,
                    mem_mb=0.0,
                    last_cpu_active_utc=datetime.fromtimestamp(self.last_cpu_active_ts, tz=timezone.utc).isoformat(),
                    is_hung=True,
                    cmdline=[str(c) for c in self.cmdline],
                    cwd=self.cwd,
                    stdout_log=self.log_paths[0] if self.log_paths else None,
                    stderr_log=self.log_paths[1] if self.log_paths else None,
                )

JOBS: Dict[str, _Job] = {}
JOBS_LOCK = threading.Lock()

def _windows_creationflags():
    flags = 0
    # CREATE_NEW_PROCESS_GROUP allows clean tree killing via psutil
    if hasattr(subprocess, "CREATE_NEW_PROCESS_GROUP"):
        flags |= subprocess.CREATE_NEW_PROCESS_GROUP
    # CREATE_NO_WINDOW prevents console windows from appearing
    if hasattr(subprocess, "CREATE_NO_WINDOW"):
        flags |= subprocess.CREATE_NO_WINDOW
    return flags

def _open_logs(log_dir: Optional[str], job_id: str):
    if not log_dir:
        return None
    os.makedirs(log_dir, exist_ok=True)
    stdout_path = os.path.join(log_dir, f"{job_id}.out.log")
    stderr_path = os.path.join(log_dir, f"{job_id}.err.log")
    return (stdout_path, stderr_path)

@app.get("/health")
def health():
    return {"status": "ok", "time_utc": datetime.now(timezone.utc).isoformat(), "jobs": len(JOBS)}

@app.post("/start", response_model=StartResponse, dependencies=[Depends(require_auth)])
def start_job(req: StartRequest):
    job_id = req.job_id or str(uuid.uuid4())
    with JOBS_LOCK:
        if req.kill_existing and job_id in JOBS:
            old_job = JOBS[job_id]
            _kill_job(old_job, mode="tree_kill")
            JOBS.pop(job_id, None)
            # Wait for PID to actually exit to prevent port/resource conflicts
            old_pid = old_job.popen.pid
            deadline = time.time() + 15.0
            while time.time() < deadline:
                if not psutil.pid_exists(old_pid):
                    break
                time.sleep(0.2)
            else:
                print(f"[WARN] Old job {job_id} PID {old_pid} still exists after 15s", flush=True)
        elif job_id in JOBS:
            raise HTTPException(status_code=409, detail=f"job_id '{job_id}' already exists")

        log_paths = _open_logs(req.log_dir, job_id)
        # Open log files with UTF-8 encoding in text mode to handle Unicode characters
        stdout_file = open(log_paths[0], "a", encoding="utf-8", buffering=1) if log_paths else None
        stderr_file = open(log_paths[1], "a", encoding="utf-8", buffering=1) if log_paths else None

        env = os.environ.copy()
        if req.env:
            env.update(req.env)
        # Ensure Python uses UTF-8 encoding for output
        env['PYTHONIOENCODING'] = 'utf-8'

        creationflags = _windows_creationflags() if os.name == "nt" else 0

        try:
            popen = subprocess.Popen(
                req.cmd,
                cwd=req.cwd or None,
                env=env,
                stdout=stdout_file if stdout_file else subprocess.DEVNULL,
                stderr=stderr_file if stderr_file else subprocess.DEVNULL,
                shell=False,
                creationflags=creationflags
            )
        except Exception as e:
            # Clean up file handles on failure
            if stdout_file:
                stdout_file.close()
            if stderr_file:
                stderr_file.close()
            raise HTTPException(status_code=500, detail=f"Failed to start: {e}")

        job = _Job(job_id, popen, req.cwd, log_paths)
        job.log_files = (stdout_file, stderr_file) if log_paths else None
        JOBS[job_id] = job

    return StartResponse(job_id=job_id, pid=popen.pid, stdout_log=log_paths[0] if log_paths else None, stderr_log=log_paths[1] if log_paths else None)

def _kill_job(job: _Job, mode: str = "term") -> bool:
    """Kill a job process, escalating through terminate -> kill -> tree_kill.
    Returns True if process confirmed dead, False if still alive after all attempts.
    """
    try:
        p = psutil.Process(job.popen.pid)
    except psutil.NoSuchProcess:
        job.close_logs()  # Clean up file handles
        return True  # Already dead

    # First, collect all descendants including those in different process groups
    # This handles cases where child processes used CREATE_NEW_CONSOLE or similar
    all_procs = []
    try:
        all_procs = [p] + p.children(recursive=True)
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        all_procs = [p]
    
    # Also check for CarlaUE4 processes that may have been spawned by this job
    # by checking command line arguments or timing heuristics
    try:
        job_start_time = job.start_ts
        for proc in psutil.process_iter(['pid', 'name', 'exe', 'create_time', 'cmdline']):
            try:
                proc_name = proc.info.get('name', '').lower()
                proc_exe = (proc.info.get('exe') or '').lower()
                
                # Check if it's a CARLA process
                if any(keyword in proc_name or keyword in proc_exe for keyword in 
                       ['carlaue4', 'bootstrappackagedgame', 'ue4editor']):
                    
                    # Check if it was created after this job started (within 60 seconds)
                    proc_start = proc.info.get('create_time', 0)
                    if proc_start >= job_start_time - 5 and proc_start <= job_start_time + 60:
                        # This is likely spawned by our job
                        if proc.pid not in [p.pid for p in all_procs]:
                            all_procs.append(proc)
                            
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
    except Exception:
        pass  # Continue with what we have

    # Try terminate first (soft stop)
    if mode in ("term", "kill", "tree_kill"):
        for proc in all_procs:
            try:
                proc.terminate()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        # Wait for all to terminate
        gone, alive = psutil.wait_procs(all_procs, timeout=5.0)
        if not alive:
            job.close_logs()
            return True  # All terminated successfully

    # Escalate to kill (hard stop)
    if mode in ("kill", "tree_kill"):
        for proc in alive if mode in ("kill", "tree_kill") else all_procs:
            try:
                proc.kill()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        # Wait for all to be killed
        gone, alive = psutil.wait_procs(all_procs, timeout=5.0)
        if not alive:
            job.close_logs()
            return True  # All killed successfully
    
    # Check if any are still alive
    try:
        if not psutil.pid_exists(job.popen.pid):
            job.close_logs()
            return True
    except:
        pass
    
    if alive:
        print(f"[WARN] {len(alive)} process(es) survived tree_kill: {[p.pid for p in alive]}", flush=True)
        return False
    
    job.close_logs()
    return True

@app.post("/stop", dependencies=[Depends(require_auth)])
def stop_job(req: StopRequest):
    with JOBS_LOCK:
        job = JOBS.get(req.job_id)
        if not job:
            raise HTTPException(status_code=404, detail="job_id not found")
        _kill_job(job, mode=req.mode)
        return {"status": "sent", "job_id": req.job_id, "mode": req.mode}

@app.get("/status", response_model=List[ProcInfo], dependencies=[Depends(require_auth)])
def status():
    out: List[ProcInfo] = []
    with JOBS_LOCK:
        for job_id, job in JOBS.items():
            out.append(job.snapshot())
    return out

@app.post("/stop_all", dependencies=[Depends(require_auth)])
def stop_all(mode: str = "tree_kill"):
    with JOBS_LOCK:
        for job in list(JOBS.values()):
            _kill_job(job, mode=mode)
    return {"status": "sent", "mode": mode}

# Optional background metrics thread (kept simple; snapshot() already updates on demand)
def _metrics_loop():
    while True:
        time.sleep(METRICS_INTERVAL)
        with JOBS_LOCK:
            # prune exited to avoid leak
            for jid, job in list(JOBS.items()):
                if job.popen.poll() is not None:
                    # keep it for a short while for inspection
                    if (time.time() - job.start_ts) > 3600:
                        job.close_logs()
                        JOBS.pop(jid, None)

t = threading.Thread(target=_metrics_loop, daemon=True)
t.start()

# To run: uvicorn agent:app --host 0.0.0.0 --port 8081
