#!/bin/bash
# Auto-format hook — runs prettier after file edits
# Trigger: PostToolUse (Write|Edit)

FILE_PATH="$1"

# Only format TypeScript/JavaScript/JSON files
if echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|json|css|md)$'; then
    # Check if npx is available and prettier is installed
    if command -v npx &>/dev/null; then
        # Find the nearest package.json to determine the project root
        DIR=$(dirname "$FILE_PATH")
        while [ "$DIR" != "/" ] && [ ! -f "$DIR/package.json" ]; do
            DIR=$(dirname "$DIR")
        done

        if [ -f "$DIR/package.json" ] && [ -f "$DIR/node_modules/.bin/prettier" ]; then
            cd "$DIR" && npx prettier --write "$FILE_PATH" 2>/dev/null
        fi
    fi
fi

exit 0
