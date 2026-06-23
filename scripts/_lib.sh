#!/usr/bin/env bash
# _lib.sh — shared helpers for pulse-build.sh and pulse-deploy.sh
# Source this file; do not execute directly.

# ── Colors ──────────────────────────────────────────────────────────────────
C_RED=$'\033[0;31m'
C_GRN=$'\033[0;32m'
C_YEL=$'\033[0;33m'
C_BLU=$'\033[0;34m'
C_CYN=$'\033[0;36m'
C_BLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RST=$'\033[0m'

info()    { printf '\n%s  %s%s\n' "${C_BLU}▶${C_RST}" "$*" "$C_RST"; }
ok()      { printf '%s  ✓  %s%s\n' "$C_GRN" "$*" "$C_RST"; }
warn()    { printf '%s  ⚠  %s%s\n' "$C_YEL" "$*" "$C_RST" >&2; }
die()     { printf '\n%s  ✗  %s%s\n\n' "$C_RED" "$*" "$C_RST" >&2; exit 1; }
section() { printf '\n%s%s  %s  %s%s\n' "$C_BLD" "$C_BLU" "$1" "$C_RST" ""; }

# ── fzf wrapper ─────────────────────────────────────────────────────────────
# Usage: pick <prompt> <item1> <item2> ...
# Returns the selected item on stdout; exits if the user cancels.
pick() {
  local prompt="$1"; shift
  local items=("$@")
  local result

  # Prefer fzf
  if command -v fzf >/dev/null 2>&1; then
    result=$(printf '%s\n' "${items[@]}" \
      | fzf --height=40% --layout=reverse --border=rounded \
            --prompt="  ${prompt}: " \
            --pointer="▶" \
            --color="prompt:cyan,pointer:cyan,hl:yellow,hl+:yellow" \
            --no-multi)
    [[ -n "$result" ]] || die "Nothing selected — aborted."
    echo "$result"
    return
  fi

  # Fallback: numbered list
  printf '\n%s%s%s\n' "$C_CYN" "$prompt" "$C_RST" >&2
  local i=1
  for item in "${items[@]}"; do
    printf '  %s%2d%s  %s\n' "$C_BLD" "$i" "$C_RST" "$item" >&2
    i=$((i + 1))
  done
  while true; do
    printf 'Enter number: ' >&2
    read -r n
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#items[@]} )); then
      echo "${items[$((n-1))]}"
      return
    fi
    warn "Invalid choice '$n'" >&2
  done
}

# ── Project discovery ────────────────────────────────────────────────────────
# Lists projects under WORKSPACE_ROOT that have a Dockerfile.
buildable_projects() {
  local root="$1"
  local projects=()
  while IFS= read -r dir; do
    local name
    name="$(basename "$(dirname "$dir")")"
    projects+=("$name")
  done < <(find "$root" -maxdepth 2 -name "Dockerfile" ! -path "*/.git/*" | sort)
  printf '%s\n' "${projects[@]}"
}

# Lists projects under WORKSPACE_ROOT that have deploy/workloads/*/clusters/aws/
deployable_projects() {
  local root="$1"
  # path depth: root/project/deploy/workloads/wl/clusters/aws = 6 levels below root
  find "$root" -maxdepth 6 -type d -name "aws" \
    ! -path "*/.git/*" \
    | grep "/deploy/workloads/.*/clusters/aws$" \
    | sed "s|${root}/||; s|/deploy/workloads.*||" \
    | sort -u
}

# Lists workloads for a given project that have a clusters/aws dir
project_workloads() {
  local project_dir="$1"
  find "${project_dir}/deploy/workloads" -maxdepth 4 -type d -name "aws" \
    ! -path "*/.git/*" \
    | grep "/clusters/aws$" \
    | sed 's|.*/workloads/||; s|/clusters/aws||' \
    | sort
}

# Lists Dockerfiles for a given project dir
project_dockerfiles() {
  local project_dir="$1"
  find "$project_dir" -maxdepth 1 -name "Dockerfile*" ! -path "*/.git/*" \
    | sed "s|${project_dir}/||" \
    | sort
}

# Lists git branches for a given project dir
project_branches() {
  local project_dir="$1"
  git -C "$project_dir" branch -a --format='%(refname:short)' 2>/dev/null \
    | sed 's|origin/||' \
    | sort -u \
    | grep -v '^HEAD$'
}

# ── Divider ──────────────────────────────────────────────────────────────────
divider() {
  printf '%s%s%s\n' "$C_DIM" "  ──────────────────────────────────────────────────────" "$C_RST"
}
