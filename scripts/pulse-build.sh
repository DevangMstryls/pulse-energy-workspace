#!/usr/bin/env bash
#
# pulse-build.sh — Interactive Docker build → push to ECR.
#
# Any flag you supply skips that prompt.  Run with no flags for a fully
# interactive walkthrough.  Pass all flags to use it non-interactively
# (e.g. from another script or CI fallback).
#
# Usage (interactive):
#   ./scripts/pulse-build.sh
#
# Usage (non-interactive / partial):
#   ./scripts/pulse-build.sh -p pulse-central -e staging
#   ./scripts/pulse-build.sh -p pulse-central -e production -b production -f ./Dockerfile.extended -y
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

# ── Defaults (overridable via env vars) ─────────────────────────────────────
ECR_ACCOUNT_ID="${ECR_ACCOUNT_ID:-366292523926}"
ECR_REGION="${ECR_REGION:-ap-south-1}"
ECR_PREFIX_STAGING="${ECR_REPO_PREFIX_STAGING:-pulse-energy-staging}"
ECR_PREFIX_PRODUCTION="${ECR_REPO_PREFIX_PRODUCTION:-pulse-energy-production}"
GH_BUILD_TOKEN="${GH_PAT:-${GITHUB_TOKEN:-}}"

# ── Argument parsing ─────────────────────────────────────────────────────────
PROJECT="" ENVIRONMENT="" BRANCH="" DOCKERFILE="" SERVICE=""
ECR_REPO_OVERRIDE="" ARCH="" TAG_OVERRIDE="" PUSH=true ASSUME_YES=false

usage() {
  cat <<EOF
pulse-build.sh — interactively (or via flags) build a project image and push to ECR

  Run with no arguments for a fully guided interactive mode.

Flags (each skips the corresponding prompt):
  -p, --project <name>     Project dir under workspace root  (e.g. pulse-central)
  -e, --env     <env>      staging | production
  -b, --branch  <ref>      Branch/commit to build from       (default: current HEAD)
  -f, --dockerfile <path>  Dockerfile to use                 (default: ./Dockerfile)
  -s, --service <name>     Service name for ECR repo         (default: project name)
      --ecr-repo <name>    Full ECR repo name override
      --arch <arch>        arm64 | amd64                     (default: arm64)
  -t, --tag <sha>          Override image tag                (default: 7-char short SHA)
      --no-push            Build locally only, do not push
  -y, --yes                Skip final confirmation prompt
  -h, --help

Env overrides: ECR_ACCOUNT_ID  ECR_REGION  ECR_REPO_PREFIX_STAGING
               ECR_REPO_PREFIX_PRODUCTION  GH_PAT  GITHUB_TOKEN
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)    PROJECT="$2";          shift 2 ;;
    -e|--env)        ENVIRONMENT="$2";      shift 2 ;;
    -b|--branch)     BRANCH="$2";           shift 2 ;;
    -f|--dockerfile) DOCKERFILE="$2";       shift 2 ;;
    -s|--service)    SERVICE="$2";          shift 2 ;;
    --ecr-repo)      ECR_REPO_OVERRIDE="$2";shift 2 ;;
    --arch)          ARCH="$2";             shift 2 ;;
    -t|--tag)        TAG_OVERRIDE="$2";     shift 2 ;;
    --no-push)       PUSH=false;            shift   ;;
    -y|--yes)        ASSUME_YES=true;       shift   ;;
    -h|--help)       usage 0 ;;
    *) die "Unknown argument: $1  (use -h for help)" ;;
  esac
done

# ── Dependency check ─────────────────────────────────────────────────────────
command -v docker >/dev/null || die "docker not found — install Docker Desktop"
command -v git    >/dev/null || die "git not found"
if ! command -v fzf >/dev/null 2>&1; then
  warn "fzf not found — falling back to numbered list selection.  Install with: brew install fzf"
fi

# ── Interactive prompts (only for missing values) ────────────────────────────
section "🔨  Pulse Build"

# 1. Project
if [[ -z "$PROJECT" ]]; then
  info "Select a project to build:"
  _projects=()
  while IFS= read -r _p; do _projects+=("$_p"); done < <(buildable_projects "$WORKSPACE_ROOT")
  PROJECT="$(pick "Project" "${_projects[@]}")"
fi
ok "Project: $PROJECT"

PROJECT_DIR="${WORKSPACE_ROOT}/${PROJECT}"
[[ -d "$PROJECT_DIR" ]] || die "Project dir not found: $PROJECT_DIR"

# 2. Environment
if [[ -z "$ENVIRONMENT" ]]; then
  info "Select target environment:"
  ENVIRONMENT="$(pick "Environment" "staging" "production")"
fi
ok "Environment: $ENVIRONMENT"

case "$ENVIRONMENT" in
  staging)    ECR_PREFIX="$ECR_PREFIX_STAGING";    BUILD_ENV="stg"  ;;
  production) ECR_PREFIX="$ECR_PREFIX_PRODUCTION"; BUILD_ENV="prod" ;;
  *) die "Invalid environment '$ENVIRONMENT' (expected: staging | production)" ;;
esac

# 3. Dockerfile
if [[ -z "$DOCKERFILE" ]]; then
  _dockerfiles=()
  while IFS= read -r _df; do _dockerfiles+=("$_df"); done < <(project_dockerfiles "$PROJECT_DIR")
  if [[ ${#_dockerfiles[@]} -eq 1 ]]; then
    DOCKERFILE="${_dockerfiles[0]}"
    ok "Dockerfile: $DOCKERFILE (only one found)"
  elif [[ ${#_dockerfiles[@]} -gt 1 ]]; then
    info "Select Dockerfile:"
    DOCKERFILE="$(pick "Dockerfile" "${_dockerfiles[@]}")"
  else
    DOCKERFILE="./Dockerfile"
    warn "No Dockerfile found in $PROJECT_DIR — defaulting to ./Dockerfile"
  fi
else
  ok "Dockerfile: $DOCKERFILE"
fi

# 4. Branch
if [[ -z "$BRANCH" ]]; then
  CURRENT_HEAD="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
  info "Select branch to build from (current: ${C_YEL}${CURRENT_HEAD}${C_RST}):"
  _branches=()
  while IFS= read -r _b; do _branches+=("$_b"); done < <(project_branches "$PROJECT_DIR")
  # Put current branch at top for fast selection
  _sorted_branches=("$CURRENT_HEAD")
  for b in "${_branches[@]}"; do [[ "$b" != "$CURRENT_HEAD" ]] && _sorted_branches+=("$b"); done
  BRANCH="$(pick "Branch" "${_sorted_branches[@]}")"
fi
ok "Branch: $BRANCH"

# 5. Architecture
if [[ -z "$ARCH" ]]; then
  info "Select build architecture:"
  ARCH="$(pick "Architecture" \
    "arm64  (default — Graviton EKS nodes)" \
    "amd64  (x86 — use only if needed)")"
  ARCH="${ARCH%% *}"   # strip description suffix
fi
ok "Architecture: $ARCH"

case "$ARCH" in
  arm64) PLATFORM="linux/arm64" ;;
  amd64) PLATFORM="linux/amd64" ;;
  *) die "Invalid arch '$ARCH' (expected: arm64 | amd64)" ;;
esac

# ── Resolve image identity ────────────────────────────────────────────────────
cd "$PROJECT_DIR"

# Checkout + update submodules
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  warn "Working tree is dirty — uncommitted local changes will be included in the build."
fi
info "Fetching origin/$BRANCH ..."
git fetch --quiet origin "$BRANCH" 2>/dev/null \
  || warn "Could not fetch origin/$BRANCH — building from local ref"
git checkout --quiet "$BRANCH"
git pull --quiet --ff-only origin "$BRANCH" 2>/dev/null || true

info "Updating git submodules..."
git submodule update --init --recursive --quiet \
  || warn "submodule update reported issues — continuing"

SERVICE="${SERVICE:-$PROJECT}"
TAG="${TAG_OVERRIDE:-$(git rev-parse --short=7 HEAD)}"
ECR_REPO="${ECR_REPO_OVERRIDE:-${ECR_PREFIX}_${SERVICE}}"
IMAGE_REPO="${ECR_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com/${ECR_REPO}"
IMAGE="${IMAGE_REPO}:${TAG}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# ── Build plan summary ────────────────────────────────────────────────────────
divider
printf '\n'
printf '  %s%-18s%s %s\n' "$C_BLD" "Project"     "$C_RST" "$PROJECT  ${C_DIM}(branch: $CURRENT_BRANCH)${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "Environment" "$C_RST" "$ENVIRONMENT  ${C_DIM}(build-arg ENV=$BUILD_ENV)${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "Dockerfile"  "$C_RST" "$DOCKERFILE"
printf '  %s%-18s%s %s\n' "$C_BLD" "Platform"    "$C_RST" "$PLATFORM"
printf '  %s%-18s%s %s\n' "$C_BLD" "Image tag"   "$C_RST" "${C_YEL}${TAG}${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "ECR image"   "$C_RST" "${C_CYN}${IMAGE}${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "Push to ECR" "$C_RST" "$PUSH"
printf '\n'
divider

# ── Confirm ──────────────────────────────────────────────────────────────────
if ! $ASSUME_YES; then
  if [[ "$ENVIRONMENT" == "production" ]]; then
    printf '\n%s  PRODUCTION build.%s  Confirm by typing the project name: ' "$C_YEL" "$C_RST"
    read -r _confirm
    [[ "$_confirm" == "$PROJECT" ]] || die "Confirmation did not match. Aborted."
  else
    printf '\n  Proceed with build? [y/N] '
    read -r _reply
    [[ "$_reply" =~ ^[Yy]$ ]] || die "Aborted."
  fi
fi

# ── ECR login + buildx ───────────────────────────────────────────────────────
BUILD_ARGS=(--build-arg "ENV=${BUILD_ENV}" --provenance=false)
[[ -n "$GH_BUILD_TOKEN" ]] && BUILD_ARGS+=(--build-arg "GITHUB_TOKEN=${GH_BUILD_TOKEN}")

if $PUSH; then
  $PUSH && { command -v aws >/dev/null || die "aws CLI not found — install it or use --no-push"; }
  info "Logging in to ECR (${ECR_REGION})..."
  aws ecr get-login-password --region "$ECR_REGION" \
    | docker login --username AWS --password-stdin \
        "${ECR_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com" \
        > /dev/null
  ok "ECR login successful"

  if ! docker buildx inspect pulse-builder >/dev/null 2>&1; then
    info "Creating buildx builder 'pulse-builder'..."
    docker buildx create --name pulse-builder --driver docker-container --use >/dev/null
  else
    docker buildx use pulse-builder
  fi
  OUTPUT_ARGS=(--push)
else
  OUTPUT_ARGS=(--load)
  warn "--no-push: image will be loaded into local Docker only."
fi

# ── Build ─────────────────────────────────────────────────────────────────────
info "Building ${C_CYN}${IMAGE}${C_RST} ..."
docker buildx build \
  --platform "$PLATFORM" \
  -f "$DOCKERFILE" \
  "${BUILD_ARGS[@]}" \
  -t "$IMAGE" \
  "${OUTPUT_ARGS[@]}" \
  .

ok "Build complete: ${C_CYN}${IMAGE}${C_RST}"

if $PUSH; then
  printf '\n%s  ✅  Image pushed.%s\n\n' "$C_GRN" "$C_RST"
  printf '  To deploy this image, run:\n\n'
  printf '  %s./scripts/pulse-deploy.sh -p %s -e %s -t %s%s\n\n' \
    "$C_CYN" "$PROJECT" "$ENVIRONMENT" "$TAG" "$C_RST"
fi
