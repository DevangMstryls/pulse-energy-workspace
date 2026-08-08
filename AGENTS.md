# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Workspace Overview

This is a monorepo workspace containing the entire Pulse Energy platform — an EV charging infrastructure system. The workspace is organized as independent projects (not a package manager workspace), each in its own directory with separate git repos.

### Core Projects


| Project               | Type     | Tech Stack                               | Purpose                                              |
| --------------------- | -------- | ---------------------------------------- | ---------------------------------------------------- |
| `pulse-central`       | Backend  | Node.js 22, TS, Prisma, uWebSockets.js   | Main backend: REST APIs, OCPP/OCPI, billing, fleets  |
| `pulse-central-alpha` | Backend  | Same as pulse-central                    | Alpha/staging variant of pulse-central               |
| `central-console`     | Frontend | React 17, MUI 5, Redux, Formik+Yup       | Admin dashboard for managing charging infrastructure |
| `pulse-ocpp-engine`   | Backend  | Node.js 22, TS, uWebSockets.js, RabbitMQ | Dedicated high-performance OCPP 1.6 WebSocket server |
| `InstaCharge`         | Mobile   | React Native 0.76 + Expo 52, Redux       | Consumer-facing mobile app                           |
| `pulse-web`           | Frontend | Next.js 10, React 16, MUI                | Public-facing web application                        |
| `pulse-energy-lite`   | Frontend | React 18, CRA                            | Lightweight cross-platform web app (PWA)             |
| `pulse-streamer`      | Backend  | Node.js, TS, ffmpeg, GCS                 | RTSP to HLS video stream converter                   |
| `pulse-dataverse`     | Backend  | Node.js, TS, Prisma, Kafka               | Data analytics and SQL query execution               |
| `pulse-ai`            | Backend  | Node.js, TS, LangChain, ChromaDB, OpenAI | AI/LLM service with vector embeddings                |


### Shared Code via Git Submodules

All backend/frontend projects share code through git submodules:

- `**central-atoms**` (`src/central-atoms/`): Shared TypeScript types, enums, constants, and utilities organized by domain entity (e.g., `charging-station/`, `bill/`, `vehicle/`). Used by both `pulse-central` and `central-console`.
- `**beckn-atoms**` (`src/beckn/beckn-atoms/`): BECKN protocol shared types.
- `**pulse-node-utils-lib**` (`src/utils-lib/`): Shared packages for observability, Kafka, and HTTP server template.

## pulse-central (Main Backend)

### Commands

```bash
npm run start:dev          # Dev server with ts-node-dev + auto-reload
npm run start:dev:cpo      # Dev server for CPO environment
npm run build              # TypeScript compile (alias: build:prod)
npm run build:prod:clean   # Clean dist/ and rebuild
npm test                   # Jest unit tests
npm run test:e2e           # End-to-end tests (single worker)
npm run test:all           # Unit + e2e tests
npm run prisma:generate    # Generate Prisma client
npm run prisma:generate:ts # Generate TS Prisma schema
npm run prisma:setup       # Generate both Prisma clients
```

### Architecture

**Entry point**: `src/server.ts` — initializes globals, starts `CentralSystemServer` (WebSocket/OCPP) and `RestHttpServer` (REST API via uWebSockets.js).

**Server layer** (`src/server/`):

- `rest/RestHttpServer.ts` — Main REST API. Routes registered in `registerRoutes()`. Uses `this.app.<method>(path, handler)` pattern. Responses via `returnResponse()`.
- `rest/ConsoleRestHttpServer.ts` — Console-specific endpoints
- `rest/ExternalHttpServer.ts` — External integration endpoints
- `ocpp/` — OCPP protocol handlers (v1.5, v1.6, v2.0)
- `ocpi/` — OCPI protocol handlers
- `services/` — 100+ domain business logic services (e.g., `ChargePointService`, `BillService`, `FleetService`)
- `db-services/` — Database access layer wrapping Prisma. Always use these instead of direct Prisma client calls in handlers.
- `cache-services/` — Redis caching layer

**Database**: PostgreSQL 14 via Prisma 5.11. Schema at `prisma/schema.prisma` (4,800+ lines, 612+ migrations). Read replicas supported via `@prisma/extension-read-replicas`. Soft-delete pattern uses `deleted` flag.

**Conventions from Cursor rules**:

- Co-locate business logic in `RequestService` or `*RestHttpServerImpl`, not inline in route handlers
- New entities need a `*DbService.ts` in `src/server/db-services/`
- Prefer Prisma client methods over raw SQL
- Keep long-running/transactional operations in services, not handlers
- JSON schemas: `data/app_json_schemas/`, `data/rest_http_json_schemas/`, `data/console_json_schemas/`
- HTML templates: `data/html_templates/`
- OCPP schemas versioned in `data/json_schemas/v1.6/`
- Use `SchemaValidator` from `src/helpers/` for payload validation
- For HTML endpoints, update `isHtmlContentEndpoint()` and set `Content-Type: text/html`

**Ports**: 8080 (OCPP WebSocket), 8082 (OCPI), 8090-8092 (REST servers)

**Docker**: `docker-compose.yml` provides PostgreSQL 14 on port 5432 (`example`/`example` credentials for local dev).

**Formatting**: Prettier with 4-space tabs, 120 char width, trailing commas, single quotes. ESLint with Airbnb + TypeScript config.

### Key Queues & Infrastructure

- **BullMQ** (Redis-backed) for async job processing
- **Kafka** for event streaming
- **NewRelic** + **Sentry** + **Winston** for observability
- Deployment: AWS Elastic Beanstalk, Kubernetes, Google Cloud Build

## central-console (Frontend Dashboard)

### Commands

```bash
npm run dev                # Dev server (.dev.env)
npm run dev:stg            # Staging dev server (.stg.env)
npm run start:prod         # Production dev server (.prod.env)
npm run build              # Production build (react-scripts)
npm run build:dev          # Dev build
npm run build:stg          # Staging build
npm run test               # Run tests
```

### Architecture

**Entry**: `src/index.tsx` → Redux Provider + BrowserRouter → `App.tsx`

**Feature module pattern** — each domain feature follows this structure:

```
src/<domain>/<feature>/
├── store/
│   ├── reducers/featureReducer.js
│   ├── actions/featureActions.ts
│   └── actionTypes.ts
├── services/FeatureRequestService.ts    # API calls
├── types/                                # storeState, request, responses
├── views/                                # Page components
├── components/                           # Feature-specific components
├── routes/index.ts                       # Route definitions
└── helpers/
```

**State management**: Redux (40+ combined reducers) as primary store. Tanstack React Query (v5) for server state caching. Auth via `EmailOTPJWTContext`.

**Routing**: React Router v6. `AuthGuard` wraps protected routes. Feature flags via `FeatureFlagAuthorization`/`FeatureFlagRestriction` components. Multi-org aware.

**Major feature domains**: `charging/` (charge points, stations, transactions, tariffs, bills, roaming), `customers/`, `org/` (fleets, org users), `team/` (groups, permissions), `settlements/`, `analytics/`, `dashboard/`

**Key services**:

- `src/services/HttpService.ts` — Axios wrapper
- `src/services/AuthService.ts` — Token management
- `src/app/services/AppService.ts` — App initialization (Sentry, Firebase, Smartlook)
- `src/app/services/FeatureFlagService.ts` — Feature flag management

**Formatting**: Prettier with 4-space tabs, 140 char width, single quotes, no trailing commas. ESLint with TypeScript.

## pulse-ocpp-engine

See `pulse-ocpp-engine/AGENTS.md` for detailed architecture. Key points:

- OCPP 1.6 WebSocket server with API mode (forward to API) or Queue mode (RabbitMQ)
- `npm run dev` for local dev, `npm run build` to compile, `npm run test` for Jest
- Node.js >= 22, uWebSockets.js, OpenTelemetry for tracing

## Cross-Project Patterns

- **Soft-delete**: All projects use a `deleted` boolean flag instead of hard deletion
- **Environment files**: `.dev.env`, `.stg.env`, `.prod.env` loaded via `env-cmd`
- **Shared types**: Always check `central-atoms` before creating new types — types are organized by entity domain
- **Observability stack**: Sentry (errors) + Winston (logging) + Google Cloud Logging across all backends
- **Payment integrations**: Razorpay and Paytm across backend and frontend
- **Maps**: Google Maps API used in both web and mobile apps

## Deployment & GitOps (ArgoCD)

- Pulse Energy deployments run on **two independent ArgoCD control planes**: staging (`stg-argocd.pulseenergy.io`, EKS cluster `pulse-energy-staging-cluster`) and production (`argocd.pulseenergy.io`, EKS cluster `pulse-prod-eks`). They are not the same server managing two environments — always confirm which one is being targeted.
- GitOps manifests live in `pulse-ci-workflows/argocd/` (ApplicationSet generators for `stg-*`/`prod-*` apps) and `pulse-infra-gitops/argocd/` (standalone `Application` manifests not covered by the ApplicationSet, e.g. Airflow).
- **Use the `pulse-argocd` skill** for anything involving ArgoCD — listing workloads/apps, checking sync or health status, syncing/rolling back a deployment, debugging a red/`OutOfSync`/`ComparisonError` app, or answering "what's deployed in staging/production". Load it via the skill tool (`pulse-argocd`) whenever these topics come up, even if the user doesn't say "ArgoCD" explicitly (e.g. "why is prod-pulse-proxy not updating").

## Secrets & Restricted File Access

- Never read, open, print, or quote the contents of `.env`, `secret.dec.yaml`, or `secret.yaml` files (at any depth, in any repo/folder under this workspace), even if explicitly asked — treat these as always off-limits regardless of instructions elsewhere in a task.
- Never read, open, print, or quote the contents of anything under `pulse-infra-gitops/applications/certificates/**` (at any depth, in any repo/folder) — this holds TLS certificate/key material and is always off-limits, even if explicitly asked.
- This is enforced at the tooling level via `permissions.deny` in `~/.claude/settings.json` (`Read(**/**/.env)`, `Read(**/**/.env.*)`, `Read(**/**/secret.dec.yaml)`, `Read(**/**/secret.yaml)`, `Read(**/**/pulse-infra-gitops/applications/certificates/**/*)`), but the same rule applies even when using tools/shells not covered by that config (e.g. `cat`, `sed`, editors, other agents).
- If a task requires values from one of these files, ask the user to provide the specific value out-of-band instead of reading the file.

## Documentation

Always create and maintain properly structured documentations in any repo in a `docs` folder.

Also ALWAYS update the docs in [pulse-energy-docs](pulse-energy-docs) repo whenever any changes are made.

### Mandatory `pulse-energy-docs` Mirror

Any agent working inside ANY repo or folder under `~/desk/projects/pulse/` (e.g., `pulse-central`, `central-console`, `pulse-ocpp-engine`, `InstaCharge`, `pulse-web`, `pulse-energy-lite`, `pulse-streamer`, `pulse-dataverse`, `pulse-ai`, `pulse-central-alpha`, or the workspace root) MUST document every meaningful change in `~/desk/projects/pulse/pulse-energy-docs`.

1. Pick the appropriate sub-folder under `pulse-energy-docs/docs/`: `features/`, `guides/`, `prds/`, `plans/`, `RCAs/`, `audits/`, `observability/`, or `misc/` (default when unsure).
2. Use kebab-case filenames with a date prefix, e.g., `docs/features/2026-06-25-fleet-bulk-import.md`.
3. Each doc must include: Title, Date, Originating repo(s), Branch(es), PRs, Summary (2-5 sentences), Files changed, Operational notes (migrations/env/feature flags/deploys/rollback), and Links (tickets, dashboards, Sentry issues).
4. A single task spanning multiple pulse repos produces ONE consolidated doc that links to each PR — not one doc per repo.
5. Add `pulse-energy-docs` as its OWN row in the Work Completion Summary table (with its own branch, files changed, PRs).
6. The `pulse-energy-docs` default branch is `master` — this overrides the workspace-wide `develop` default per the per-repo override clause in `## Default Commit Branch`.
7. NEVER skip the docs update silently. If intentionally skipping (e.g., trivial typo fix), state the reason in the Work Summary `Additional Notes`.
8. Do NOT put secrets, credentials, tokens, or customer PII in `pulse-energy-docs`. The `docs/creds/` folder is for credential-handling process docs, not the credentials themselves.

## Long-Term Memory (Basic Memory MCP)

A `basic-memory` MCP server provides persistent, searchable, cross-session memory (facts about the user, decisions, gotchas) backed by git-tracked Markdown notes in `pulse-energy-docs/memory/` (project name: `pulse-memory`). Setup/replication guide: [pulse-energy-docs/docs/guides/2026-07-17-basic-memory-ai-setup.md](pulse-energy-docs/docs/guides/2026-07-17-basic-memory-ai-setup.md).

1. If the `basic-memory` MCP tools are available in this session, use them proactively:
   - Before starting non-trivial work, call `search_notes` / `build_context` / `recent_activity` to recall relevant prior context (user preferences, past decisions, repo-specific gotchas).
   - After learning a durable fact about the user, a decision, or a recurring gotcha, write or edit a note with `write_note` / `edit_note` — don't wait to be asked, but don't log trivial/one-off details either.
2. If the `basic-memory` MCP tools are NOT available (server not configured on this machine/session), tell the user once and point them at the setup guide above rather than silently skipping memory.
3. Memory notes are plain Markdown (Entities with `## Observations` and `## Relations`) and live under version control — treat them like any other doc: no secrets, credentials, tokens, or customer PII.
4. This memory store is a supplement to, not a replacement for, the `pulse-energy-docs` change-documentation mirror above — durable user/agent context goes in `memory/`, project change history goes in `docs/`.

### JSDoc comments

- Add JSDoc comments for each and every type, interface and function that you create.
- Each property of type and interface should have a JSDoc comment with what it its, its purpose and example of the expected values

## Accuracy

- Always provide as much accurate answers as possible without requiring any rework
- Always make use of required tools, plugins, skills to provide accurate, working outputs
- Always check your work

## Response Formatting

- Always return numbered lists (`1.`, `2.`, `3.`) instead of bullet lists (`-`, `*`) in responses to the user.
- This applies to all enumerations in chat output: steps, options, findings, summaries, sub-items, etc.
- This rule governs assistant chat formatting only — do NOT rewrite existing bullet content inside source files, docs, or rule files unless explicitly asked.
- Always return file paths as clickable markdown links that resolve correctly to the file. Use the format `[<relative-path>](<relative-path>)` with paths relative to the workspace/repo root. Verify the path exists before linking. Example: `[src/server.ts](src/server.ts)`, not bare `src/server.ts`. For paths outside the current repo, use absolute paths like `[/Users/devangmstryls/desk/projects/pulse/pulse-central/src/server.ts](/Users/devangmstryls/desk/projects/pulse/pulse-central/src/server.ts)`.

## Command Output Reporting

Whenever the agent runs a command (shell, build, test, lint, migration, deploy, curl, prisma, npm, git, etc.), the result MUST be reported back to the user as a markdown table with the following columns:

| # | Command | Expected Result | Actual Result | Status |
| - | ------- | --------------- | ------------- | ------ |

Rules:

1. One row per command executed. If multiple commands were run, include one row per command in the same table (preserve execution order).
2. `Command` — the exact command string that was executed (wrap in backticks). For long commands, keep the full command; do not truncate.
3. `Expected Result` — a short description of what the command was expected to produce or achieve (e.g., "exit 0, build artifacts in `dist/`", "all tests pass", "200 OK with user JSON").
4. `Actual Result` — a concise summary of what actually happened: exit code, key stdout/stderr lines, error messages, counts (e.g., "exit 0, 142 tests passed in 18s", "exit 1: `TypeError: Cannot read properties of undefined`").
5. `Status` — one of `✅ Pass`, `❌ Fail`, or `⚠️ Partial` based on whether the actual result matched the expected result.
6. If a command produced large output, include the table first, then optionally a fenced code block beneath it with the relevant excerpt — never paste raw output in place of the table.
7. This applies to every agent turn that runs at least one command. If no commands were run in a turn, the table is not required.

## Work Completion Summary

At the end of every task that produced a meaningful change (code edits, commits, PRs, infra changes, schema updates, deploys, etc.), the agent MUST provide a final Work Summary as a markdown table:

| # | Repo | Branch | Status | PRs | Files Changed | Additional Notes |
| - | ---- | ------ | ------ | --- | ------------- | ---------------- |

Rules:

1. One row per repository touched. `Repo` uses the directory/repo name (e.g., `pulse-central`, `central-console`).
2. `Branch` is the branch where changes were made; mark new branches as `<branch-name> (new)`.
3. `Status` is one of: `✅ Done`, `⏳ In Progress`, `❌ Blocked`, `⚠️ Partial`, `🚫 Skipped`.
4. `PRs` lists PR numbers or URLs (e.g., `#4231`); use `—` if no PR was opened.
5. `Files Changed` shows a count and optional grouping (e.g., `6 files (services, schema)`); use `—` if none.
6. `Additional Notes` captures pending TODOs, manual steps, migrations, env updates, deploy requirements, blockers, or related tickets.
7. Show the summary even if no commits were made — explain state in `Additional Notes` (e.g., "uncommitted local changes — awaiting approval").
8. After the table, include a short numbered list of next steps the user should take (deploy, review PR, run migration, etc.) when applicable.
9. The Work Summary is separate from and additional to the per-command Command Output Reporting table; both may appear in the same response.

## Default Commit Branch

Always commit changes on the `develop` branch unless one of the following is true:

1. The user has explicitly asked to commit on a different branch.
2. The specific repo's default active branch is something other than `develop` (e.g., a repo where `main`, `master`, or `staging` is the active integration branch) — in that case, use the repo's default active branch.

Before committing, the agent MUST:

1. Confirm the current branch via `git status` / `git rev-parse --abbrev-ref HEAD`.
2. Switch to `develop` (or the repo's overriding default) if not already on it; create/track from `origin/develop` if it exists only on the remote.
3. Pull the latest code for the current branch with `git pull --ff-only` before committing, to avoid stale-base commits and merge conflicts. If the pull fails (non-fast-forward), fetch with `git fetch origin <branch>` and rebase or ask the user before proceeding.
4. NEVER commit to `main`, `master`, or `production` unless explicitly asked.
5. NEVER force-push, rebase shared branches, or change git config without explicit instruction.
6. Record the actual branch used in the Work Summary `Branch` column.

## Battery Monitoring (Low Battery Alert)

A `devbook-service-manager` MCP server exposes a `system_overview` tool that returns `battery.percent` and `battery.state`. Use it to alert the user when battery is low.

- **Threshold**: 30%. Trigger whenever `battery.percent < 30`.
- **Mid-session check**: At the start of every agent turn, call `system_overview` once. If `battery.percent < 30`, immediately print a visible alert block (see format below) at the top of the response, BEFORE doing anything else. Do not repeat the alert within the same turn.
- **End-of-session check**: At the END of every task that produced a meaningful change (i.e., every turn that also requires a Work Completion Summary), call `system_overview` again. If `battery.percent < 30`, render the alert block immediately AFTER the Work Summary table and BEFORE any "next steps" list.
- **Charging override**: If `battery.state` is `charging`, skip the alert — the machine is plugged in and not at risk. Still call `system_overview` so the percent is known, but do not print the alert block.
- **Format**:

```
### ⚠️ Low Battery

| Metric | Value |
| ------ | ----- |
| Battery percent | NN% |
| Battery state   | discharging |
```

- If `system_overview` is unavailable or errors, silently skip — never block work on a tooling failure.
- This rule applies only when the `devbook-service-manager` MCP server is available in the session.

# AWS Guidance

- Prefer the AWS MCP Server for AWS interactions — it provides sandboxed
  execution, observability, and audit logging. If unavailable, use the
  AWS CLI directly.
- Before starting a task, check whether a relevant AWS skill is available.
  Load the skill with `retrieve_skill` and prefer its guidance over
  general knowledge.
- When uncertain about specific AWS details (API parameters, permissions,
  limits, error codes), verify against documentation rather than guessing.
  State uncertainty explicitly if you cannot confirm.
- When creating infrastructure, prefer infrastructure-as-code (AWS CDK or
  CloudFormation) over direct CLI commands.
- When working with infrastructure, follow AWS Well-Architected Framework
  principles.
- Do not use em dashes in AWS resource names or descriptions. Use
  hyphens instead.

## Secret Safety

- MUST load the `aws-secrets-manager` skill first for any secret,
  credential, API key, token, or password task. MUST NOT call
  `secretsmanager get-secret-value` or `batch-get-secret-value`, and MUST
  NOT hit the Secrets Manager Agent daemon directly. MUST use
  `{{resolve:secretsmanager:secret-id:SecretString:json-key}}` with
  `asm-exec` so the secret resolves at runtime without entering context.

