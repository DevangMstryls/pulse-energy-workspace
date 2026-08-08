#!/usr/bin/env bash
# Adapter: headroom — Headroom context-compression proxy + MCP server.
# Delegates to scripts/headroom.sh when present.
# Capabilities: status, start, stop, restart.

headroom_load() {
  SERVICE_DISPLAY_NAME="Headroom"
  SERVICE_DESCRIPTION="Headroom context-compression proxy (delegates to scripts/headroom.sh)"
  CAPABILITIES=(status start stop restart)
}

HEADROOM_SCRIPT="${SCRIPT_DIR}/../headroom.sh"
HEADROOM_BIN="/Users/devangmstryls/.pyenv/versions/3.10.12/bin/headroom"
HEADROOM_URL="http://127.0.0.1:8787"

headroom_status() {
  if ! curl -s --max-time 2 "${HEADROOM_URL}/health" >/dev/null 2>&1; then
    echo "stopped"
    return
  fi
  echo "running"
}

headroom_start() {
  if [[ -x "$HEADROOM_SCRIPT" ]]; then
    "$HEADROOM_SCRIPT" start
  else
    "$HEADROOM_BIN" proxy >/dev/null 2>&1 &
  fi
}

headroom_stop() {
  if [[ -x "$HEADROOM_SCRIPT" ]]; then
    "$HEADROOM_SCRIPT" stop
  else
    pkill -f "headroom.*proxy" 2>/dev/null || true
  fi
}

headroom_restart() {
  if [[ -x "$HEADROOM_SCRIPT" ]]; then
    "$HEADROOM_SCRIPT" restart
  else
    headroom_stop || true
    sleep 1
    headroom_start
  fi
}

headroom_info() {
  printf '  Proxy URL: %s\n' "$HEADROOM_URL"
  printf '  Binary   : %s\n' "$HEADROOM_BIN"
  printf '  Script   : %s\n' "$HEADROOM_SCRIPT"
  if curl -s --max-time 2 "${HEADROOM_URL}/health" >/dev/null 2>&1; then
    local health
    health="$(curl -s --max-time 2 "${HEADROOM_URL}/health" 2>/dev/null || echo '{}')"
    if command -v jq >/dev/null 2>&1; then
      printf '  Version  : %s\n' "$(echo "$health" | jq -r '.version // "?"')"
      printf '  Mode     : %s\n' "$(echo "$health" | jq -r '.mode // "?"')"
      printf '  Uptime   : %ss\n' "$(echo "$health" | jq -r '.uptime_seconds // "?"')"
    fi
  fi
}
