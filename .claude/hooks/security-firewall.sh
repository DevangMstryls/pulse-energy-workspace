#!/bin/bash
# Security firewall hook — blocks dangerous commands
# Trigger: PreToolUse (Bash|Write|Edit)

TOOL_NAME="$1"
INPUT="$2"

# Block dangerous bash commands
if [ "$TOOL_NAME" = "Bash" ]; then
    # Block rm -rf with broad patterns
    if echo "$INPUT" | grep -qE 'rm\s+-rf\s+/|rm\s+-rf\s+\*|rm\s+-rf\s+\.'; then
        echo "BLOCKED: Dangerous rm -rf command detected" >&2
        exit 2
    fi

    # Block force push
    if echo "$INPUT" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+-f\b'; then
        echo "BLOCKED: Force push is not allowed" >&2
        exit 2
    fi

    # Block --no-verify on git commands
    if echo "$INPUT" | grep -qE 'git\s+.*--no-verify'; then
        echo "BLOCKED: Skipping git hooks is not allowed" >&2
        exit 2
    fi

    # Block reading env files via cat/head/tail
    if echo "$INPUT" | grep -qE '(cat|head|tail|less|more)\s+.*\.(env|dev\.env|stg\.env|prod\.env)'; then
        echo "BLOCKED: Reading environment files directly is not allowed" >&2
        exit 2
    fi
fi

exit 0
