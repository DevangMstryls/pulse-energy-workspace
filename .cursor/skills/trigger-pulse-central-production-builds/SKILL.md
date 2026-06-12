---
name: trigger-pulse-central-production-builds
description: Triggers pulse-central production Docker builds and EKS workload deploys via GitHub Actions (build, build-and-deploy, deploy-workload). Use when the user asks to build, deploy, release, or roll back pulse-central in production, trigger CI/CD, push an image to ECR, or update a production workload tag.
---

# Trigger pulse-central Production Builds

Production deploys for `Pulse-Energy/pulse-central` use GitHub Actions + ECR + GitOps (ArgoCD). Images land in `366292523926.dkr.ecr.ap-south-1.amazonaws.com/pulse-energy-production_pulse-central`.

## Prerequisites

1. `gh` CLI authenticated with access to `Pulse-Energy/pulse-central`
2. Confirm target commit is on the intended branch (usually `production`)
3. Never deploy `staging` or `stg` branch to production — the reusable workflow rejects this

## Choose a workflow

| Goal | Workflow file | When to use |
|------|---------------|-------------|
| Build image only (ECR push, no deploy) | `build.yml` | Shared image build before deploying one or many workloads |
| Build + deploy one workload | `build-and-deploy-manual.yml` | Single-workload release from a specific branch/commit |
| Deploy existing tag (or rollback) | `deploy-workload.yml` | Image already in ECR; redeploy or rollback |

**Default arch:** `arm64` (Graviton). Use `arch=both` only when multi-arch is required.

## Verify caller wiring first

Before using `build-and-deploy-manual.yml`, read `.github/workflows/build-and-deploy-manual.yml` in the repo:

- **Correct:** calls `Pulse-Energy/pulse-ci-workflows/.github/workflows/build-and-deploy-manual.yml@main` and passes `workload`
- **Miswired:** calls `build-only.yml` only — use the two-step flow below instead

## Commands

Run from any directory. Always pass `--repo Pulse-Energy/pulse-central`.

Use `--ref production` (or `main`) so the workflow file comes from a trusted branch.

### 1. Build only → production ECR

```bash
gh workflow run build.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f branch=production \
  -f environment=production \
  -f dockerfile=./Dockerfile
```

Optional: `-f dockerfile=./Dockerfile.extended`

Image tag = **7-char commit SHA** of `branch` HEAD (shown in the Actions run summary).

### 2. Deploy one workload (after build, or rollback)

```bash
gh workflow run deploy-workload.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f workload=pulse-central-app-api-wl \
  -f environment=production \
  -f image-tag=<7-char-sha>
```

Omit `-f image-tag=...` to deploy the latest tag already recorded in ECR/Git for that workload.

### 3. Build + deploy one workload (when caller is wired correctly)

```bash
gh workflow run build-and-deploy-manual.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f branch=production \
  -f environment=production \
  -f workload=pulse-central-app-api-wl \
  -f dockerfile=./Dockerfile \
  -f arch=arm64
```

Optional inputs:

- `-f commit=<full-or-short-sha>` — pin build to a specific commit on `branch`
- `-f dockerfile=./Dockerfile.extended`
- `-f arch=both` — multi-arch manifest (slower; use when needed)

### 4. Two-step flow (reliable fallback)

When `build-and-deploy-manual.yml` only builds (miswired caller):

```bash
# Step 1 — build
gh workflow run build.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f branch=production \
  -f environment=production \
  -f dockerfile=./Dockerfile

# Step 2 — wait, read tag from summary, deploy each workload
gh run watch --repo Pulse-Energy/pulse-central

gh workflow run deploy-workload.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f workload=<workload-name> \
  -f environment=production \
  -f image-tag=<7-char-sha>
```

Repeat deploy for each workload that should receive the new tag.

## Monitor and verify

```bash
# List recent runs
gh run list --repo Pulse-Energy/pulse-central --workflow=build.yml --limit 5

# Watch active run
gh run watch --repo Pulse-Energy/pulse-central

# Open run in browser
gh run view <run-id> --repo Pulse-Energy/pulse-central --web
```

After deploy workflow succeeds:

1. Confirm Git commit on `production` updated `deploy/workloads/<workload>/clusters/aws/production.yaml` (`tag` + optional `branch` pin)
2. **Sync in ArgoCD** if auto-sync is off — production apps may stay OutOfSync until manual sync
3. Check pod rollout: new tag in ArgoCD UI or cluster

## Rollback

Deploy a previous known-good tag (no rebuild):

```bash
gh workflow run deploy-workload.yml \
  --repo Pulse-Energy/pulse-central \
  --ref production \
  -f workload=<workload-name> \
  -f environment=production \
  -f image-tag=<previous-7-char-sha>
```

Find previous tags: Actions run summary, `git log production -- deploy/workloads/<workload>/clusters/aws/production.yaml`, or ArgoCD History.

## Workload selection

Use exact workload directory names (suffix `-wl`). Full list: [workloads.md](workloads.md).

Common mappings:

| Service | Workload |
|---------|----------|
| Main REST / app API | `pulse-central-app-api-wl` |
| Console API | `pulse-central-console-api-wl` |
| Generic API | `pulse-central-generic-api-wl` |
| OCPI | `pulse-central-ocpi-api-wl` |
| Cron jobs | `pulse-central-cron-wl` |
| WebSocket API | `pulse-central-ws-api-green-wl` or `pulse-central-ws-api-blue-wl` |

**OCPP WebSocket servers** (`pulse-central-ocpp-*`, `thunderplus-central-ocpp-*`) are listed in workflow dropdowns but live in `pulse-ocpp-engine`, not pulse-central deploy paths. Do not deploy those from pulse-central.

## Safety checklist

Before triggering production:

1. Confirm migrations/schema changes are backward-compatible (shared Postgres/Redis/RabbitMQ)
2. Confirm the commit is merged to `production` (or intentionally pin a feature branch — see branch pinning)
3. Prefer deploying one canary workload first (`pulse-central-generic-api-wl` or a dedicated blue workload)
4. Check `autoDeploy: false` in target `production.yaml` — deploy workflow still updates Git; ArgoCD may need manual sync
5. Report the triggered run URL and image tag to the user

## Branch pinning

Deploying from a non-`production` branch sets `branch: <branch>` in the workload's `production.yaml`. Production auto-deploy skips pinned workloads until unpinned by redeploying from `branch=production`.

See `pulse-energy-docs/docs/guides/BRANCH_PINNING_RUNBOOK.md`.

## Related docs

- `pulse-energy-docs/docs/guides/argocd.md` — deploy/rollback overview
- `pulse-energy-docs/contexts/aws-infra-setup.md` — CI/CD architecture
- `pulse-energy-docs/docs/guides/PRODUCTION_ARCHITECTURE.md` — production topology
