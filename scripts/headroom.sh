#!/usr/bin/env bash
#
# headroom.sh — Manage the Headroom context-compression proxy.
#
# Headroom compresses LLM traffic to save context and reduce API costs.
# The proxy runs locally at http://127.0.0.1:8787.
#
# Two run modes:
#   Foreground / nohup  — start/stop/restart (manual, current session)
#   Daemon (launchd)    — daemon-install / daemon-uninstall / daemon-status
#                         Runs automatically on login, survives reboots.
#
# Usage:
#   ./scripts/headroom.sh start             # Start proxy (nohup, current session)
#   ./scripts/headroom.sh stop              # Stop nohup proxy
#   ./scripts/headroom.sh restart           # Stop + start
#   ./scripts/headroom.sh status            # Proxy + MCP + savings health
#   ./scripts/headroom.sh logs              # Tail proxy log
#   ./scripts/headroom.sh stats             # Live proxy stats + savings summary
#
#   ./scripts/headroom.sh daemon-install    # Register as macOS launchd daemon
#   ./scripts/headroom.sh daemon-uninstall  # Remove launchd daemon
#   ./scripts/headroom.sh daemon-status     # Show launchd daemon state
#   ./scripts/headroom.sh daemon-restart    # Restart launchd daemon
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
HEADROOM_BIN="/Users/devangmstryls/.pyenv/versions/3.10.12/bin/headroom"
PROXY_HOST="127.0.0.1"
PROXY_PORT="8787"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
LOG_DIR="${HOME}/.headroom/logs"
LOG_FILE="${LOG_DIR}/proxy.log"
PID_FILE="${HOME}/.headroom/proxy.pid"
SAVINGS_FILE="${HOME}/.headroom/proxy_savings.json"
PLIST_LABEL="com.headroom.default"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
C_RED=$'\033[0;31m'
C_GRN=$'\033[0;32m'
C_YEL=$'\033[0;33m'
C_BLU=$'\033[0;34m'
C_CYN=$'\033[0;36m'
C_RST=$'\033[0m'
C_BLD=$'\033[1m'

info()    { printf '%s==>%s %s\n'   "$C_BLU" "$C_RST" "$*"; }
ok()      { printf '%s ✓ %s%s\n'    "$C_GRN" "$*" "$C_RST"; }
warn()    { printf '%s ⚠  %s%s\n'   "$C_YEL" "$*" "$C_RST" >&2; }
die()     { printf '%s ✗ %s%s\n'    "$C_RED" "$*" "$C_RST" >&2; exit 1; }
section() { printf '\n%s%s%s\n'     "$C_BLD" "$*" "$C_RST"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_bin() {
  [[ -x "$HEADROOM_BIN" ]] || die "headroom binary not found at $HEADROOM_BIN"
}

proxy_health() {
  curl -s --max-time 2 "${PROXY_URL}/health" >/dev/null 2>&1
}

proxy_pid_from_file() {
  [[ -f "$PID_FILE" ]] && cat "$PID_FILE" || echo ""
}

proxy_is_running() {
  local pid
  pid="$(proxy_pid_from_file)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  pgrep -f "headroom.*proxy" >/dev/null 2>&1
}

daemon_is_installed() {
  [[ -f "$PLIST_PATH" ]]
}

print_opencode_hint() {
  printf '\n'
  warn "opencode does not auto-route through the proxy."
  printf '    To enable full-session savings, launch opencode via:\n'
  printf '      %sANTHROPIC_BASE_URL=%s opencode%s\n' "$C_CYN" "$PROXY_URL" "$C_RST"
}

# ---------------------------------------------------------------------------
# Foreground / nohup commands
# ---------------------------------------------------------------------------

cmd_start() {
  check_bin

  if proxy_is_running && proxy_health; then
    ok "Proxy already running at ${PROXY_URL}"
    if daemon_is_installed; then
      printf '    (managed by launchd — use %sdaemon-restart%s to restart)\n' "$C_CYN" "$C_RST"
    fi
    return 0
  fi

  if daemon_is_installed; then
    warn "A launchd daemon is installed — starting via launchctl instead of nohup."
    launchctl kickstart -k "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null \
      || launchctl start "${PLIST_LABEL}" 2>/dev/null \
      || true
    sleep 1
    if proxy_health; then
      ok "Proxy started via launchd"
      print_opencode_hint
      return 0
    fi
    die "Proxy did not become healthy — check: ./scripts/headroom.sh daemon-status"
  fi

  mkdir -p "$LOG_DIR"
  info "Starting Headroom proxy on ${PROXY_URL} (nohup) ..."

  nohup "$HEADROOM_BIN" proxy > "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  local retries=10
  while (( retries-- > 0 )); do
    sleep 0.5
    if proxy_health; then
      ok "Proxy started  (pid ${pid})"
      printf '    Log : %s\n' "$LOG_FILE"
      printf '    URL : %s\n' "$PROXY_URL"
      printf '\n'
      warn "This process will stop when the terminal closes."
      printf '    For a persistent daemon that survives reboots:\n'
      printf '      %s./scripts/headroom.sh daemon-install%s\n' "$C_CYN" "$C_RST"
      print_opencode_hint
      return 0
    fi
  done

  die "Proxy did not become healthy after 5 s — check logs: $LOG_FILE"
}

cmd_stop() {
  if daemon_is_installed; then
    warn "A launchd daemon is installed. Stopping via launchctl (daemon stays registered)."
    printf '    To fully unregister: %s./scripts/headroom.sh daemon-uninstall%s\n' "$C_CYN" "$C_RST"
    launchctl stop "${PLIST_LABEL}" 2>/dev/null \
      || launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null \
      || true
    rm -f "$PID_FILE"
    ok "Daemon stopped (plist still installed — will restart on next login)"
    return 0
  fi

  local pid
  pid="$(proxy_pid_from_file)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    info "Stopping Headroom proxy (pid ${pid}) ..."
    kill "$pid"
    rm -f "$PID_FILE"
    ok "Proxy stopped"
  else
    local found_pids
    found_pids="$(pgrep -f "headroom.*proxy" 2>/dev/null || true)"
    if [[ -n "$found_pids" ]]; then
      info "Stopping Headroom proxy processes: ${found_pids} ..."
      echo "$found_pids" | xargs kill 2>/dev/null || true
      rm -f "$PID_FILE"
      ok "Proxy stopped"
    else
      warn "No running proxy found"
      rm -f "$PID_FILE"
    fi
  fi
}

cmd_restart() {
  cmd_stop || true
  sleep 1
  cmd_start
}

# ---------------------------------------------------------------------------
# Daemon (launchd) commands
# ---------------------------------------------------------------------------

cmd_daemon_install() {
  check_bin

  if daemon_is_installed; then
    ok "Daemon already installed: ${PLIST_PATH}"
    printf '    To reinstall cleanly: %s./scripts/headroom.sh daemon-uninstall%s then re-run\n' \
      "$C_CYN" "$C_RST"
    return 0
  fi

  info "Installing Headroom as a launchd user daemon ..."
  printf '    Plist : %s\n' "$PLIST_PATH"
  printf '    Port  : %s\n' "$PROXY_PORT"
  printf '    Mode  : token\n'
  printf '\n'

  "$HEADROOM_BIN" install apply \
    --preset persistent-service \
    --runtime python \
    --scope user \
    --port "$PROXY_PORT" \
    --mode token \
    --no-telemetry

  # Give launchd a moment to bootstrap and start the process
  sleep 2

  if proxy_health; then
    ok "Daemon installed and proxy is healthy at ${PROXY_URL}"
  else
    warn "Daemon installed but proxy not yet healthy — it may take a few seconds."
    printf '    Check: %s./scripts/headroom.sh daemon-status%s\n' "$C_CYN" "$C_RST"
  fi

  printf '\n'
  ok "Proxy will now start automatically on every login."
  print_opencode_hint
}

cmd_daemon_uninstall() {
  check_bin

  if ! daemon_is_installed; then
    warn "No launchd daemon found at ${PLIST_PATH}"
    return 0
  fi

  info "Removing Headroom launchd daemon ..."
  "$HEADROOM_BIN" install remove --profile default || true

  # Belt-and-suspenders: unload plist directly if the command didn't clean up
  if [[ -f "$PLIST_PATH" ]]; then
    launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
    rm -f "$PLIST_PATH"
  fi

  rm -f "$PID_FILE"
  ok "Daemon uninstalled. Proxy will no longer start on login."
}

cmd_daemon_restart() {
  check_bin

  if ! daemon_is_installed; then
    warn "No launchd daemon installed — use daemon-install first, or use 'restart' for nohup mode."
    return 1
  fi

  info "Restarting Headroom launchd daemon ..."
  "$HEADROOM_BIN" install restart --profile default 2>/dev/null \
    || launchctl kickstart -k "gui/$(id -u)/${PLIST_LABEL}"

  sleep 2
  if proxy_health; then
    ok "Daemon restarted and proxy is healthy at ${PROXY_URL}"
  else
    warn "Proxy not yet healthy — check: ./scripts/headroom.sh daemon-status"
  fi
}

cmd_daemon_status() {
  check_bin
  section "Headroom Daemon (launchd)"

  if daemon_is_installed; then
    ok "Plist installed: ${PLIST_PATH}"
    # launchctl print gives running state on macOS 10.15+
    local lc_out
    lc_out="$(launchctl print "gui/$(id -u)/${PLIST_LABEL}" 2>&1 || true)"
    if echo "$lc_out" | grep -q "state = running"; then
      printf '    %slaunchd state : running%s\n' "$C_GRN" "$C_RST"
    elif echo "$lc_out" | grep -q "state ="; then
      local state
      state="$(echo "$lc_out" | grep "state =" | head -1 | awk '{print $NF}')"
      printf '    launchd state : %s%s%s\n' "$C_YEL" "$state" "$C_RST"
    else
      printf '    launchd state : %s(unknown — run launchctl print gui/%s/%s)%s\n' \
        "$C_YEL" "$(id -u)" "$PLIST_LABEL" "$C_RST"
    fi

    # Show last exit code if available
    local exit_code
    exit_code="$(echo "$lc_out" | grep "last exit code" | awk '{print $NF}' || true)"
    [[ -n "$exit_code" ]] && printf '    last exit code : %s\n' "$exit_code"
  else
    printf '%s ✗ Not installed%s\n' "$C_RED" "$C_RST"
    printf '    Install: %s./scripts/headroom.sh daemon-install%s\n' "$C_CYN" "$C_RST"
  fi

  printf '\n'
  "$HEADROOM_BIN" install status 2>&1 | sed 's/^/    /'
}

# ---------------------------------------------------------------------------
# Status / logs / stats (shared)
# ---------------------------------------------------------------------------

cmd_status() {
  check_bin
  section "Headroom Status"

  # --- Proxy process ---
  printf '\n%sProxy%s  (%s)\n' "$C_BLD" "$C_RST" "${PROXY_URL}"
  if proxy_health; then
    local health_json
    health_json="$(curl -s --max-time 2 "${PROXY_URL}/health" 2>/dev/null || echo '{}')"
    ok "Running"
    if command -v jq >/dev/null 2>&1; then
      printf '    Version : %s\n' "$(echo "$health_json" | jq -r '.version // "unknown"')"
      printf '    Mode    : %s\n' "$(echo "$health_json" | jq -r '.mode // "unknown"')"
      printf '    Uptime  : %s s\n' "$(echo "$health_json" | jq -r '.uptime_seconds // "?"')"
    else
      printf '    %s\n' "$health_json"
    fi
    local pid
    pid="$(proxy_pid_from_file)"
    [[ -n "$pid" ]] && printf '    PID     : %s\n' "$pid"
    printf '    Log     : %s\n' "$LOG_FILE"
  else
    printf '%s ✗ Not running%s\n' "$C_RED" "$C_RST"
    if daemon_is_installed; then
      printf '    Daemon is installed — try: %s./scripts/headroom.sh daemon-restart%s\n' \
        "$C_CYN" "$C_RST"
    else
      printf '    Quick start : %s./scripts/headroom.sh start%s\n'         "$C_CYN" "$C_RST"
      printf '    Persistent  : %s./scripts/headroom.sh daemon-install%s\n' "$C_CYN" "$C_RST"
    fi
  fi

  # --- Daemon state ---
  printf '\n%sDaemon (launchd)%s\n' "$C_BLD" "$C_RST"
  if daemon_is_installed; then
    ok "Installed: ${PLIST_PATH}"
    local lc_state
    lc_state="$(launchctl print "gui/$(id -u)/${PLIST_LABEL}" 2>&1 | grep "state =" | head -1 | awk '{print $NF}' || true)"
    [[ -n "$lc_state" ]] && printf '    state : %s\n' "$lc_state"
  else
    printf '    %snot installed%s  (proxy will not survive logout)\n' "$C_YEL" "$C_RST"
    printf '    Install: %s./scripts/headroom.sh daemon-install%s\n' "$C_CYN" "$C_RST"
  fi

  # --- MCP server ---
  printf '\n%sMCP Server%s\n' "$C_BLD" "$C_RST"
  "$HEADROOM_BIN" mcp status 2>&1 | sed 's/^/    /'

  # --- Savings ---
  printf '\n%sSavings file%s\n' "$C_BLD" "$C_RST"
  if [[ -f "$SAVINGS_FILE" ]]; then
    ok "Found: $SAVINGS_FILE"
    if command -v jq >/dev/null 2>&1; then
      local tokens_saved usd_saved
      tokens_saved="$(jq -r '.lifetime.tokens_saved // 0' "$SAVINGS_FILE" 2>/dev/null || echo 0)"
      usd_saved="$(jq -r '.lifetime.compression_savings_usd // 0' "$SAVINGS_FILE" 2>/dev/null || echo 0)"
      printf '    Lifetime tokens saved : %s\n' "$tokens_saved"
      printf '    Lifetime cost saved   : $%s\n' "$usd_saved"
    fi
  else
    printf '    %s(no savings data yet)%s\n' "$C_YEL" "$C_RST"
  fi

  # --- opencode routing ---
  printf '\n%sopencode routing%s\n' "$C_BLD" "$C_RST"
  if proxy_health; then
    print_opencode_hint
  fi

  printf '\n'
}

cmd_logs() {
  if [[ ! -f "$LOG_FILE" ]]; then
    # Daemon logs via unified logging on macOS
    if daemon_is_installed; then
      info "Streaming launchd logs for ${PLIST_LABEL}  (Ctrl-C to stop)"
      log stream --predicate "subsystem == \"${PLIST_LABEL}\" OR process == \"headroom\"" \
        --level debug 2>/dev/null \
        || { warn "log stream failed — falling back to file"; tail -f "$LOG_FILE" 2>/dev/null || true; }
      return
    fi
    warn "No log file found at $LOG_FILE — has the proxy been started?"
    exit 1
  fi
  info "Tailing $LOG_FILE  (Ctrl-C to stop)"
  tail -f "$LOG_FILE"
}

cmd_stats() {
  check_bin

  if proxy_health; then
    section "Proxy Stats (live)"
    local stats_json
    stats_json="$(curl -s --max-time 5 "${PROXY_URL}/stats" 2>/dev/null || echo '{}')"
    if command -v jq >/dev/null 2>&1; then
      echo "$stats_json" | jq '.summary // .' 2>/dev/null || printf '%s\n' "$stats_json"
    else
      printf '%s\n' "$stats_json"
    fi
  else
    warn "Proxy not running — showing persisted savings file only"
  fi

  if [[ -f "$SAVINGS_FILE" ]]; then
    section "Persisted Savings  ($SAVINGS_FILE)"
    if command -v jq >/dev/null 2>&1; then
      jq '{
        lifetime,
        display_session,
        history_points: (.history | length)
      }' "$SAVINGS_FILE" 2>/dev/null || cat "$SAVINGS_FILE"
    else
      cat "$SAVINGS_FILE"
    fi
  else
    warn "No savings file yet — proxy has not processed any requests"
    printf '    Start: %s./scripts/headroom.sh daemon-install%s\n' "$C_CYN" "$C_RST"
    printf '    Then : %sANTHROPIC_BASE_URL=%s opencode%s\n' "$C_CYN" "$PROXY_URL" "$C_RST"
  fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF

${C_BLD}headroom.sh${C_RST} — Manage the Headroom context-compression proxy

${C_BLD}Usage:${C_RST}
  ./scripts/headroom.sh <command>

${C_BLD}Session commands${C_RST} (nohup — stops on logout):
  start             Start proxy in background (nohup)
  stop              Stop nohup proxy
  restart           Stop + start

${C_BLD}Daemon commands${C_RST} (launchd — survives logout & reboot):
  daemon-install    Register as macOS launchd user agent (auto-starts on login)
  daemon-uninstall  Remove launchd registration
  daemon-restart    Restart the launchd-managed proxy
  daemon-status     Show launchd daemon state

${C_BLD}Info commands:${C_RST}
  status            Proxy health + daemon state + MCP + savings
  logs              Tail proxy log (or launchd stream if daemonised)
  stats             Live proxy stats + persisted savings summary

${C_BLD}Paths:${C_RST}
  Proxy URL  : ${PROXY_URL}
  Log file   : ${LOG_FILE}
  PID file   : ${PID_FILE}
  Savings    : ${SAVINGS_FILE}
  Plist      : ${PLIST_PATH}

${C_BLD}Recommended setup (persistent):${C_RST}
  ./scripts/headroom.sh daemon-install
  ANTHROPIC_BASE_URL=${PROXY_URL} opencode

${C_BLD}Note:${C_RST} Without routing opencode through the proxy, headroom_stats
  only counts tokens from explicit headroom_compress calls — not total spend.

EOF
  exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMAND="${1:-}"

case "$COMMAND" in
  start)            cmd_start            ;;
  stop)             cmd_stop             ;;
  restart)          cmd_restart          ;;
  daemon-install)   cmd_daemon_install   ;;
  daemon-uninstall) cmd_daemon_uninstall ;;
  daemon-restart)   cmd_daemon_restart   ;;
  daemon-status)    cmd_daemon_status    ;;
  status)           cmd_status           ;;
  logs)             cmd_logs             ;;
  stats)            cmd_stats            ;;
  -h|--help|help|"") usage 0            ;;
  *) die "Unknown command: '$COMMAND' — run './scripts/headroom.sh --help'"  ;;
esac
