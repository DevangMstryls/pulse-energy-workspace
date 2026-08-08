#!/usr/bin/env bash
# Adapter: colima — macOS Docker runtime (manages the docker daemon).
# Capabilities: status, start, stop, restart.

colima_load() {
  SERVICE_DISPLAY_NAME="Colima"
  SERVICE_DESCRIPTION="macOS Docker runtime (manages docker daemon)"
  CAPABILITIES=(status start stop restart)
}

colima_status() {
  if ! command -v colima >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  # `colima status` exits 0 when running, non-zero when stopped
  if colima status 2>/dev/null | grep -q "Running"; then
    echo "running"
  else
    echo "stopped"
  fi
}

colima_start() {
  command -v colima >/dev/null 2>&1 || { echo "colima not installed" >&2; return 1; }
  colima start 2>&1
}

colima_stop() {
  command -v colima >/dev/null 2>&1 || return 0
  colima stop 2>&1
}

colima_restart() {
  command -v colima >/dev/null 2>&1 || return 1
  colima restart 2>&1
}

colima_info() {
  command -v colima >/dev/null 2>&1 || { echo "  colima binary not found"; return; }
  printf '  Version : %s\n' "$(colima version 2>/dev/null | head -1)"
  printf '  Profile : %s\n' "${COLIMA_PROFILE:-default}"
  if colima status 2>/dev/null | grep -q "Running"; then
    printf '  CPU/Mem : %s\n' "$(colima list 2>/dev/null | awk 'NR==2{print $3"/"$4}')"
  fi
}
