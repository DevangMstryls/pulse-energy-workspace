#!/usr/bin/env bash
# Adapter: battery — macOS battery read-only metric.
# Capabilities: status only (read-only — no start/stop/restart).

battery_load() {
  SERVICE_DISPLAY_NAME="Battery"
  SERVICE_DESCRIPTION="macOS battery (read-only)"
  CAPABILITIES=(status)
}

battery_status() {
  if ! pmset -g batt >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  # Report "running" if a battery is present, else "stopped"
  if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    echo "running"
  else
    echo "stopped"
  fi
}

battery_info() {
  local raw
  raw="$(pmset -g batt 2>/dev/null)"
  [[ -z "$raw" ]] && { echo "  pmset unavailable"; return; }
  local pct state
  pct="$(echo "$raw" | grep -oE '[0-9]+%' | head -1 | tr -d '%')"
  if echo "$raw" | grep -q 'AC Power'; then
    state="charging"
  else
    state="discharging"
  fi
  printf '  Percent : %s%%\n' "$pct"
  printf '  State   : %s\n' "$state"
  # Show time remaining line if present
  echo "$raw" | grep -oE '[0-9]+:[0-9]+ remaining' | sed 's/^/  Time    : /'
}
