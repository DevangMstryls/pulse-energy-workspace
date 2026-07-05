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
3. NEVER commit to `main`, `master`, or `production` unless explicitly asked.
4. NEVER force-push, rebase shared branches, or change git config without explicit instruction.
5. Record the actual branch used in the Work Summary `Branch` column.

## Headroom (Context Compression)

Three Headroom MCP tools are available for on-demand context compression. **Note: these operate in MCP-only mode** — they compress content you explicitly pass in, and track only those savings. The Headroom proxy (`http://127.0.0.1:8787`) that would auto-compress all traffic is not currently integrated with opencode, so it is not active.

1. `headroom_compress` — call this on any large tool output (search results, file reads larger than ~500 tokens, command logs, RAG chunks) BEFORE reasoning over it. Typical savings: 60-95% of tokens. Returns a `hash` that can be used to retrieve the original later.
2. `headroom_retrieve` — call with a `hash` returned by a prior compression to get the full original content back. Accepts an optional `query` to filter results.
3. `headroom_stats` — call at the end of a session, or when the user asks for a token/cost summary.

### When to compress

1. Search results with many matches.
2. File reads of large files — try `offset`/`limit` first; compress if still large.
3. Command output longer than ~100 lines.
4. RAG chunks or multiple file reads combined into a single reasoning step.

### When NOT to compress

1. Content the agent is about to edit — read/compress AFTER the edit, not before (editing requires exact original text).
2. Short outputs under ~500 tokens (overhead not worth it).
3. Structured data needed verbatim for downstream tool calls (file paths, hashes, generated SQL, etc.).

Each Headroom tool call counts as a command for reporting purposes and MUST appear as a row in the per-turn Command Output Reporting table, with a short summary of bytes/tokens saved or the hash returned.

### Headroom stats at end of every task

At the END of every task that produced a meaningful change (i.e., every turn that also requires a Work Completion Summary), the agent MUST:

1. Call `headroom_stats` as the last tool call of the turn.
2. Check proxy status: run `curl -s --max-time 2 http://127.0.0.1:8787/health` — note whether it is running or not.
3. Render a `### Headroom stats` block immediately AFTER the Work Summary table and BEFORE any "next steps" list, in this format:

```
### Headroom stats

| Metric | Value |
| ------ | ----- |
| Compressions this session  | … |
| Tokens in (original)       | … |
| Tokens in (compressed)     | … |
| Tokens saved               | … (NN%) |
| MCP-only cost saved (est.) | $… |
| Proxy status               | ⚠️ Not running — only explicit compressions tracked |
```

Replace the proxy status line with `✅ Running — full session savings tracked` if the proxy health check succeeds.

**Why the cost number is small:** `estimated_cost_saved_usd` uses a hardcoded $3/1M token rate and only counts tokens passed explicitly to `headroom_compress`. It does NOT reflect total conversation token spend. Full-session savings require the proxy to be running and traffic routed through it — which opencode does not currently support.

4. If `headroom_stats` is unavailable or errors, note that in the Work Summary `Additional Notes` column — never fabricate numbers.
5. For purely informational/Q&A turns where no Work Summary is produced, the stats block is optional and should be included only if the user asks.

