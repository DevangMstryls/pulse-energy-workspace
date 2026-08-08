#!/usr/bin/env bash
#
# service-manager.sh — Unified manager for local dev services / daemons / MCP servers.
#
# Modeled on scripts/headroom.sh. Each service is implemented as a sourced adapter
# in services.d/<name>.sh that exposes:
#   <name>_status   → echoes "running" | "stopped" | "unknown" + optional JSON via --json
#   <name>_start    → starts the service
#   <name>_stop     → stops the service
#   <name>_restart  → restarts the service (default: stop + sleep 1 + start)
#   <name>_info     → human-readable details (PID, port, version, etc.)
#
# Adapters may set a `CAPABILITIES` array (status, start, stop, restart) to declare
# what they support. Read-only services (e.g. battery) only declare "status".
#
# Usage:
#   ./service-manager.sh list [--json]
#   ./service-manager.sh status [<name>] [--json]
#   ./service-manager.sh start   <name>
#   ./service-manager.sh stop    <name>
#   ./service-manager.sh restart <name>
#   ./service-manager.sh info    <name>
#   ./service-manager.sh system                # battery, disk, mem, uptime snapshot
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="${SCRIPT_DIR}/services.d"
STATE_DIR="${HOME}/.devbook-services"
mkdir -p "$STATE_DIR"

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

info()    { printf '%s==>%s %s\n'   "$C_BLU" "$C_RST" "$*" 1>&2; }
ok()      { printf '%s ✓ %s%s\n'    "$C_GRN" "$*" "$C_RST" 1>&2; }
warn()    { printf '%s ⚠  %s%s\n'   "$C_YEL" "$*" "$C_RST" 1>&2; }
die()     { printf '%s ✗ %s%s\n'    "$C_RED" "$*" "$C_RST" 1>&2; exit 1; }
section() { printf '\n%s%s%s\n'     "$C_BLD" "$*" "$C_RST" 1>&2; }

# ---------------------------------------------------------------------------
# Adapter discovery
# ---------------------------------------------------------------------------

# List of registered service names (basenames of services.d/*.sh, sans extension).
discover_services() {
  local f name
  for f in "$SERVICES_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .sh)"
    echo "$name"
  done
}

# Bash function names cannot contain hyphens (or dots). Convert the service
# name to a valid identifier by replacing non-alphanumeric chars with `_`.
# e.g. "basic-memory" → "basic_memory", "my.svc" → "my_svc".
fn_name() {
  local name="$1" action="$2"
  local safe
  safe="$(echo "$name" | tr '.-' '__')"
  echo "${safe}_${action}"
}

# Source an adapter by name. After sourcing, the adapter is expected to have
# defined a `<name>_load` function (hyphens/dots replaced with `_`) that sets:
#   SERVICE_DISPLAY_NAME, SERVICE_DESCRIPTION, CAPABILITIES (array)
load_adapter() {
  local name="$1"
  local file="${SERVICES_DIR}/${name}.sh"
  [[ -f "$file" ]] || die "No adapter for service '$name' at $file"
  # shellcheck disable=SC1090
  source "$file"
  local load_fn
  load_fn="$(fn_name "$name" load)"
  if ! declare -F "$load_fn" >/dev/null 2>&1; then
    die "Adapter '$name' is missing a ${load_fn}() function"
  fi
  "$load_fn"
}

# Default restart implementation: stop + sleep + start. Adapters may override.
default_restart() {
  local name="$1"
  "$(fn_name "$name" stop)" || true
  sleep 1
  "$(fn_name "$name" start)"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_list() {
  local json=0
  [[ "${1:-}" == "--json" ]] && json=1

  local names
  names="$(discover_services)"
  if [[ -z "$names" ]]; then
    warn "No services registered in $SERVICES_DIR"
    return 0
  fi

    if (( json )); then
    printf '['
    local first=1
    while IFS= read -r name; do
      load_adapter "$name"
      local status
      status="$("$(fn_name "$name" status)" 2>/dev/null || echo "unknown")"
      (( first )) || printf ','
      first=0
      printf '{"name":"%s","display_name":"%s","status":"%s","capabilities":[%s]}' \
        "$name" "${SERVICE_DISPLAY_NAME:-$name}" "$status" \
        "$(printf '"%s",' "${CAPABILITIES[@]}" | sed 's/,$//')"
    done <<< "$names"
    printf ']\n'
  else
    section "Registered services"
    while IFS= read -r name; do
      load_adapter "$name"
      local status
      status="$("$(fn_name "$name" status)" 2>/dev/null || echo "unknown")"
      local color="$C_YEL"
      [[ "$status" == "running" ]] && color="$C_GRN"
      [[ "$status" == "stopped" ]] && color="$C_RED"
      printf '  %s%-15s%s %s%-10s%s  %s\n' \
        "$C_BLD" "$name" "$C_RST" "$color" "$status" "$C_RST" "${SERVICE_DESCRIPTION:-}"
    done <<< "$names"
  fi
}

cmd_status() {
  local name=""
  local json=0
  for arg in "$@"; do
    case "$arg" in
      --json) json=1 ;;
      *) name="$arg" ;;
    esac
  done

  if [[ -z "$name" ]]; then
    cmd_list $([[ $json -eq 1 ]] && echo --json)
    return
  fi

  load_adapter "$name"
  local status
  status="$("$(fn_name "$name" status)" 2>/dev/null || echo "unknown")"

  if (( json )); then
    printf '{"name":"%s","display_name":"%s","status":"%s","capabilities":[%s]}\n' \
      "$name" "${SERVICE_DISPLAY_NAME:-$name}" "$status" \
      "$(printf '"%s",' "${CAPABILITIES[@]}" | sed 's/,$//')"
  else
    local color="$C_YEL"
    [[ "$status" == "running" ]] && color="$C_GRN"
    [[ "$status" == "stopped" ]] && color="$C_RED"
    printf '%s%s%s: %s%s%s\n' "$C_BLD" "${SERVICE_DISPLAY_NAME:-$name}" "$C_RST" "$color" "$status" "$C_RST"
    if declare -F "$(fn_name "$name" info)" >/dev/null 2>&1; then
      "$(fn_name "$name" info)"
    fi
  fi
}

has_capability() {
  local name="$1" cap="$2"
  local c
  for c in "${CAPABILITIES[@]:-}"; do
    [[ "$c" == "$cap" ]] && return 0
  done
  return 1
}

cmd_action() {
  local action="$1" name="$2"
  [[ -z "$name" ]] && die "Usage: service-manager.sh $action <name>"
  load_adapter "$name"

  local fn
  case "$action" in
    start)   fn="$(fn_name "$name" start)" ;;
    stop)    fn="$(fn_name "$name" stop)" ;;
    restart) fn="$(fn_name "$name" restart)" ;;
    *)       die "Unknown action: $action" ;;
  esac

  if ! has_capability "$name" "$action"; then
    die "Service '$name' does not support '$action' (capabilities: ${CAPABILITIES[*]:-none})"
  fi

  if ! declare -F "$fn" >/dev/null 2>&1; then
    if [[ "$action" == "restart" ]]; then
      fn="default_restart"
    else
      die "Adapter '$name' is missing function $fn"
    fi
  fi

  if [[ "$fn" == "default_restart" ]]; then
    default_restart "$name"
  else
    "$fn"
  fi
}

cmd_info() {
  local name="$1"
  [[ -z "$name" ]] && die "Usage: service-manager.sh info <name>"
  load_adapter "$name"
  section "${SERVICE_DISPLAY_NAME:-$name}"
  printf '  Description : %s\n' "${SERVICE_DESCRIPTION:-}"
  printf '  Capabilities: %s\n' "${CAPABILITIES[*]:-none}"
  if declare -F "$(fn_name "$name" info)" >/dev/null 2>&1; then
    printf '\n'
    "$(fn_name "$name" info)"
  fi
}

cmd_system() {
  local json=0
  [[ "${1:-}" == "--json" ]] && json=1

  # Battery
  local batt_pct batt_state
  if batt_raw="$(pmset -g batt 2>/dev/null)"; then
    batt_pct="$(echo "$batt_raw" | grep -oE '[0-9]+%' | head -1 | tr -d '%')"
    if echo "$batt_raw" | grep -q 'AC Power'; then
      batt_state="charging"
    else
      batt_state="discharging"
    fi
  else
    batt_pct="?" ; batt_state="unknown"
  fi

  # Disk (root volume)
  local disk_used disk_total disk_pct
  disk_info="$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')"
  disk_pct="$(echo "$disk_info" | grep -oE '\([0-9]+%\)' | tr -d '()%')"

  # Memory
  local mem_used mem_total
  mem_info="$(vm_stat 2>/dev/null | awk 'NR==2{print $3}' | tr -d '.')"
  page_size=4096
  mem_total_raw="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"

  # Uptime
  local uptime
  uptime="$(uptime 2>/dev/null | sed 's/^.*up/up/')"

  if (( json )); then
    cat <<EOF
{"battery":{"percent":${batt_pct:-null},"state":"$batt_state"},"disk":{"used_total":"$disk_info","percent":${disk_pct:-null}},"uptime":"$(echo "$uptime" | tr -d '"')"}
EOF
  else
    section "System snapshot"
    printf '  Battery : %s%% (%s)\n' "$batt_pct" "$batt_state"
    printf '  Disk    : %s\n' "$disk_info"
    printf '  Uptime  : %s\n' "$uptime"
  fi
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF

${C_BLD}service-manager.sh${C_RST} — Unified manager for local dev services & daemons

${C_BLD}Usage:${C_RST}
  ./service-manager.sh <command> [args]

${C_BLD}Commands:${C_RST}
  list [--json]                List all registered services + status
  status [<name>] [--json]     Status of one service (or all if omitted)
  start   <name>               Start a service
  stop    <name>               Stop a service
  restart <name>               Restart a service
  info    <name>               Detailed info for a service
  system  [--json]             Battery, disk, uptime snapshot

${C_BLD}Adding a service:${C_RST}
  Drop a file in services.d/<name>.sh implementing:
    <name>_load      → set SERVICE_DISPLAY_NAME, SERVICE_DESCRIPTION, CAPABILITIES=()
    <name>_status    → echo "running" | "stopped" | "unknown"
    <name>_start     → (optional, if "start" in CAPABILITIES)
    <name>_stop      → (optional, if "stop" in CAPABILITIES)
    <name>_restart   → (optional; defaults to stop + start)
    <name>_info      → (optional) human-readable details

${C_BLD}State dir:${C_RST} $STATE_DIR
${C_BLD}Adapters dir:${C_RST} $SERVICES_DIR

EOF
  exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  list)    cmd_list "$@" ;;
  status)  cmd_status "$@" ;;
  start)   cmd_action start "$@" ;;
  stop)    cmd_action stop "$@" ;;
  restart) cmd_action restart "$@" ;;
  info)    cmd_info "$@" ;;
  system)  cmd_system "$@" ;;
  -h|--help|help|"") usage 0 ;;
  *) die "Unknown command: '$COMMAND' — run './service-manager.sh --help'" ;;
esac
