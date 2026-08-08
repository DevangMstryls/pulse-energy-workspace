#!/usr/bin/env bash
#
# install.sh — Install the Devbook Service Manager as:
#   1. A launchd user agent (auto-starts on login, pre-warms uv deps)
#   2. An MCP server registered in opencode.jsonc (stdio, per-session)
#
# Usage:
#   ./install.sh                 # install everything
#   ./install.sh --uninstall     # remove everything
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_FILE="${SCRIPT_DIR}/mcp-server/server.py"
PLIST_TEMPLATE="${SCRIPT_DIR}/com.devbook.service-manager.plist"
PLIST_LABEL="com.devbook.service-manager"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.jsonc"
MCP_NAME="devbook-service-manager"

C_GRN=$'\033[0;32m'; C_RED=$'\033[0;31m'; C_YEL=$'\033[0;33m'; C_RST=$'\033[0m'
ok()   { printf '%s ✓ %s%s\n' "$C_GRN" "$*" "$C_RST"; }
die()  { printf '%s ✗ %s%s\n' "$C_RED" "$*" "$C_RST" >&2; exit 1; }
warn() { printf '%s ⚠  %s%s\n' "$C_YEL" "$*" "$C_RST" >&2; }

UNINSTALL=0
[[ "${1:-}" == "--uninstall" ]] && UNINSTALL=1

# ---------------------------------------------------------------------------
# 1. launchd daemon
# ---------------------------------------------------------------------------

install_launchd() {
  command -v uv >/dev/null 2>&1 || die "uv not found at /opt/homebrew/bin/uv"
  [[ -f "$SERVER_FILE" ]]     || die "server.py not found at $SERVER_FILE"

  # Render plist with absolute server path
  local rendered
  rendered="$(sed "s|__SERVER_PATH__|${SERVER_FILE}|g" "$PLIST_TEMPLATE")"

  # Unload existing if present
  launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true

  mkdir -p "$(dirname "$PLIST_PATH")"
  echo "$rendered" > "$PLIST_PATH"
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
    launchctl load "$PLIST_PATH" 2>/dev/null || true

  ok "launchd daemon installed at $PLIST_PATH"
  printf '    (runs once on login to pre-warm uv deps; agents launch their own stdio instance)\n'
}

uninstall_launchd() {
  launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  ok "launchd daemon removed"
}

# ---------------------------------------------------------------------------
# 2. opencode.jsonc MCP registration
# ---------------------------------------------------------------------------

install_opencode() {
  [[ -f "$OPENCODE_CONFIG" ]] || { warn "opencode.jsonc not found at $OPENCODE_CONFIG — skipping MCP registration"; return 0; }

  # Idempotent: if already registered, skip
  if grep -q "\"${MCP_NAME}\"" "$OPENCODE_CONFIG" 2>/dev/null; then
    ok "${MCP_NAME} already registered in opencode.jsonc"
    return 0
  fi

  # Back up
  cp "$OPENCODE_CONFIG" "${OPENCODE_CONFIG}.bak-$(date +%Y%m%d%H%M%S)"

  # Insert the new MCP entry right after the opening of the "mcp" object.
  # We use python for safe JSONC handling (jsonc allows comments — fall back to text insertion).
  # Heredoc is quoted ('PY') to prevent shell expansion; vars passed via env.
  OPENCODE_CONFIG="$OPENCODE_CONFIG" SERVER_FILE="$SERVER_FILE" MCP_NAME="$MCP_NAME" python3 - <<'PY' || die "Failed to patch $OPENCODE_CONFIG"
import json, re, sys, os
from pathlib import Path

p = Path(os.environ["OPENCODE_CONFIG"])
text = p.read_text()
mcp_name = os.environ["MCP_NAME"]

entry = {
    "type": "local",
    "command": ["/opt/homebrew/bin/uv", "run", os.environ["SERVER_FILE"]],
    "enabled": True,
}

# Try parsing as strict JSON first (works if opencode.jsonc is actually JSON)
try:
    cfg = json.loads(text)
    cfg.setdefault("mcp", {})[mcp_name] = entry
    p.write_text(json.dumps(cfg, indent=2) + "\n")
    print("  patched via JSON parse")
    sys.exit(0)
except json.JSONDecodeError:
    pass

# Fall back to regex insertion after `"mcp": {` (handles comments / trailing commas)
pattern = re.compile(r'("mcp"\s*:\s*\{)')
new_block = (
    '\\1\n'
    f'    "{mcp_name}": {{\n'
    '      "type": "local",\n'
    f'      "command": ["/opt/homebrew/bin/uv", "run", "{entry["command"][2]}"],\n'
    '      "enabled": true\n'
    '    },'
)
new_text, n = pattern.subn(new_block, text, count=1)
if n == 0:
    print("  ERROR: could not find \"mcp\": { block", file=sys.stderr)
    sys.exit(1)
p.write_text(new_text)
print("  patched via regex (jsonc)")
PY
  ok "Registered '${MCP_NAME}' in $OPENCODE_CONFIG"
}

uninstall_opencode() {
  [[ -f "$OPENCODE_CONFIG" ]] || return 0
  if ! grep -q "\"${MCP_NAME}\"" "$OPENCODE_CONFIG" 2>/dev/null; then
    return 0
  fi
  cp "$OPENCODE_CONFIG" "${OPENCODE_CONFIG}.bak-uninstall-$(date +%Y%m%d%H%M%S)"
  # Remove the block (key + nested object, with optional trailing comma)
  OPENCODE_CONFIG="$OPENCODE_CONFIG" MCP_NAME="$MCP_NAME" python3 - <<'PY' || die "Failed to remove entry from $OPENCODE_CONFIG"
import re, os
from pathlib import Path
p = Path(os.environ["OPENCODE_CONFIG"])
text = p.read_text()
mcp_name = os.environ["MCP_NAME"]
text2 = re.sub(
    r'\n\s*"' + re.escape(mcp_name) + r'"\s*:\s*\{[^{}]*\},?',
    '',
    text,
    count=1,
)
p.write_text(text2)
PY
  ok "Removed '${MCP_NAME}' from $OPENCODE_CONFIG"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if (( UNINSTALL )); then
  uninstall_opencode
  uninstall_launchd
  ok "Devbook Service Manager uninstalled."
else
  install_launchd
  install_opencode
  ok "Devbook Service Manager installed."
  printf '\n  Next steps:\n'
  printf '    1. Restart opencode so it picks up the new MCP server.\n'
  printf '    2. Run: %s/scripts/services/service-manager.sh list%s to verify.\n' "$C_GRN" "$C_RST"
  printf '    3. In any agent session, call the `list_services` MCP tool.\n'
fi
