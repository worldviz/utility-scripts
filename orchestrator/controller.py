
import os
import ntpath  # For parsing Windows paths on any platform
import time
import argparse
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
import yaml

DEFAULT_TIMEOUT = 5.0

def load_inv(inv_path):
    with open(inv_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

def auth_header(token):
    return {"Authorization": f"Bearer {token}"} if token and token != "change-me" else {}

def filter_clients(inv, client_filter):
    """Filter inventory clients by comma-separated names. Returns full inv dict with filtered clients."""
    if not client_filter:
        return inv
    allowed = set(name.strip() for name in client_filter.split(","))
    filtered = [c for c in inv["clients"] if c["name"] in allowed]
    if not filtered:
        print(f"[WARN] No clients matched filter: {client_filter}")
    return {**inv, "clients": filtered}

def start_all(inv, payload):
    token = inv.get("token", "change-me")
    futures = []
    with ThreadPoolExecutor(max_workers=min(32, len(inv["clients"]))) as ex:
        for c in inv["clients"]:
            url = f'http://{c["host"]}:{c.get("port", 8081)}/start'
            futures.append(ex.submit(_post_json, url, payload, token, c["name"]))
        for fut in as_completed(futures):
            name, ok, data = fut.result()
            print(f"[{name}] start -> {ok} {data}")

def stop_all(inv, mode="tree_kill"):
    token = inv.get("token", "change-me")
    futures = []
    with ThreadPoolExecutor(max_workers=min(32, len(inv["clients"]))) as ex:
        for c in inv["clients"]:
            url = f'http://{c["host"]}:{c.get("port", 8081)}/stop_all?mode={mode}'
            futures.append(ex.submit(_post_empty, url, token, c["name"]))
        for fut in as_completed(futures):
            name, ok, data = fut.result()
            print(f"[{name}] stop_all -> {ok} {data}")

def status(inv):
    token = inv.get("token", "change-me")
    futures = []
    with ThreadPoolExecutor(max_workers=min(32, len(inv["clients"]))) as ex:
        for c in inv["clients"]:
            url = f'http://{c["host"]}:{c.get("port", 8081)}/status'
            futures.append(ex.submit(_get, url, token, c["name"]))
        rows = []
        for fut in as_completed(futures):
            name, ok, data = fut.result()
            if ok and isinstance(data, list):
                if len(data) == 0:
                    # Agent is up but has no jobs
                    rows.append((name, "(no jobs)", "-", "idle", "-", "-", "-"))
                else:
                    for proc in data:
                        rows.append((name, proc["job_id"], proc["pid"], proc["status"], round(proc["cpu_percent"], 1), round(proc["mem_mb"], 1), proc["is_hung"]))
            else:
                rows.append((name, "-", "-", "unreachable", "-", "-", "-"))
        rows.sort()
        print("\nNAME | JOB_ID | PID | STATUS | CPU% | MEM(MB) | HUNG")
        print("-"*72)
        for r in rows:
            print(f"{r[0]:<12} {r[1]:<36} {str(r[2]):<6} {r[3]:<10} {str(r[4]):<6} {str(r[5]):<8} {str(r[6])}")

def exec_and_wait(inv, payload, poll_interval=1.0, timeout=300.0):
    """Execute a command and wait for it to complete. Returns dict of {client_name: returncode}."""
    import uuid
    token = inv.get("token", "change-me")

    # Start jobs on all clients
    job_id = payload.get("job_id") or str(uuid.uuid4())
    payload["job_id"] = job_id
    futures = []
    with ThreadPoolExecutor(max_workers=min(32, len(inv["clients"]))) as ex:
        for c in inv["clients"]:
            url = f'http://{c["host"]}:{c.get("port", 8081)}/start'
            futures.append(ex.submit(_post_json, url, payload, token, c["name"]))

        started = {}
        for fut in as_completed(futures):
            name, ok, data = fut.result()
            if ok:
                print(f"[{name}] started job {job_id}, pid {data.get('pid')}")
                started[name] = True
            else:
                print(f"[{name}] failed to start: {data}")
                started[name] = False

    # Poll for completion
    print(f"\nWaiting for jobs to complete (timeout: {timeout}s)...")
    start_time = time.time()
    results = {}

    while time.time() - start_time < timeout:
        all_done = True
        for c in inv["clients"]:
            name = c["name"]
            if name in results:
                continue
            if not started.get(name):
                continue

            # Check status
            url = f'http://{c["host"]}:{c.get("port", 8081)}/status'
            try:
                resp = requests.get(url, headers=auth_header(token), timeout=DEFAULT_TIMEOUT)
                if resp.ok:
                    jobs = resp.json()
                    found = False
                    for job in jobs:
                        if job["job_id"] == job_id:
                            found = True
                            if job["status"] in ("exited", "unknown"):
                                # Process has ended (either cleanly or disappeared from process table)
                                results[name] = job.get("returncode", 0)
                                print(f"[{name}] completed with returncode {results[name]} (status: {job['status']})")
                            else:
                                print(f"[{name}] still running (status: {job['status']})")
                                all_done = False
                            break

                    if not found:
                        # Job not found in status list - may have exited very quickly
                        # Mark as complete with unknown returncode
                        results[name] = 0  # Assume success for fast-exit commands
                        print(f"[{name}] job not found in status (likely exited quickly) - assuming success")
                else:
                    print(f"[{name}] HTTP error: {resp.status_code}")
                    all_done = False
            except Exception as e:
                print(f"[{name}] error checking status: {e}")
                all_done = False

        if all_done:
            break
        time.sleep(poll_interval)

    # Check for timeouts
    for c in inv["clients"]:
        name = c["name"]
        if started.get(name) and name not in results:
            print(f"[{name}] TIMEOUT after {timeout}s")
            results[name] = None

    return results

def _post_json(url, payload, token, name):
    try:
        resp = requests.post(url, json=payload, headers=auth_header(token), timeout=DEFAULT_TIMEOUT)
        if resp.ok:
            return name, True, resp.json()
        return name, False, f"{resp.status_code} {resp.text}"
    except Exception as e:
        return name, False, str(e)

def _post_empty(url, token, name):
    try:
        resp = requests.post(url, headers=auth_header(token), timeout=DEFAULT_TIMEOUT)
        if resp.ok:
            return name, True, resp.json()
        return name, False, f"{resp.status_code} {resp.text}"
    except Exception as e:
        return name, False, str(e)

def _get(url, token, name):
    try:
        resp = requests.get(url, headers=auth_header(token), timeout=DEFAULT_TIMEOUT)
        if resp.ok:
            return name, True, resp.json()
        return name, False, f"{resp.status_code} {resp.text}"
    except Exception as e:
        return name, False, str(e)

def generate_job_id(exe, args):
    """Generate a meaningful job_id from the command.

    Looks for script files in args (.py, .ps1, .bat, etc.) and uses their basename.
    Falls back to exe basename if no script found.
    Uses ntpath to correctly parse Windows paths even when running on Mac/Linux.
    """
    # Common script extensions to look for
    script_extensions = ('.py', '.ps1', '.bat', '.sh', '.js', '.rb', '.pl', '.r', '.m')

    # Search through args for any script files
    for arg in args:
        if not arg:
            continue
        arg_lower = arg.lower()
        for ext in script_extensions:
            if arg_lower.endswith(ext):
                # Found a script file, extract just the filename using ntpath (for Windows paths)
                basename = ntpath.basename(arg)
                # Remove the extension to keep it cleaner
                name_without_ext = ntpath.splitext(basename)[0]
                return name_without_ext

    # No script found, use exe basename without extension
    basename = ntpath.basename(exe)
    return ntpath.splitext(basename)[0]

def main():
    import sys

    parser = argparse.ArgumentParser(description="Control CARLA agents on LAN")
    parser.add_argument("--inventory", "-i", default="inventory.yml", help="Path to inventory YAML")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_start = sub.add_parser("start", help="Start a job on clients")
    p_start.add_argument("--job-id", default=None, help="Job identifier (default: auto-generated from command)")
    p_start.add_argument("--exe", required=True, help="Path to executable on the client machines")
    p_start.add_argument("--args", nargs=argparse.REMAINDER, default=[], help="Arguments to pass to executable (everything after --args ...)")
    p_start.add_argument("--cwd", default=None)
    p_start.add_argument("--log-dir", default="C:/wvlab/logs-orchestrator")
    p_start.add_argument("--clients", default=None, help="Comma-separated client names to target (default: all)")
    p_start.add_argument("--wait", action="store_true", help="Wait for process to exit and report returncode")
    p_start.add_argument("--timeout", type=float, default=300.0, help="Timeout in seconds (only applies with --wait)")

    p_stop = sub.add_parser("stop", help="Stop all jobs on clients")
    p_stop.add_argument("--mode", choices=["term", "kill", "tree_kill"], default="tree_kill")
    p_stop.add_argument("--clients", default=None, help="Comma-separated client names to target (default: all)")

    p_status = sub.add_parser("status", help="Fetch status from clients")
    p_status.add_argument("--clients", default=None, help="Comma-separated client names to target (default: all)")

    p_exec = sub.add_parser("exec", help="Execute a command and wait for completion (for one-shot tasks)")
    p_exec.add_argument("--job-id", default=None, help="Job identifier (default: auto-generated from script/exe name)")
    p_exec.add_argument("--exe", required=True, help="Path to executable on the client machines")
    p_exec.add_argument("--args", nargs=argparse.REMAINDER, default=[], help="Arguments to pass to executable (everything after --args ...)")
    p_exec.add_argument("--cwd", default=None)
    p_exec.add_argument("--log-dir", default="C:/wvlab/logs-orchestrator")
    p_exec.add_argument("--clients", default=None, help="Comma-separated client names to target (default: all)")
    p_exec.add_argument("--timeout", type=float, default=300.0, help="Timeout in seconds to wait for completion")

    # Parse arguments and check for unknown flags before --args
    args_list = sys.argv[1:]
    if "--args" in args_list:
        args_idx = args_list.index("--args")
        before_args = args_list[:args_idx+1]
        after_args = args_list[args_idx+1:]

        # Check for flags in the after_args section (typos like --timeoutttt)
        for item in after_args:
            if item.startswith("--") and item not in ["--help", "-h"]:
                print(f"WARNING: Flag '{item}' appears after --args and will be passed to the executable as an argument.", file=sys.stderr)
                print(f"         If this is a controller flag, move it before --args", file=sys.stderr)

        args = parser.parse_args(before_args + after_args)
    else:
        args = parser.parse_args()
    inv = load_inv(args.inventory)

    # Apply client filter if specified
    inv = filter_clients(inv, getattr(args, 'clients', None))

    # Generate smart job_id if not provided (for both start and exec)
    if args.cmd in ("start", "exec") and args.job_id is None:
        args.job_id = generate_job_id(args.exe, args.args or [])
        print(f"Using auto-generated job_id: {args.job_id}", file=sys.stderr)

    # Validation warnings for conflicting/ignored flags
    if args.cmd == "start":
        if hasattr(args, 'timeout') and args.timeout != 300.0 and not args.wait:
            print(f"WARNING: --timeout {args.timeout} is ignored without --wait flag", file=sys.stderr)
            print(f"         Use 'python controller.py start --exe ... --wait --timeout {args.timeout}' to wait for process completion", file=sys.stderr)

    if args.cmd == "start":
        payload = {
            "job_id": args.job_id,
            "cmd": [args.exe] + (args.args or []),
            "cwd": args.cwd,
            "env": None,
            "log_dir": args.log_dir,
            "kill_existing": True
        }
        if args.wait:
            results = exec_and_wait(inv, payload, timeout=args.timeout)
            print("\n=== RESULTS ===")
            all_success = True
            for name, returncode in sorted(results.items()):
                if returncode == 0:
                    print(f"[{name}] SUCCESS (returncode 0)")
                elif returncode is None:
                    print(f"[{name}] TIMEOUT")
                    all_success = False
                else:
                    print(f"[{name}] FAILED (returncode {returncode})")
                    all_success = False
            import sys
            sys.exit(0 if all_success else 1)
        else:
            start_all(inv, payload)
    elif args.cmd == "stop":
        stop_all(inv, mode=args.mode)
    elif args.cmd == "status":
        status(inv)
    elif args.cmd == "exec":
        payload = {
            "job_id": args.job_id,
            "cmd": [args.exe] + (args.args or []),
            "cwd": args.cwd,
            "env": None,
            "log_dir": args.log_dir,
            "kill_existing": True  # Allow re-running same exec task (replaces previous)
        }
        results = exec_and_wait(inv, payload, timeout=args.timeout)
        print("\n=== RESULTS ===")
        all_success = True
        for name, returncode in sorted(results.items()):
            if returncode == 0:
                print(f"[{name}] SUCCESS (returncode 0)")
            elif returncode is None:
                print(f"[{name}] TIMEOUT")
                all_success = False
            else:
                print(f"[{name}] FAILED (returncode {returncode})")
                all_success = False
        import sys
        sys.exit(0 if all_success else 1)

if __name__ == "__main__":
    main()
