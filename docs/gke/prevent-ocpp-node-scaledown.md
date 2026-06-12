# Preventing GKE Autoscaler from Restarting OCPP Engine Pods

**Date:** 2026-04-17
**Cluster:** `pulse-energy-prod-cluster` (`asia-south1`)
**Node Pool:** `pulse-energy-prod-ocpp-node-pool`

## Problem

The GKE Cluster Autoscaler removed 2 underutilized nodes from the OCPP node pool, evicting 19 `pulse-ocpp-engine` pods. This caused active WebSocket connections to chargers to drop.

### Root Cause

Nodes `...km9k` (10% CPU, 25% mem) and `...42qq` (16% CPU, 33% mem) were deemed underutilized. The autoscaler determined the remaining 19 nodes could absorb the evicted pods, so it drained and removed them.

A third node (`...58tl`, 20% CPU, 23% mem) was also underutilized but survived because the autoscaler couldn't find placement for its pods (`no.scale.down.node.no.place.to.move.pods`). This was accidental protection, not an explicit guarantee.

### Incident Timeline (April 17, 2026 — UTC)

| Time  | Event                                                  | Nodes       |
|-------|--------------------------------------------------------|-------------|
| 11:49 | Stable, no changes                                     | 21 / 21     |
| 12:18 | Autoscaler considers scaling down `...58tl`, rejects   | 21 / 21     |
| 12:23 | Same node re-evaluated, rejected again                 | 21 / 21     |
| 12:28 | **Scale-down decision: remove 2 nodes (`...km9k`, `...42qq`)** | 21 → 19 |
| 12:33 | Removal complete, confirmed via `resultInfo`           | 19 / 19     |
| 12:45 | Stable at new lower count                              | 19 / 19     |

### Evicted Pods

| Node      | CPU | Mem | Evicted Pods                                          |
|-----------|-----|-----|-------------------------------------------------------|
| `...km9k` | 10% | 25% | 7x `pulse-ocpp-engine-blue-wl`, 1x `green-wl`        |
| `...42qq` | 16% | 33% | 8x `pulse-ocpp-engine-blue-wl`, 1x `green-wl`, 1x `green-nginx-wl` |

---

## Solution: Three Layers of Protection

### 1. PodDisruptionBudget (PDB) — Block Voluntary Evictions

This is the most critical protection. Setting `maxUnavailable: 0` prevents the autoscaler (and `kubectl drain`) from evicting any OCPP pods.

```yaml
# pdb-ocpp-engine-blue.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pulse-ocpp-engine-blue-pdb
  namespace: pulse-energy
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: pulse-ocpp-engine-blue-wl   # Match your deployment's pod labels
---
# pdb-ocpp-engine-green.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pulse-ocpp-engine-green-pdb
  namespace: pulse-energy
spec:
  maxUnavailable: 0
  selector:
    matchLabels:
      app: pulse-ocpp-engine-green-wl   # Match your deployment's pod labels
```

Apply with:

```bash
kubectl apply -f pdb-ocpp-engine-blue.yaml
kubectl apply -f pdb-ocpp-engine-green.yaml
```

> **Note:** `maxUnavailable: 0` blocks **voluntary** disruptions (autoscaler, drain, upgrades) but NOT **involuntary** ones (node crash, OOM kill).

> **Deploy/rollout caveat:** When you need to update these pods (deploys, node upgrades), temporarily set `maxUnavailable: 1` or the PDB will block `kubectl rollout restart` as well.

### 2. Fixed Node Pool Size (min = max) — Prevent Node Removal Entirely

Lock the OCPP node pool to a fixed size so the autoscaler cannot add or remove nodes:

```bash
gcloud container node-pools update pulse-energy-prod-ocpp-node-pool \
  --cluster=pulse-energy-prod-cluster \
  --region=asia-south1 \
  --enable-autoscaling \
  --min-nodes=21 \
  --max-nodes=21
```

This guarantees no nodes are ever removed. The trade-off is paying for 21 nodes even during low traffic.

### 3. PriorityClass — Prevent Preemption by Other Pods

Create a high-priority class so OCPP pods are the last to be preempted:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ocpp-critical
value: 1000000
globalDefault: false
preemptionPolicy: Never
description: "Priority class for OCPP engine pods - must not be evicted"
```

Reference in OCPP engine deployments:

```yaml
spec:
  template:
    spec:
      priorityClassName: ocpp-critical
```

---

## Recommendation

Apply **PDB (`maxUnavailable: 0`) + fixed node pool size (min=max=21)**. This gives two independent guarantees:

1. The autoscaler cannot remove nodes from the OCPP pool (min=max).
2. Even if something else tries to drain a node, the PDB blocks pod eviction.

| Approach                        | Protects Against                        | Effort | Priority         |
|---------------------------------|-----------------------------------------|--------|------------------|
| PDB `maxUnavailable: 0`        | Autoscaler eviction, `kubectl drain`    | Low    | **Do immediately** |
| Fixed node pool size (min=max)  | Node removal entirely                   | Low    | **Do immediately** |
| PriorityClass                   | Preemption by other pods                | Low    | Nice to have     |

---

## Source Log

Raw autoscaler log: [`data/gke/downloaded-logs-20260417-181753.json`](../../data/gke/downloaded-logs-20260417-181753.json)
