# pulse-central Production Workloads

Workload names match directories under `pulse-central/deploy/workloads/`.

All workloads share ECR repository `pulse-energy-production_pulse-central` unless overridden in `values.yaml` `build.ecrRepository`.

## Deployable workloads (22)

| Workload | Typical role |
|----------|----------------|
| `mg-central-app-api-wl` | MG central app API |
| `pulse-central-app-api-wl` | Primary app REST API |
| `pulse-central-app-load-api-wl` | App load API |
| `pulse-central-app-load-api-blue-wl` | App load API (blue) |
| `pulse-central-console-api-wl` | Console REST API |
| `pulse-central-console-api-blue-wl` | Console API (blue) |
| `pulse-central-cron-wl` | Scheduled cron jobs |
| `pulse-central-cron-coffee-wl` | Coffee cron variant |
| `pulse-central-e2e-test-wl` | E2E test workload |
| `pulse-central-generic-api-wl` | Generic REST API |
| `pulse-central-interstate-p2p-api-wl` | Interstate P2P API |
| `pulse-central-load-wizard-api-wl` | Load wizard API |
| `pulse-central-load-wizard-api-blue-wl` | Load wizard API (blue) |
| `pulse-central-ocpi-api-wl` | OCPI hub API |
| `pulse-central-ocpi-cpo-api-wl` | OCPI CPO API |
| `pulse-central-ocpi-emsp-api-wl` | OCPI EMSP API |
| `pulse-central-p2p-api-wl` | P2P API |
| `pulse-central-preprod-generic-api-wl` | Preprod generic API |
| `pulse-central-temp-load-wizard-api-wl` | Temporary load wizard |
| `pulse-central-ubc-bpp-api-wl` | UBC BPP API |
| `pulse-central-ws-api-blue-wl` | WebSocket API (blue) |
| `pulse-central-ws-api-green-wl` | WebSocket API (green) |

## In workflow dropdown but not in pulse-central deploy/

These appear in `build-and-deploy-manual.yml` / `deploy-workload.yml` choice lists but are owned by other repos:

| Workload | Owner repo |
|----------|------------|
| `pulse-central-ocpp-blue-wl` | `pulse-ocpp-engine` |
| `pulse-central-ocpp-green-wl` | `pulse-ocpp-engine` |
| `thunderplus-central-ocpp-blue-wl` | `pulse-ocpp-engine` |
| `thunderplus-central-ocpp-green-wl` | `pulse-ocpp-engine` |

## Per-workload config paths

```
deploy/workloads/<workload>/clusters/aws/production.yaml   # image tag, branch pin, replicas, ingress
deploy/workloads/<workload>/values.yaml                      # shared Helm values, optional build.* overrides
```
