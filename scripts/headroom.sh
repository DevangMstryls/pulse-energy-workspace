#!/usr/bin/env bash
#
# headroom.sh — Manage the Headroom context-compression proxy.
#
# Headroom compresses LLM traffic to save context and reduce API costs.
# The proxy runs locally at http://127.0.0.1:8787 and must be started
# before opencode (or any other tool) can route traffic through it.
#
# Usage:
#   ./scripts/headroom.sh start      # Start proxy in background (persistent)
#   ./scripts/headroom.sh stop       # Stop background proxy
#   ./scripts/headroom.sh restart    # Stop then start
#   ./scripts/headroom.sh status     # Check proxy + MCP server health
#   ./scripts/headroom.sh logs       # Tail proxy log
#   ./scripts/headroom.sh stats      # Show saved proxy_savings.json summary
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

info()    { printf '%s==>%s %s\n'      "$C_BLU" "$C_RST" "$*"; }
ok()      { printf '%s ✓ %s%s\n'       "$C_GRN" "$*" "$C_RST"; }
warn()    { printf '%s ⚠  %s%s\n'      "$C_YEL" "$*" "$C_RST" >&2; }
die()     { printf '%s ✗ %s%s\n'       "$C_RED" "$*" "$C_RST" >&2; exit 1; }
section() { printf '\n%s%s%s\n'        "$C_BLD" "$*" "$C_RST"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_bin() {
  [[ -x "$HEADROOM_BIN" ]] || die "headroom binary not found at $HEADROOM_BIN"
}

proxy_health() {
  # Returns 0 if proxy responds to /health, 1 otherwise.
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
  # Fallback: check if any headroom proxy process is alive
  pgrep -f "headroom.*proxy" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_start() {
  check_bin

  if proxy_is_running && proxy_health; then
    ok "Proxy is already running at ${PROXY_URL}"
    return 0
  fi

  mkdir -p "$LOG_DIR"
  info "Starting Headroom proxy on ${PROXY_URL} ..."

  nohup "$HEADROOM_BIN" proxy \
    > "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  # Wait up to 5 s for the proxy to become healthy
  local retries=10
  while (( retries-- > 0 )); do
    sleep 0.5
    if proxy_health; then
      ok "Proxy started  (pid ${pid})"
      printf '    Log : %s\n' "$LOG_FILE"
      printf '    URL : %s\n' "$PROXY_URL"
      printf '\n'
      warn "opencode does not auto-route through the proxy."
      printf '    To enable full-session savings set:\n'
      printf '      %sANTHROPIC_BASE_URL=%s%s\n' "$C_CYN" "$PROXY_URL" "$C_RST"
      printf '    before launching opencode.\n'
      return 0
    fi
  done

  die "Proxy did not become healthy after 5 s — check logs: $LOG_FILE"
}

cmd_stop() {
  local pid
  pid="$(proxy_pid_from_file)"

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    info "Stopping Headroom proxy (pid ${pid}) ..."
    kill "$pid"
    rm -f "$PID_FILE"
    ok "Proxy stopped"
  else
    # Try killing by process name as fallback
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

cmd_status() {
  check_bin
  section "Headroom Status"

  # --- Proxy ---
  printf '\n%sProxy%s  (%s)\n' "$C_BLD" "$C_RST" "${PROXY_URL}"
  if proxy_health; then
    local health_json
    health_json="$(curl -s --max-time 2 "${PROXY_URL}/health" 2>/dev/null || echo '{}')"
    ok "Running"
    # Print key fields if jq available
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
    printf '    Start it: %s./scripts/headroom.sh start%s\n' "$C_CYN" "$C_RST"
  fi

  # --- MCP server ---
  printf '\n%sMCP Server%s\n' "$C_BLD" "$C_RST"
  local mcp_status
  mcp_status="$("$HEADROOM_BIN" mcp status 2>&1 || true)"
  printf '%s\n' "$mcp_status" | sed 's/^/    /'

  # --- Savings file ---
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
    printf '    %s(no savings data yet — proxy has not processed any requests)%s\n' "$C_YEL" "$C_RST"
  fi

  # --- opencode routing note ---
  printf '\n%sopencode routing%s\n' "$C_BLD" "$C_RST"
  if proxy_health; then
    warn "opencode does not auto-route through the proxy."
    printf '    Set %sANTHROPIC_BASE_URL=%s%s before launching opencode\n' \
      "$C_CYN" "$PROXY_URL" "$C_RST"
    printf '    to enable full-session automatic compression.\n'
  fi

  printf '\n'
}

cmd_logs() {
  if [[ ! -f "$LOG_FILE" ]]; then
    warn "No log file found at $LOG_FILE — has the proxy been started?"
    exit 1
  fi
  info "Tailing $LOG_FILE  (Ctrl-C to stop)"
  tail -f "$LOG_FILE"
}

cmd_stats() {
  check_bin

  # Show live proxy stats if running
  if proxy_health; then
    section "Proxy Stats (live)"
    local stats_json
    stats_json="$(curl -s --max-time 5 "${PROXY_URL}/stats" 2>/dev/null || echo '{}')"
    if command -v jq >/dev/null 2>&1; then
      # Pretty-print the summary block
      echo "$stats_json" | jq '.summary // .' 2>/dev/null || printf '%s\n' "$stats_json"
    else
      printf '%s\n' "$stats_json"
    fi
  else
    warn "Proxy not running — showing persisted savings file only"
  fi

  # Always show persisted savings
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
    printf '    Start the proxy and route traffic through it:\n'
    printf '      %s./scripts/headroom.sh start%s\n' "$C_CYN" "$C_RST"
    printf '      %sANTHROPIC_BASE_URL=%s opencode%s\n' "$C_CYN" "$PROXY_URL" "$C_RST"
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

${C_BLD}Commands:${C_RST}
  start      Start proxy in background, write PID to ~/.headroom/proxy.pid
  stop       Stop background proxy
  restart    Stop + start
  status     Show proxy health, MCP server state, and lifetime savings
  logs       Tail the proxy log  (${LOG_FILE})
  stats      Show live proxy stats + persisted savings summary

${C_BLD}Proxy URL:${C_RST}  ${PROXY_URL}
${C_BLD}Log file:${C_RST}   ${LOG_FILE}
${C_BLD}PID file:${C_RST}   ${PID_FILE}
${C_BLD}Savings:${C_RST}    ${SAVINGS_FILE}

${C_BLD}To enable full-session savings in opencode:${C_RST}
  1. Start the proxy:     ./scripts/headroom.sh start
  2. Launch opencode with: ANTHROPIC_BASE_URL=${PROXY_URL} opencode

${C_BLD}Note:${C_RST} Without the proxy, headroom_stats only counts tokens from
  explicit headroom_compress MCP tool calls — not total conversation spend.

EOF
  exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMAND="${1:-}"

case "$COMMAND" in
  start)   cmd_start   ;;
  stop)    cmd_stop    ;;
  restart) cmd_restart ;;
  status)  cmd_status  ;;
  logs)    cmd_logs    ;;
  stats)   cmd_stats   ;;
  -h|--help|help|"") usage 0 ;;
  *) die "Unknown command: '$COMMAND' — run './scripts/headroom.sh --help'" ;;
esac
