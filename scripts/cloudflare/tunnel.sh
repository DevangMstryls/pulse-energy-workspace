#!/usr/bin/env bash
# tunnel.sh — Manage a Cloudflare Tunnel as a macOS LaunchAgent.
#
# ─────────────────────────────────────────────────────────────────────────────
# SETUP — edit these five variables before first use on a new machine:
# ─────────────────────────────────────────────────────────────────────────────
#
#  TUNNEL_NAME        The tunnel name shown in `cloudflared tunnel list`.
#                     Created once per machine via:
#                       cloudflared tunnel create <name>
#                     Example: "devang-devbook-pro"
#
#  TUNNEL_CREDS_FILE  Filename (not full path) of the credentials JSON that
#                     cloudflared writes to ~/.cloudflared/ when you run
#                     `cloudflared tunnel create`. It is named after the
#                     tunnel UUID, e.g. "05f0b843-2e97-485b-bbea-5867a81d8df1.json".
#                     Find yours with: ls ~/.cloudflared/*.json
#
#  STATUS_HOST        One public hostname from your ingress config to use as
#                     the health-check target in `tunnel.sh status`.
#                     Example: "devang-openchamber.pulseenergy.in"
#
#  VALIDATE_HOST      One public hostname from your ingress config to spot-check
#                     in `tunnel.sh validate`. Can be the same as STATUS_HOST.
#                     Example: "devang-openchamber.pulseenergy.in"
#
#  BACKEND_PORTS      Space-separated list of localhost ports that your ingress
#                     rules point to. Used by `tunnel.sh validate` to check
#                     whether each local backend is reachable.
#                     Example: "3000 7081 7082 8082 8092 8083"
#
# All five can also be overridden at runtime via environment variables:
#   TUNNEL_NAME=my-tunnel TUNNEL_CREDS_FILE=abc.json ./tunnel.sh start
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY LaunchAgent and not LaunchDaemon?
#   The Homebrew cloudflared binary is adhoc-signed only (no Apple TeamID).
#   macOS rejects adhoc-signed binaries in the system domain (LaunchDaemon)
#   with "Bootstrap failed: 5: Input/output error". The user GUI domain
#   (LaunchAgent) has no notarization requirement and needs no sudo.
# ─────────────────────────────────────────────────────────────────────────────
#
# Usage:
#   tunnel.sh install            Install/repair the LaunchAgent plist
#   tunnel.sh start              Install plist if needed and start the tunnel
#   tunnel.sh stop               Stop the tunnel
#   tunnel.sh restart            Restart without touching config
#   tunnel.sh reload             Reinstall plist if stale and restart
#   tunnel.sh status             Show process, connections, and health checks
#   tunnel.sh logs [-f] [-n N]   View service logs
#   tunnel.sh validate           Validate ingress config and local backends

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# ✏️  MACHINE-SPECIFIC CONFIGURATION — change these for each new machine
# ─────────────────────────────────────────────────────────────────────────────

# Tunnel name (from `cloudflared tunnel list` or `cloudflared tunnel create`)
TUNNEL_NAME="${TUNNEL_NAME:-devang-devbook-pro}"

# Credentials JSON filename inside ~/.cloudflared/
# Run `ls ~/.cloudflared/*.json` to find yours.
TUNNEL_CREDS_FILE="${TUNNEL_CREDS_FILE:-05f0b843-2e97-485b-bbea-5867a81d8df1.json}"

# Public hostname used for the HTTP health check in `status`
STATUS_HOST="${STATUS_HOST:-devang-openchamber.pulseenergy.in}"

# Public hostname spot-checked in `validate`
VALIDATE_HOST="${VALIDATE_HOST:-devang-openchamber.pulseenergy.in}"

# Space-separated localhost ports your ingress rules map to
# (used by `validate` to check whether local backends are up)
BACKEND_PORTS="${BACKEND_PORTS:-3000 7081 7082 8082 8092 8083}"

# ─────────────────────────────────────────────────────────────────────────────
# Paths — derived automatically, no need to edit
# ─────────────────────────────────────────────────────────────────────────────

SERVICE_LABEL="com.cloudflare.cloudflared"

# LaunchAgent plist location (user domain — no sudo, no notarization check)
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST="${LAUNCH_AGENTS_DIR}/${SERVICE_LABEL}.plist"

# cloudflared config and credentials (all kept in ~/.cloudflared/)
USER_CONFIG_DIR="${HOME}/.cloudflared"
USER_CONFIG="${USER_CONFIG_DIR}/config.yml"
CREDENTIALS_FILE="${USER_CONFIG_DIR}/${TUNNEL_CREDS_FILE}"

# Log files (writable by the current user, no sudo needed)
LOG_DIR="${HOME}/Library/Logs/cloudflared"
LOG_OUT="${LOG_DIR}/tunnel.out.log"
LOG_ERR="${LOG_DIR}/tunnel.err.log"

# Path to cloudflared binary (Homebrew default; override via env if different)
CLOUDFLARED="${CLOUDFLARED:-/opt/homebrew/bin/cloudflared}"

# Current user's UID — used to target the correct launchctl gui domain
GUI_UID="$(id -u)"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf '%b\n' "${GREEN}==>${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}warn:${NC} $*"; }
error() { printf '%b\n' "${RED}error:${NC} $*" >&2; }

service_loaded() {
  launchctl print "gui/${GUI_UID}/${SERVICE_LABEL}" &>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# install_plist — write the LaunchAgent plist using current variable values.
# Safe to re-run; rewrites the file in place.
# ─────────────────────────────────────────────────────────────────────────────
install_plist() {
  info "Installing LaunchAgent plist to ${PLIST}"
  mkdir -p "${LAUNCH_AGENTS_DIR}"
  mkdir -p "${LOG_DIR}"

  # Variables expanded here are intentional — the plist must contain
  # the resolved absolute paths, not shell variable names.
  cat > "${PLIST}" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>Label</key>
		<string>${SERVICE_LABEL}</string>
		<key>ProgramArguments</key>
		<array>
			<string>${CLOUDFLARED}</string>
			<string>tunnel</string>
			<string>--config</string>
			<string>${USER_CONFIG}</string>
			<string>run</string>
		</array>
		<key>RunAtLoad</key>
		<true/>
		<key>StandardOutPath</key>
		<string>${LOG_OUT}</string>
		<key>StandardErrorPath</key>
		<string>${LOG_ERR}</string>
		<key>KeepAlive</key>
		<dict>
			<key>SuccessfulExit</key>
			<false/>
		</dict>
		<key>ThrottleInterval</key>
		<integer>5</integer>
	</dict>
</plist>
PLIST_EOF

  chmod 644 "${PLIST}"
  info "Plist installed at ${PLIST}"
}

# Returns 0 if the plist exists and already points at the current USER_CONFIG.
# Fails (triggers reinstall) if the plist is missing, empty, or was generated
# for a different home directory / config path.
plist_is_valid() {
  [[ -f "${PLIST}" ]] && grep -q "${USER_CONFIG}" "${PLIST}" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────

cmd_start() {
  # Pre-flight: ensure config and credentials are present
  if [[ ! -f "${USER_CONFIG}" ]]; then
    error "Config not found: ${USER_CONFIG}"
    error "Create it with: cloudflared tunnel create ${TUNNEL_NAME}"
    exit 1
  fi
  if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    error "Credentials not found: ${CREDENTIALS_FILE}"
    error "Expected file: ${TUNNEL_CREDS_FILE}"
    error "Run: ls ~/.cloudflared/*.json  to find the correct filename"
    error "Then set TUNNEL_CREDS_FILE=<filename> in this script."
    exit 1
  fi

  # Install or repair plist if it's missing or points at a stale path
  if ! plist_is_valid; then
    warn "LaunchAgent plist missing or stale — installing it now"
    if service_loaded; then
      launchctl bootout "gui/${GUI_UID}/${SERVICE_LABEL}" || true
    fi
    install_plist
  fi

  if service_loaded; then
    info "Service already loaded; kickstarting ${SERVICE_LABEL}"
    launchctl kickstart -k "gui/${GUI_UID}/${SERVICE_LABEL}"
  else
    info "Loading and starting ${SERVICE_LABEL}"
    launchctl bootstrap "gui/${GUI_UID}" "${PLIST}"
  fi

  sleep 2
  cmd_status
}

cmd_stop() {
  if service_loaded; then
    info "Stopping ${SERVICE_LABEL}"
    launchctl bootout "gui/${GUI_UID}/${SERVICE_LABEL}"
  else
    warn "Service ${SERVICE_LABEL} is not loaded"
  fi

  # Kill any stray token-based cloudflared processes (from old setups)
  if pgrep -f "cloudflared tunnel run --token" >/dev/null 2>&1; then
    warn "Found token-based cloudflared process; stopping it"
    pkill -f "cloudflared tunnel run --token" || true
  fi
}

cmd_restart() {
  if service_loaded; then
    info "Restarting ${SERVICE_LABEL}"
    launchctl kickstart -k "gui/${GUI_UID}/${SERVICE_LABEL}"
  else
    cmd_start
  fi
}

cmd_reload() {
  info "Reloading config from ${USER_CONFIG}"
  # Reinstall plist in case CLOUDFLARED path or USER_CONFIG path changed
  if ! plist_is_valid; then
    warn "Plist stale — reinstalling before reload"
    install_plist
  fi
  cmd_restart
  info "Config reloaded"
}

cmd_status() {
  echo "Tunnel:  ${TUNNEL_NAME}"
  echo "Config:  ${USER_CONFIG}"
  echo "Creds:   ${CREDENTIALS_FILE}"
  echo

  echo "Processes:"
  if pgrep -fl cloudflared >/dev/null 2>&1; then
    pgrep -fl cloudflared | sed 's/^/  /'
  else
    echo "  (none running)"
  fi
  echo

  echo "Service (LaunchAgent gui/${GUI_UID}):"
  if service_loaded; then
    echo "  ${SERVICE_LABEL}: loaded"
    launchctl print "gui/${GUI_UID}/${SERVICE_LABEL}" 2>/dev/null \
      | grep -E "state|pid|last exit" | sed 's/^/  /' || true
  else
    echo "  ${SERVICE_LABEL}: not loaded"
  fi
  echo

  if [[ -x "${CLOUDFLARED}" ]]; then
    echo "Tunnel info:"
    "${CLOUDFLARED}" tunnel info "${TUNNEL_NAME}" 2>&1 | sed 's/^/  /' || true
    echo
  fi

  echo "Health checks (${STATUS_HOST}):"
  local code4 code6
  code4="$(curl -4 -s -o /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://${STATUS_HOST}/" 2>/dev/null || echo "fail")"
  code6="$(curl -6 -s -o /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://${STATUS_HOST}/" 2>/dev/null || echo "fail")"
  echo "  https://${STATUS_HOST}/ (IPv4): ${code4}"
  echo "  https://${STATUS_HOST}/ (IPv6): ${code6}"

  if [[ "${code4}" == "503" || "${code6}" == "503" ]]; then
    warn "503 — duplicate connectors? Check: pgrep -fl cloudflared"
  fi
  if [[ "${code4}" == "530" || "${code6}" == "530" ]]; then
    warn "530 — tunnel not running. Run: $0 start"
  fi
  if [[ "${code4}" == "502" || "${code6}" == "502" ]]; then
    warn "502 — tunnel is up but local backend (${STATUS_HOST}) is not running"
  fi
}

cmd_logs() {
  local follow=false
  local lines=50

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--follow) follow=true; shift ;;
      -n) lines="$2"; shift 2 ;;
      *) error "Unknown logs option: $1"; exit 1 ;;
    esac
  done

  if [[ ! -f "${LOG_ERR}" ]]; then
    error "Log file not found: ${LOG_ERR}"
    error "Has the tunnel been started at least once? Run: $0 start"
    exit 1
  fi

  info "Showing ${LOG_ERR}"
  if [[ "${follow}" == true ]]; then
    tail -f "${LOG_ERR}"
  else
    tail -n "${lines}" "${LOG_ERR}"
  fi
}

cmd_validate() {
  if [[ ! -f "${USER_CONFIG}" ]]; then
    error "Config not found: ${USER_CONFIG}"
    exit 1
  fi

  info "Validating ingress rules in ${USER_CONFIG}"
  "${CLOUDFLARED}" --config "${USER_CONFIG}" tunnel ingress validate

  echo
  info "Spot-checking ingress rule for https://${VALIDATE_HOST}"
  "${CLOUDFLARED}" --config "${USER_CONFIG}" tunnel ingress rule "https://${VALIDATE_HOST}"

  echo
  info "Checking local backend ports (${BACKEND_PORTS})"
  for port in ${BACKEND_PORTS}; do
    local http_code
    http_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 \
      "http://localhost:${port}/" 2>/dev/null || true)"
    if [[ "${http_code}" != "000" && -n "${http_code}" ]]; then
      printf "  Port %-5s %s\n" "${port}:" "${http_code}"
    else
      printf "  Port %-5s not reachable\n" "${port}:"
    fi
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install               Install/repair the LaunchAgent plist (no sudo needed)
  start                 Install plist if needed and start the tunnel
  stop                  Stop the tunnel
  restart               Restart the tunnel
  reload                Reinstall plist if stale and restart
  status                Show process, tunnel info, and HTTP health
  logs [-f] [-n N]      View stderr log (default: last 50 lines)
  validate              Validate ingress config and local backends

Environment overrides (can also be set at the top of this script):
  TUNNEL_NAME           Tunnel name            (current: ${TUNNEL_NAME})
  TUNNEL_CREDS_FILE     Credentials filename   (current: ${TUNNEL_CREDS_FILE})
  STATUS_HOST           Health-check hostname  (current: ${STATUS_HOST})
  VALIDATE_HOST         Validate hostname      (current: ${VALIDATE_HOST})
  BACKEND_PORTS         Backend port list      (current: ${BACKEND_PORTS})
  CLOUDFLARED           Binary path            (current: ${CLOUDFLARED})

Paths (auto-derived):
  Plist:   ${PLIST}
  Config:  ${USER_CONFIG}
  Logs:    ${LOG_ERR}

Docs: pulse-energy-docs/docs/guides/CLOUDFLARE_TUNNEL.md
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    install)  install_plist ;;
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_restart ;;
    reload)   cmd_reload ;;
    status)   cmd_status ;;
    logs)     cmd_logs "$@" ;;
    validate) cmd_validate ;;
    -h|--help|help|"") usage ;;
    *)
      error "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
