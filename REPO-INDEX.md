# Pulse Workspace — Repository Index

This folder (`/Users/devangmstryls/desk/projects/pulse`) is a **local workspace** that groups many independent git repositories for the Pulse Energy EV charging platform. It is **not** a single monorepo or npm/yarn workspace; each project has its own `.git` history, remotes, and dependencies.

**Last indexed:** 2026-05-28 (infra section added)

**Related workspace docs:** [AGENTS.md](./AGENTS.md) · [CLAUDE.md](./CLAUDE.md)

**Infrastructure work:** Use the repos in [Infrastructure](#infrastructure) below — not application repos like `pulse-central` or `central-console`.

---

## Infrastructure

For **anything related to infrastructure** (cloud provisioning, Kubernetes/GitOps, CI/CD pipelines, deployment runbooks, networking, observability setup, incident RCAs, or architecture docs), start in these workspace clones:

| Folder | Remote | Use this repo for |
|--------|--------|-------------------|
| [`pulse-energy-docs`](./pulse-energy-docs/) | `https://github.com/Pulse-Energy/pulse-energy-docs.git` | **Documentation** — platform and infra guides, runbooks, RCAs, migration plans, architecture references. Infra deep-dives live under `docs/guides/infra/` (e.g. ingress/nginx, EKS, networking). Update this repo when infra behavior or ops procedures change. |
| [`pulse-iaac`](./pulse-iaac/) | `git@github.com:Pulse-Energy/pulse-primary-iaac.git` | **Infrastructure as code** — AWS/GCP Terraform (or equivalent) under `aws-infra/`, `gcp/`, `environments/`, `modules/`. Provisioning, environments, and cloud resource definitions. |
| [`pulse-ci-workflows`](./pulse-ci-workflows/) | `git@github.com:Pulse-Energy/pulse-ci-workflows.git` | **CI/CD + deploy plumbing** — reusable GitHub Actions under `.github/workflows/`, plus the deployment artifacts those workflows apply: `argocd/`, `chart/`, `helm-values/`, `manifests/`, and the central `services-registry.yaml`. |
| [`pulse-infra-gitops`](./pulse-infra-gitops/) | `git@github.com:Pulse-Energy/pulse-infra-gitops.git` | **Cluster GitOps** — ArgoCD applications, Helm values, ingress, observability, certificates, and other Kubernetes cluster/app config (complements `pulse-iaac`). |

**Typical flow**

1. Read or update **how/why** in `pulse-energy-docs` (especially `docs/guides/infra/`).
2. Change **cloud resources** in `pulse-iaac`.
3. Change **cluster/app deployment** in `pulse-infra-gitops`.
4. Change **build and deploy automation** in `pulse-ci-workflows`.

---

## Quick reference — core platform


| Folder                | Type     | Purpose                                                                       |
| --------------------- | -------- | ----------------------------------------------------------------------------- |
| `pulse-central`       | Backend  | Main backend: REST, OCPP/OCPI, billing, fleets (Node 22, Prisma, uWebSockets) |
| `pulse-central-alpha` | Backend  | Staging/alpha variant of `pulse-central`                                      |
| `central-console`     | Frontend | Admin dashboard (React 17, MUI, Redux)                                        |
| `pulse-ocpp-engine`   | Backend  | Dedicated OCPP 1.6 WebSocket server (RabbitMQ)                                |
| `InstaCharge`         | Mobile   | Consumer app (React Native + Expo)                                            |
| `pulse-web`           | Frontend | Public web app (Next.js)                                                      |
| `pulse-energy-lite`   | Frontend | Lightweight PWA (React 18, CRA)                                               |
| `pulse-streamer`      | Backend  | RTSP → HLS video streaming                                                    |
| `pulse-dataverse`     | Backend  | Analytics and SQL query execution                                             |
| `pulse-ai`            | Backend  | AI/LLM service (LangChain, ChromaDB)                                          |


**Shared code (git submodules inside many repos):**


| Submodule path           | Repo                   | Role                                       |
| ------------------------ | ---------------------- | ------------------------------------------ |
| `src/central-atoms/`     | `central-atoms`        | Shared TS types, enums, constants          |
| `src/beckn/beckn-atoms/` | `beckn-atoms`          | BECKN protocol types                       |
| `src/utils-lib/`         | `pulse-node-utils-lib` | Observability, Kafka, HTTP server template |


---

## Workspace root files (not repos)


| Path                            | Purpose                                 |
| ------------------------------- | --------------------------------------- |
| `AGENTS.md`                     | Agent/Codex guidance for this workspace |
| `CLAUDE.md`                     | Claude Code guidance (mirror of AGENTS) |
| `pulse-infra.code-workspace`    | VS Code multi-root workspace            |
| `ubc-beckn-onix.code-workspace` | VS Code workspace for UBC Onix          |
| `package-lock.json`             | Minimal lockfile at workspace root      |
| `ev-bootcamp-kit-v1.zip`        | Archived bootcamp kit                   |
| `dump.rdb`                      | Redis dump (local dev artifact)         |


---

## Regenerating this index

From the workspace root:

```bash
for d in */; do
  name="${d%/}"
  if [ -d "$name/.git" ] || [ -f "$name/.git" ]; then
    remote=$(git -C "$name" remote get-url origin 2>/dev/null || echo "—")
    branch=$(git -C "$name" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "—")
    echo "$name|$remote|$branch"
  fi
done | sort
```

Update the tables above when adding or removing clones.