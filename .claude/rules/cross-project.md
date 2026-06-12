---
description: Cross-project patterns and conventions shared across all repos
priority: medium
---
# Cross-Project Patterns

## Shared Types (central-atoms)
- Always check `central-atoms` before creating new types — types are organized by domain entity
- Types live in `src/central-atoms/` (git submodule) in both `pulse-central` and `central-console`
- Entity examples: `charging-station/`, `bill/`, `vehicle/`, `fleet/`

## Environment Files
- Environment config: `.dev.env`, `.stg.env`, `.prod.env` loaded via `env-cmd`
- Never create plain `.env` files — use the environment-specific variants

## Observability Stack
- **Sentry**: Error tracking (all projects)
- **Winston**: Structured logging (backends)
- **Google Cloud Logging**: Log aggregation (backends)
- **NewRelic**: APM monitoring (pulse-central)
- **Microsoft Clarity**: Session replay (energy-market)

## Infrastructure
- Deployment: AWS EKS (Kubernetes) — migrating from GCP
- CI/CD: Google Cloud Build (legacy) + GitHub Actions
- Database: PostgreSQL 14 via Prisma
- Queues: BullMQ (Redis-backed), Kafka for event streaming
- Payments: Razorpay and Paytm
- Maps: Google Maps API
