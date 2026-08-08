#!/usr/bin/env bash
# Adapter: cloudflared — Cloudflare Tunnel daemon (launchd-managed).
# Capabilities: status, start, stop, restart.

cloudflared_load() {
  SERVICE_DISPLAY_NAME="Cloudflare Tunnel"
  SERVICE_DESCRIPTION="Cloudflare tunnel daemon (launchd: com.cloudflare.cloudflared)"
  CAPABILITIES=(status start stop restart)
}

CLOUDFLARED_PLIST="com.cloudflare.cloudflared"

cloudflared_status() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  # launchctl plist is loaded + process is alive
  if launchctl list "$CLOUDFLARED_PLIST" >/dev/null 2>&1 \
     && pgrep -f "cloudflared.*tunnel" >/dev/null 2>&1; then
    echo "running"
  else
    echo "stopped"
  fi
}

cloudflared_start() {
  command -v cloudflared >/dev/null 2>&1 || { echo "cloudflared not installed" >&2; return 1; }
  launchctl start "$CLOUDFLARED_PLIST" 2>/dev/null \
    || launchctl kickstart "gui/$(id -u)/${CLOUDFLARED_PLIST}" 2>/dev/null \
    || true
  # Wait briefly for it to come up
  for _ in 1 2 3 4 5; do
    pgrep -f "cloudflared.*tunnel" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
}

cloudflared_stop() {
  launchctl stop "$CLOUDFLARED_PLIST" 2>/dev/null || true
  # If still alive (e.g. launched outside launchd), kill directly
  pkill -f "cloudflared.*tunnel" 2>/dev/null || true
}

cloudflared_restart() {
  cloudflared_stop || true
  sleep 1
  cloudflared_start
}

cloudflared_info() {
  command -v cloudflared >/dev/null 2>&1 || { echo "  cloudflared binary not found"; return; }
  printf '  Version   : %s\n' "$(cloudflared --version 2>/dev/null)"
  printf '  Plist     : %s\n' "$CLOUDFLARED_PLIST"
  printf '  Plist path: %s/Library/LaunchAgents/%s.plist\n' "$HOME" "$CLOUDFLARED_PLIST"
  # Show active tunnel ingress hostnames if config exists
  local cfg="${HOME}/.cloudflared/config.yml"
  if [[ -f "$cfg" ]]; then
    printf '  Config    : %s\n' "$cfg"
    grep -E 'hostname:|url:' "$cfg" 2>/dev/null | sed 's/^/    /'
  fi
}
