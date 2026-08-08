#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "fastmcp>=0.3.0",
# ]
# ///
"""
Devbook Service Manager — MCP server.

Exposes the bash service-manager.sh engine to any MCP-capable coding agent
(opencode, Claude Desktop, etc.) as a set of tools:

  - list_services()        → all registered services + status
  - service_status(name)   → status of one service
  - service_start(name)    → start a service
  - service_stop(name)     → stop a service
  - service_restart(name)  → restart a service
  - service_info(name)     → detailed info for a service
  - system_overview()      → battery, disk, uptime snapshot

The server is a thin wrapper: every tool shells out to service-manager.sh and
returns its JSON output. Heavy lifting (launchctl, colima, cloudflared, etc.)
stays in bash where those tools live.

Run directly:
    uv run scripts/services/mcp-server/server.py

Wired into opencode.jsonc / Claude Desktop config as a local stdio MCP server
(see install.sh).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Resolve service-manager.sh relative to this file so it works regardless of CWD.
_HERE = Path(__file__).resolve().parent
MANAGER = _HERE.parent / "service-manager.sh"

# Timeout for service actions (start/stop can take a few seconds for colima etc.)
ACTION_TIMEOUT = float(os.environ.get("PULSE_SVC_TIMEOUT", "30"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run_manager(*args: str, timeout: float | None = None) -> dict[str, Any]:
    """Run service-manager.sh with --json and return parsed JSON.

    Falls back to a structured envelope on error so tools always return JSON.
    """
    if not MANAGER.exists():
        return {"ok": False, "error": f"manager not found at {MANAGER}"}

    cmd = [str(MANAGER), *args, "--json"]
    # Avoid duplicate --json if caller already passed it
    if args and args[-1] == "--json":
        cmd = [str(MANAGER), *args]

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout or ACTION_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        return {"ok": False, "error": f"timeout after {e.timeout}s", "cmd": cmd}
    except FileNotFoundError as e:
        return {"ok": False, "error": f"manager binary missing: {e}"}

    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()

    if not stdout:
        return {
            "ok": proc.returncode == 0,
            "error": stderr or "no output",
            "returncode": proc.returncode,
        }

    # The manager may emit human text on stderr (progress) and JSON on stdout.
    try:
        data = json.loads(stdout)
    except json.JSONDecodeError:
        # Not JSON — return raw text
        return {
            "ok": proc.returncode == 0,
            "output": stdout,
            "stderr": stderr,
            "returncode": proc.returncode,
        }

    if isinstance(data, list):
        return {"ok": proc.returncode == 0, "services": data, "stderr": stderr}
    # data is a dict — augment with ok + stderr
    if isinstance(data, dict):
        data.setdefault("ok", proc.returncode == 0)
        if stderr:
            data.setdefault("stderr", stderr)
    return data


# ---------------------------------------------------------------------------
# MCP tools
# ---------------------------------------------------------------------------

mcp = FastMCP("devbook-service-manager")


@mcp.tool()
def list_services() -> dict[str, Any]:
    """List all registered services and their current status.

    Returns a JSON object with a `services` array; each entry has:
      name, display_name, status ("running" | "stopped" | "unknown"),
      and capabilities (array of supported actions).
    """
    return _run_manager("list")


@mcp.tool()
def service_status(name: str) -> dict[str, Any]:
    """Get the current status of a single service by name.

    Args:
        name: Service name (e.g. "colima", "docker", "cloudflared",
              "headroom", "basic-memory", "battery").
    """
    return _run_manager("status", name)


@mcp.tool()
def service_start(name: str) -> dict[str, Any]:
    """Start a service. No-op if already running.

    Args:
        name: Service name. Must declare "start" capability.
    """
    # Use a longer timeout for start (colima boot can take ~30s)
    return _run_manager("start", name, timeout=120.0)


@mcp.tool()
def service_stop(name: str) -> dict[str, Any]:
    """Stop a service. No-op if already stopped.

    Args:
        name: Service name. Must declare "stop" capability.
    """
    return _run_manager("stop", name, timeout=60.0)


@mcp.tool()
def service_restart(name: str) -> dict[str, Any]:
    """Restart a service (stop + start, or adapter-specific).

    Args:
        name: Service name. Must declare "restart" capability.
    """
    return _run_manager("restart", name, timeout=120.0)


@mcp.tool()
def service_info(name: str) -> dict[str, Any]:
    """Get detailed info for a service (version, PID, ports, paths, etc.).

    Args:
        name: Service name.
    """
    # info is human-readable — no --json, wrap the text
    if not MANAGER.exists():
        return {"ok": False, "error": f"manager not found at {MANAGER}"}
    try:
        proc = subprocess.run(
            [str(MANAGER), "info", name],
            capture_output=True,
            text=True,
            timeout=ACTION_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        return {"ok": False, "error": f"timeout after {e.timeout}s"}
    return {
        "ok": proc.returncode == 0,
        "name": name,
        "output": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }


@mcp.tool()
def system_overview() -> dict[str, Any]:
    """Get a system snapshot: battery percent/state, disk usage, uptime.

    Read-only — safe to call anytime.
    """
    return _run_manager("system")


@mcp.tool()
def which_services_running() -> dict[str, Any]:
    """Convenience: return just the names of services currently in 'running' state."""
    data = _run_manager("list")
    services = data.get("services", []) if isinstance(data, dict) else []
    running = [s["name"] for s in services if s.get("status") == "running"]
    return {"running": running, "count": len(running)}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # FastMCP auto-detects stdio transport when run as a plain script.
    # Agents launch this file via `uv run server.py` and speak MCP over stdio.
    mcp.run()
