---
name: diff-k8s-workloads
description: Compares N Kubernetes workloads (Deployment/StatefulSet/DaemonSet) across any mix of GKE, EKS, or local clusters and writes a side-by-side Markdown diff into pulse-energy-docs/docs/guides/workload-diffs/. Use when the user asks to diff or compare K8s workloads, check drift between clusters, validate a GKE → EKS migration cutover, compare image tags / replicas / resources / env / secrets / HPA / ingress between two deployments, or sanity-check blue/green workloads.
---

# Diff Kubernetes Workloads (GKE ↔ EKS)

Runs `pulse-energy-docs/scripts/diff-k8s-workloads.py` to produce a Markdown report comparing N workloads across clusters. Built primarily for the **GKE → EKS migration**: before flipping DNS, diff the GKE original against the EKS replica and confirm image tag, replicas, resources, env, secret keys, HPA, ingress, nodeSelector, tolerations and pod annotations match.

Canonical reference: `pulse-energy-docs/docs/guides/WORKLOAD_DIFF_TOOL.md`. Read it for the full attribute list and limitations.

## Prerequisites

1. `kubectl` on `PATH` with a merged kubeconfig containing every context being compared. Run `kubectl config get-contexts -o name` and confirm at least one GKE (`gke_...`) and one EKS context are present. If missing, see `pulse-energy-docs/docs/guides/MAC_KUBECONFIG_GKE_AND_EKS.md`.
2. Python 3.9+ (stdlib only — no `pip install`).
3. `kubectl get` permission for Deployments / StatefulSets / DaemonSets / Secrets / ConfigMaps / HPAs / Services / Ingresses in the target namespaces. If Secret/ConfigMap RBAC is missing, pass `--no-secrets-keys`.

## CLI

Run from the `pulse-energy-docs/` directory so the relative `./scripts/...` path and the default output directory resolve correctly:

```bash
./scripts/diff-k8s-workloads.py \
    --workload <label>=<context>:<namespace>:<name>[:<kind>] \
    --workload <label>=<context>:<namespace>:<name>[:<kind>] \
    [--workload ...] \
    [--title "Free-form report title"] \
    [--output path/to/report.md] \
    [--no-secrets-keys]
```

Spec rules:

1. `<label>` — short, **unique** column header (e.g. `gke-prod`, `eks-prod`, `eks-stg-blue`).
2. `<context>` — kubectl context name (exact match from `kubectl config get-contexts`).
3. `<namespace>` — Kubernetes namespace.
4. `<name>` — workload object name.
5. `<kind>` — optional; auto-detected in order Deployment → StatefulSet → DaemonSet.

Defaults:

1. At least two `--workload` flags are required.
2. Default output: `pulse-energy-docs/docs/guides/workload-diffs/<timestamp>-<slug>.md`.
3. Secret/ConfigMap **values are never read** — only key lists. Reports are safe to commit.

## Common cluster contexts in this workspace

| Provider | Context | Notes |
|----------|---------|-------|
| GKE prod | `gke_pulse-energy_asia-south1_pulse-energy-prod-cluster` | Legacy / source of truth pre-migration |
| EKS prod | `pulse-prod-eks` | EKS production target |
| EKS staging | `pulse-energy-staging-cluster` | Staging |

Typical namespace: `pulse-energy`. Confirm before running.

## Scenarios

### 1. One GKE workload vs one EKS workload (pre-cutover check)

```bash
./scripts/diff-k8s-workloads.py \
  --workload gke-prod=gke_pulse-energy_asia-south1_pulse-energy-prod-cluster:pulse-energy:ops-dashboard-api-wl \
  --workload eks-prod=pulse-prod-eks:pulse-energy:ops-dashboard-api-wl \
  --title "ops-dashboard-api: GKE prod vs EKS prod"
```

### 2. N ≥ 2 mix (e.g. GKE blue + GKE green vs EKS blue)

```bash
./scripts/diff-k8s-workloads.py \
  --workload gke-prod-blue=gke_pulse-energy_asia-south1_pulse-energy-prod-cluster:pulse-energy:pulse-central-ocpp-blue-wl \
  --workload gke-prod-green=gke_pulse-energy_asia-south1_pulse-energy-prod-cluster:pulse-energy:pulse-central-ocpp-green-wl \
  --workload eks-prod-blue=pulse-prod-eks:pulse-energy:pulse-central-ocpp-blue-wl \
  --title "OCPP blue/green: GKE prod vs EKS prod blue"
```

### 3. Two EKS workloads (staging vs prod, or blue vs green)

```bash
./scripts/diff-k8s-workloads.py \
  --workload eks-stg=pulse-energy-staging-cluster:pulse-energy:genai-api-wl \
  --workload eks-prod=pulse-prod-eks:pulse-energy:genai-api-wl \
  --title "genai-api: EKS staging vs EKS production"
```

## Workflow

1. **Confirm contexts exist**: `kubectl config get-contexts -o name | rg '<context>'` for each one being passed. Abort early if any are missing.
2. **Pick unique labels** per column (`gke-prod`, `eks-prod`, `eks-stg`, `eks-prod-blue`, …). Labels must not repeat across `--workload` flags.
3. **Auto-detect kind** unless the workload is a StatefulSet/DaemonSet that the user has explicitly called out. The script tries Deployment first.
4. **Run the script** from `pulse-energy-docs/`. Tail the printed output path.
5. **Report the output path** to the user (and optionally a 1-line summary of obvious drifts: image tag mismatch, replica mismatch, missing secret keys, ingress host gap).
6. **Do not commit the report unless the user asks**. Default output dir is git-tracked.

## Drifts to highlight when summarizing

When reading the generated report back to the user, call out:

1. `code revision` (image tag) mismatch — EKS lagging GKE.
2. Replica count / HPA min-max divergence.
3. CPU / memory request and limit differences ("pod size" drift).
4. Secret or ConfigMap keys present on one side but missing on the other (common CrashLoopBackOff cause post-cutover).
5. Ingress hosts / TLS hosts gap — e.g. missing `vikram.ai.pulseenergy.io`. The `gke-prod-` ↔ `eks-prod-` host prefix swap is usually intentional.
6. `nodeSelector` / `tolerations` not yet copied to EKS (OCPP / GPU node pool risk).
7. Pod annotations (OTel auto-inject, scheduled restart timestamps) added on only one side.

## Limitations

1. Services are matched by label selector only — headless services with manual Endpoints won't be discovered.
2. Ingresses are matched only when they backend one of the discovered services. Nginx-proxy ConfigMap routing isn't parsed.
3. Only the first HPA targeting a workload is reported.
4. Secret/ConfigMap **values** are never fetched. For a value-level diff use `kubectl get secret -o jsonpath` or `aws secretsmanager get-secret-value` separately.
5. No automatic `ExternalSecret` resolution — the rendered K8s Secret keys are what end up in the pod, so those are what get diffed.

## Related guides

1. `pulse-energy-docs/docs/guides/WORKLOAD_DIFF_TOOL.md` — full reference.
2. `pulse-energy-docs/docs/guides/MAC_KUBECONFIG_GKE_AND_EKS.md` — merging GKE + EKS kubeconfig.
3. `pulse-energy-docs/docs/guides/EKS_MIGRATION_SESSION_CONTEXT.md` — cluster names, ECR conventions, DNS.
4. `pulse-energy-docs/docs/guides/PER_ENV_RESOURCES_AND_REPLICAS.md` — intended sizing per workload per environment.
