#!/usr/bin/env bash
# Adapter: basic-memory — Basic Memory MCP server.
#
# basic-memory's MCP server is normally launched per-session by the agent client
# (opencode/Claude) via stdio — there is no long-lived daemon by default. This
# adapter reports the status of the most-recent stdio MCP process and offers
# start/stop only as a convenience wrapper around `basic-memory mcp serve` run
# in the background (NOT recommended for normal agent use).
#
# Capabilities: status, start, stop, restart.

basic_memory_load() {
  SERVICE_DISPLAY_NAME="Basic Memory"
  SERVICE_DESCRIPTION="Basic Memory MCP server (stdio; agent-managed by default)"
  CAPABILITIES=(status start stop restart)
}

BASIC_MEMORY_BIN="/Users/devangmstryls/.local/bin/basic-memory"
BASIC_MEMORY_PID_FILE="${STATE_DIR}/basic-memory.pid"
BASIC_MEMORY_LOG_FILE="${STATE_DIR}/basic-memory.log"

basic_memory_status() {
  if ! command -v basic-memory >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  local pid=""
  [[ -f "$BASIC_MEMORY_PID_FILE" ]] && pid="$(cat "$BASIC_MEMORY_PID_FILE")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "running"
    return
  fi
  # Also detect any agent-launched stdio instance (best-effort)
  if pgrep -f "basic-memory.*mcp" >/dev/null 2>&1; then
    echo "running"
    return
  fi
  echo "stopped"
}

basic_memory_start() {
  command -v basic-memory >/dev/null 2>&1 || { echo "basic-memory not installed" >&2; return 1; }
  warn "NOTE: agents normally launch basic-memory via stdio per session."
  warn "      This starts a long-lived background instance at ${BASIC_MEMORY_BIN} mcp serve."
  nohup "$BASIC_MEMORY_BIN" mcp serve --project pulse-memory \
    > "$BASIC_MEMORY_LOG_FILE" 2>&1 &
  echo $! > "$BASIC_MEMORY_PID_FILE"
}

basic_memory_stop() {
  local pid=""
  [[ -f "$BASIC_MEMORY_PID_FILE" ]] && pid="$(cat "$BASIC_MEMORY_PID_FILE")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    rm -f "$BASIC_MEMORY_PID_FILE"
    return
  fi
  # Only kill the background instance we started — never touch agent-launched stdio ones.
  warn "No managed background instance found (agent-launched stdio instances are left alone)."
}

basic_memory_restart() {
  basic_memory_stop || true
  sleep 1
  basic_memory_start
}

basic_memory_info() {
  command -v basic-memory >/dev/null 2>&1 || { echo "  basic-memory binary not found"; return; }
  printf '  Binary  : %s\n' "$BASIC_MEMORY_BIN"
  printf '  Version : %s\n' "$(basic-memory --version 2>/dev/null || echo '?')"
  printf '  Project : pulse-memory\n'
  printf '  PID file: %s\n' "$BASIC_MEMORY_PID_FILE"
  printf '  Log file: %s\n' "$BASIC_MEMORY_LOG_FILE"
}
