#!/usr/bin/env bash
# Installs the workspace pre-commit hook that keeps .gitignore in sync with
# cloned git repositories.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="${ROOT}/scripts/hooks/pre-commit"
HOOK_DST="${ROOT}/.git/hooks/pre-commit"

if [[ ! -d "${ROOT}/.git" ]]; then
    echo "error: ${ROOT} is not a git repository. Run: git init -b main" >&2
    exit 1
fi

install -m 755 "$HOOK_SRC" "$HOOK_DST"
echo "Installed pre-commit hook at ${HOOK_DST}"
