#!/usr/bin/env bash
#
# pulse-deploy.sh — Interactive GitOps deploy (ArgoCD writeback).
#
# Any flag you supply skips that prompt.  Run with no flags for a fully
# interactive walkthrough.  Pass all flags to use it non-interactively.
#
# Usage (interactive):
#   ./scripts/pulse-deploy.sh
#
# Usage (non-interactive / partial):
#   ./scripts/pulse-deploy.sh -p pulse-central -w pulse-central-app-api-wl -e staging -t 407414d
#   ./scripts/pulse-deploy.sh -p pulse-central -w pulse-central-cron-wl -e production
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

DEFAULT_REGION="${ECR_REGION:-ap-south-1}"

# ── Argument parsing ─────────────────────────────────────────────────────────
PROJECT="" WORKLOAD="" ENVIRONMENT="" TAG="" COMMIT_MSG=""
VALIDATE=true PUSH=true ASSUME_YES=false

usage() {
  cat <<EOF
pulse-deploy.sh — interactively (or via flags) deploy a workload via ArgoCD writeback

  Run with no arguments for a fully guided interactive mode.

Flags (each skips the corresponding prompt):
  -p, --project  <name>   Project dir containing deploy/workloads  (e.g. pulse-central)
  -w, --workload <name>   Workload dir name                        (e.g. pulse-central-app-api-wl)
  -e, --env      <env>    staging | production
  -t, --tag      <sha>    7-char image tag                         (default: latest in ECR)
  -m, --message  <msg>    Git commit message override
      --no-validate       Skip "tag exists in ECR" check
      --no-push           Commit locally but do not git push
  -y, --yes               Skip confirmation prompt
  -h, --help

Env overrides: ECR_REGION
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)  PROJECT="$2";     shift 2 ;;
    -w|--workload) WORKLOAD="$2";    shift 2 ;;
    -e|--env)      ENVIRONMENT="$2"; shift 2 ;;
    -t|--tag)      TAG="$2";         shift 2 ;;
    -m|--message)  COMMIT_MSG="$2";  shift 2 ;;
    --no-validate) VALIDATE=false;   shift   ;;
    --no-push)     PUSH=false;       shift   ;;
    -y|--yes)      ASSUME_YES=true;  shift   ;;
    -h|--help)     usage 0 ;;
    *) die "Unknown argument: $1  (use -h for help)" ;;
  esac
done

# ── Dependency check ─────────────────────────────────────────────────────────
command -v git >/dev/null || die "git not found"
if ! command -v fzf >/dev/null 2>&1; then
  warn "fzf not found — falling back to numbered list selection.  Install with: brew install fzf"
fi

# ── Interactive prompts (only for missing values) ────────────────────────────
section "🚀  Pulse Deploy"

# 1. Project
if [[ -z "$PROJECT" ]]; then
  info "Select a project to deploy:"
  _projects=()
  while IFS= read -r _p; do _projects+=("$_p"); done < <(deployable_projects "$WORKSPACE_ROOT")
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
  staging|production) ;;
  *) die "Invalid environment '$ENVIRONMENT' (expected: staging | production)" ;;
esac

# 3. Workload
if [[ -z "$WORKLOAD" ]]; then
  _workloads=()
  while IFS= read -r _wl; do _workloads+=("$_wl"); done < <(project_workloads "$PROJECT_DIR")
  [[ ${#_workloads[@]} -gt 0 ]] || die "No workloads found in $PROJECT_DIR/deploy/workloads/"
  info "Select workload to deploy:"
  WORKLOAD="$(pick "Workload" "${_workloads[@]}")"
fi
ok "Workload: $WORKLOAD"

# Resolve manifest path (source of truth)
REL_TARGET="deploy/workloads/${WORKLOAD}/clusters/aws/${ENVIRONMENT}.yaml"
TARGET="${PROJECT_DIR}/${REL_TARGET}"
[[ -f "$TARGET" ]] || die "Manifest not found: ${PROJECT_DIR}/${REL_TARGET}"

# ── Parse ECR details from the manifest ──────────────────────────────────────
REPO_LINE="$(grep -E '^[[:space:]]*repository:[[:space:]]*' "$TARGET" \
  | head -1 | sed -E 's/.*repository:[[:space:]]*//; s/["'"'"']//g' | xargs || true)"
[[ -n "$REPO_LINE" ]] || die "Could not find image.repository in $REL_TARGET"
ECR_REPO="${REPO_LINE##*/}"
REGION="$(printf '%s' "$REPO_LINE" \
  | sed -nE 's/.*\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com.*/\1/p')"
REGION="${REGION:-$DEFAULT_REGION}"
PREV_TAG="$(grep -E '^[[:space:]]*tag:[[:space:]]*' "$TARGET" \
  | head -1 | sed -E 's/.*tag:[[:space:]]*//; s/["'"'"']//g' | xargs || true)"

# 4. Image tag
if [[ -z "$TAG" ]]; then
  if $VALIDATE && command -v aws >/dev/null 2>&1; then
    info "Fetching recent tags from ECR  ${C_DIM}(${ECR_REPO})${C_RST}..."
    _ecr_tags=()
    while IFS= read -r _t; do _ecr_tags+=("$_t"); done < <(
      aws ecr describe-images \
        --repository-name "$ECR_REPO" \
        --region "$REGION" \
        --query 'sort_by(imageDetails[?imageTags!=`null`], &imagePushedAt)[-15:].imageTags[0]' \
        --output text 2>/dev/null \
        | tr '\t' '\n' \
        | grep -E '^[0-9a-f]{7}$' \
        | tail -r \
      || true
    )
    if [[ ${#_ecr_tags[@]} -gt 0 ]]; then
      # Add a "type manually" option at the bottom
      _ecr_tags+=("  ── enter manually ──")
      info "Select image tag to deploy  ${C_DIM}(most recent first)${C_RST}:"
      TAG="$(pick "Image tag" "${_ecr_tags[@]}")"
      if [[ "$TAG" == *"enter manually"* ]]; then
        printf '  Enter 7-char SHA: '
        read -r TAG
        TAG="$(echo "$TAG" | xargs)"
      fi
    else
      warn "No tagged images found in ECR — enter tag manually."
      printf '  Enter 7-char SHA: '
      read -r TAG
      TAG="$(echo "$TAG" | xargs)"
    fi
  else
    printf '\n  Enter 7-char image tag (SHA): '
    read -r TAG
    TAG="$(echo "$TAG" | xargs)"
  fi
fi
ok "Image tag: ${C_YEL}${TAG}${C_RST}"

# ── Validate ──────────────────────────────────────────────────────────────────
echo "$TAG" | grep -qE '^[0-9a-f]{7}$' \
  || die "Invalid tag '${TAG}'. Must be a 7-char hex SHA (e.g. 407414d)."

if $VALIDATE && command -v aws >/dev/null 2>&1; then
  info "Verifying '$TAG' exists in ECR repo '$ECR_REPO'..."
  FOUND="$(aws ecr describe-images \
    --repository-name "$ECR_REPO" --region "$REGION" \
    --image-ids imageTag="$TAG" \
    --query 'imageDetails[0].imageTags[0]' --output text 2>&1 || true)"
  if [[ "$FOUND" == *Exception* || "$FOUND" == "None" || -z "$FOUND" ]]; then
    warn "Recent tags available in ${ECR_REPO}:"
    aws ecr describe-images --repository-name "$ECR_REPO" --region "$REGION" \
      --query 'sort_by(imageDetails[?imageTags!=`null`], &imagePushedAt)[-8:].imageTags[0]' \
      --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' \
      | while read -r t; do printf '    %s- %s%s\n' "$C_DIM" "$t" "$C_RST"; done
    die "Tag '$TAG' not found in ECR. Build it first with pulse-build.sh."
  fi
  ok "Tag verified in ECR"
fi

# ── Deploy plan summary ───────────────────────────────────────────────────────
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"

divider
printf '\n'
printf '  %s%-18s%s %s\n' "$C_BLD" "Project"     "$C_RST" "$PROJECT  ${C_DIM}(branch: $CURRENT_BRANCH)${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "Environment" "$C_RST" "$ENVIRONMENT"
printf '  %s%-18s%s %s\n' "$C_BLD" "Workload"    "$C_RST" "$WORKLOAD"
printf '  %s%-18s%s %s\n' "$C_BLD" "Manifest"    "$C_RST" "${C_DIM}$REL_TARGET${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "ECR repo"    "$C_RST" "${ECR_REPO}  ${C_DIM}($REGION)${C_RST}"
printf '  %s%-18s%s %s  →  %s\n' \
  "$C_BLD" "Tag change" "$C_RST" \
  "${C_DIM}${PREV_TAG:-<none>}${C_RST}" \
  "${C_YEL}${TAG}${C_RST}"
printf '  %s%-18s%s %s\n' "$C_BLD" "Git push"    "$C_RST" "$PUSH  ${C_DIM}(ArgoCD syncs on push)${C_RST}"
printf '\n'
divider

[[ "$PREV_TAG" == "$TAG" ]] \
  && warn "Tag is already set to '${TAG}' — no change will be committed."

# ── Confirm ───────────────────────────────────────────────────────────────────
if ! $ASSUME_YES; then
  if [[ "$ENVIRONMENT" == "production" ]]; then
    printf '\n%s  ⚠  PRODUCTION deploy.%s  Type the workload name to confirm: ' "$C_YEL" "$C_RST"
    read -r _confirm
    [[ "$_confirm" == "$WORKLOAD" ]] || die "Confirmation did not match. Aborted."
  else
    printf '\n  Proceed with deploy? [y/N] '
    read -r _reply
    [[ "$_reply" =~ ^[Yy]$ ]] || die "Aborted."
  fi
fi

# ── Write tag into manifest ───────────────────────────────────────────────────
cd "$PROJECT_DIR"
perl -i -pe 's/^(\s*)tag:.*/${1}tag: "'"$TAG"'"/' "$TARGET"
ok "Updated ${REL_TARGET}"

if [[ -z "$(git status --porcelain -- "$REL_TARGET")" ]]; then
  warn "No file change to commit (tag was already '$TAG')."
  exit 0
fi

# ── Commit ────────────────────────────────────────────────────────────────────
REPO_URL="$(git remote get-url origin 2>/dev/null \
  | sed -E 's#git@github.com:#https://github.com/#; s#\.git$##' || echo '')"
MSG="${COMMIT_MSG:-chore(deploy): manual deploy — ${WORKLOAD} to ${TAG} (${ENVIRONMENT})}"
if [[ -n "$PREV_TAG" && "$PREV_TAG" != "placeholder" && "$PREV_TAG" != "$TAG" && -n "$REPO_URL" ]]; then
  MSG="${MSG}

Changes: ${REPO_URL}/compare/${PREV_TAG}...${TAG}"
fi

git add "$REL_TARGET"
git commit --quiet -m "$MSG"
ok "Committed on branch '${CURRENT_BRANCH}'"

# ── Push ──────────────────────────────────────────────────────────────────────
if $PUSH; then
  info "Pushing to origin/${CURRENT_BRANCH} ..."
  for _attempt in 1 2 3; do
    if git push --quiet origin "HEAD:${CURRENT_BRANCH}"; then
      printf '\n%s  ✅  Deployed!%s\n\n' "$C_GRN" "$C_RST"
      printf '  %s%-18s%s %s\n' "$C_BLD" "Workload"  "$C_RST" "$WORKLOAD"
      printf '  %s%-18s%s %s\n' "$C_BLD" "Tag"       "$C_RST" "${C_YEL}${TAG}${C_RST}"
      printf '  %s%-18s%s %s\n' "$C_BLD" "ArgoCD"    "$C_RST" "will sync ${ENVIRONMENT} shortly"
      printf '\n'
      break
    fi
    warn "Push failed (attempt ${_attempt}/3) — rebasing and retrying..."
    git pull --quiet --rebase origin "$CURRENT_BRANCH" || true
    [[ $_attempt -eq 3 ]] && die "Push failed after 3 attempts."
  done
else
  warn "--no-push: commit is local only. ArgoCD will not sync until you git push."
fi
