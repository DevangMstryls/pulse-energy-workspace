# Pulse manual build & deploy tools

Lightweight local replacements for GitHub Actions CI/CD — for use when
Actions is rate-limited.  Both scripts are **fully interactive by default**
(powered by `fzf`) and **fully scriptable by flag** — any flag you supply
skips that prompt.

| Script             | Replaces (CI workflow)  | What it does                                       |
| ------------------ | ----------------------- | -------------------------------------------------- |
| `pulse-build.sh`   | `build-only.yml`        | Build a project's Docker image and push to ECR     |
| `pulse-deploy.sh`  | `deploy-workload.yml`   | Write image tag into GitOps manifest → ArgoCD sync |
| `_lib.sh`          | *(shared)*              | fzf helpers, colors, project/workload discovery    |

## Prerequisites

```bash
brew install fzf          # interactive picker (falls back to numbered list if absent)
```

Plus:
1. **Docker Desktop** with `buildx` (Apple Silicon builds arm64 natively).
2. **AWS CLI** authenticated with ECR push/read permissions (SSO or `aws configure`).
3. `git` and `perl` (pre-installed on macOS).

## Interactive mode (no flags)

Just run the script and answer the prompts — fzf lets you fuzzy-search every
option:

```bash
./scripts/pulse-build.sh     # walks you through project → env → dockerfile → branch → arch
./scripts/pulse-deploy.sh    # walks you through project → env → workload → tag (picked from ECR)
```

## Non-interactive / partial mode (flags)

Supply any subset of flags; only the missing ones are prompted:

```bash
# Build
./scripts/pulse-build.sh -p pulse-central -e staging               # prompts: branch, dockerfile, arch
./scripts/pulse-build.sh -p pulse-central -e staging -b staging -y # fully non-interactive
./scripts/pulse-build.sh -p pulse-central -e production -b production -f ./Dockerfile.extended -y
./scripts/pulse-build.sh -p pulse-central -e staging --no-push     # local build only, no ECR push
./scripts/pulse-build.sh -p pulse-central -e staging --arch amd64

# Deploy
./scripts/pulse-deploy.sh -p pulse-central -w pulse-central-app-api-wl -e staging -t 407414d
./scripts/pulse-deploy.sh -p pulse-central -w pulse-central-cron-wl   -e production  # auto-resolves latest ECR tag
./scripts/pulse-deploy.sh -p pulse-ocpp-engine -w pulse-ocpp-engine-blue-wl -e staging -t 40240bf -y
```

## Standard flow when Actions is rate-limited

```bash
# 1. Build and push
./scripts/pulse-build.sh

# 2. Deploy (tag auto-suggested from ECR)
./scripts/pulse-deploy.sh
```

The build script prints the exact deploy command at the end:
```
./scripts/pulse-deploy.sh -p pulse-central -e staging -t <sha>
```

## Pipeline model

1. **Build** (`pulse-build.sh`): `docker buildx build` →
   `366292523926.dkr.ecr.ap-south-1.amazonaws.com/<prefix>_<service>:<7-char-sha>`
   Default platform is `linux/arm64` (Graviton EKS nodes).
2. **Deploy** (`pulse-deploy.sh`): writes `image.tag` into
   `deploy/workloads/<workload>/clusters/aws/<env>.yaml`, commits, and pushes.
   **ArgoCD** watches the repo and rolls the change onto EKS automatically.

ECR prefix by environment:

| Environment  | ECR prefix               | Example repo                              |
| ------------ | ------------------------ | ----------------------------------------- |
| `staging`    | `pulse-energy-staging`   | `pulse-energy-staging_pulse-central`      |
| `production` | `pulse-energy-production`| `pulse-energy-production_pulse-central`   |

## Deployable projects

These projects have `deploy/workloads/*/clusters/aws/` and can be deployed:

`energy-market` · `ops-dashboard-backend` · `pai-backend` · `proxy-server`
· `pulse-ai` · `pulse-api` · `pulse-central` · `pulse-central-alpha`
· `pulse-dataverse` · `pulse-evcharging-beckn-provider` · `pulse-ocpp-engine`
· `pulse-streamer` · `pulse-ubc-ocpi-adaptor` · `pulse-ubc-ocpi-adaptor-dashboard`
· `pulse-web`

## Safety guardrails

1. **Production builds** require typing the project name to confirm.
2. **Production deploys** require typing the workload name to confirm.
3. Deploy script validates the tag is a 7-char hex SHA and exists in ECR before
   touching any file.
4. Push retries 3× with rebase on conflict to handle concurrent commits.
5. `--no-push` / `--no-validate` flags available for offline/dry-run use.

## Env var overrides

| Variable                    | Default                    | Used by       |
| --------------------------- | -------------------------- | ------------- |
| `ECR_ACCOUNT_ID`            | `366292523926`             | build         |
| `ECR_REGION`                | `ap-south-1`               | build, deploy |
| `ECR_REPO_PREFIX_STAGING`   | `pulse-energy-staging`     | build         |
| `ECR_REPO_PREFIX_PRODUCTION`| `pulse-energy-production`  | build         |
| `GH_PAT` / `GITHUB_TOKEN`   | *(empty)*                  | build         |

## Full options

```
./scripts/pulse-build.sh  --help
./scripts/pulse-deploy.sh --help
```
