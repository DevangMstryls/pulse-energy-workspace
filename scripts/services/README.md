# Devbook Service Manager

A unified manager for local dev services, daemons, and MCP servers on this Mac.
Exposed as an MCP server so any coding agent (opencode, Claude Desktop, etc.)
can query status, start, stop, and restart services.

## What it manages

| Service        | Type           | Status | Start/Stop | Notes                                            |
| -------------- | -------------- | ------ | ---------- | ------------------------------------------------ |
| `colima`       | VM runtime     | ✓      | ✓          | Manages the Docker daemon                        |
| `docker`       | CLI / daemon   | ✓      | —          | Daemon managed by colima (read-only adapter)     |
| `cloudflared`  | launchd daemon | ✓      | ✓          | `com.cloudflare.cloudflared` plist               |
| `headroom`     | Proxy + MCP    | ✓      | ✓          | Delegates to `scripts/headroom.sh`               |
| `basic-memory` | MCP (stdio)    | ✓      | ✓*         | Agent-launched by default; bg instance optional  |
| `battery`      | System metric  | ✓      | —          | Read-only — `pmset -g batt`                      |

\* basic-memory's MCP server is normally launched per-session by the agent over
stdio. The start/stop here only manages an optional long-lived background
instance (NOT recommended for normal agent use).

## Layout

```
scripts/services/
├── service-manager.sh                # core bash engine
├── services.d/                       # per-service adapters (sourced)
│   ├── colima.sh
│   ├── docker.sh
│   ├── cloudflared.sh
│   ├── headroom.sh
│   ├── basic-memory.sh
│   └── battery.sh
├── mcp-server/server.py              # FastMCP wrapper (PEP 723, uv run)
├── com.devbook.service-manager.plist # launchd user agent template
├── install.sh                        # registers daemon + opencode MCP entry
└── README.md                         # this file
```

## Quickstart

### Install (registers launchd daemon + opencode MCP entry)

```bash
./scripts/services/install.sh
```

Then restart opencode. The `devbook-service-manager` MCP server will be available;
its tools (`list_services`, `service_status`, `service_start`, etc.) can be
called by any agent session.

### Manual use (no install)

```bash
./scripts/services/service-manager.sh list
./scripts/services/service-manager.sh status colima
./scripts/services/service-manager.sh start colima
./scripts/services/service-manager.sh restart cloudflared
./scripts/services/service-manager.sh system          # battery, disk, uptime
```

JSON output for scripting / MCP:

```bash
./scripts/services/service-manager.sh list --json
./scripts/services/service-manager.sh status headroom --json
```

### Run the MCP server directly

```bash
uv run scripts/services/mcp-server/server.py
```

(First run auto-installs `fastmcp` into uv's ephemeral env — no venv juggling.)

### Uninstall

```bash
./scripts/services/install.sh --uninstall
```

## MCP tools exposed

| Tool                     | Description                                   |
| ------------------------ | --------------------------------------------- |
| `list_services()`        | All services + status                         |
| `service_status(name)`   | Status of one service                         |
| `service_start(name)`    | Start a service                               |
| `service_stop(name)`     | Stop a service                                |
| `service_restart(name)`  | Restart a service                             |
| `service_info(name)`     | Detailed info (version, PID, ports, paths)    |
| `system_overview()`      | Battery %, disk usage, uptime                 |
| `which_services_running()` | Just the names of running services          |

## Adding a new service

Drop a file in `services.d/<name>.sh` implementing:

```bash
#!/usr/bin/env bash
myservice_load() {
  SERVICE_DISPLAY_NAME="My Service"
  SERVICE_DESCRIPTION="What it does"
  CAPABILITIES=(status start stop restart)   # or just (status) for read-only
}

myservice_status() { echo "running" | "stopped" | "unknown"; }
myservice_start()  { ... ; }
myservice_stop()   { ... ; }
# restart defaults to stop + sleep 1 + start; override only if needed
myservice_info()   { printf '  Version: %s\n' "..."; }
```

No core code changes needed — `service-manager.sh` discovers it automatically.

## Transport options

Default: **stdio** (each agent session launches its own `uv run server.py`).
This matches how `basic-memory` and `headroom` are already wired into opencode.

Optional: **SSE/HTTP** for a shared long-lived instance. Edit the plist's
`ProgramArguments` to:

```
uv run __SERVER_PATH__ --transport sse --port 8790
```

Set `KeepAlive` to `true`, then point agents at `http://127.0.0.1:8790/sse`.

## State

- `~/.devbook-services/` — PID files, logs for managed background instances
- `/tmp/devbook-service-manager.{out,err}.log` — launchd daemon logs

## Safety notes

1. The `battery` adapter is read-only — no start/stop/restart.
2. The `docker` adapter is read-only — start/stop goes through `colima`.
3. `basic-memory` stop only kills the background instance started by this
   manager; agent-launched stdio instances are left alone.
4. `install.sh` always backs up `opencode.jsonc` before patching.
