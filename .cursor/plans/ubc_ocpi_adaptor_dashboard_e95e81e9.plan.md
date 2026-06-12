---
name: UBC OCPI Adaptor Dashboard
overview: Build a production-grade dashboard for the OCPI-to-UBC adaptor using Vite + React 19 + TypeScript + Tailwind CSS v4 + shadcn/ui (dark theme). The dashboard covers auth (email OTP), summary stats, locations, EVSEs, connectors, sessions (with nested OCPI/Beckn logs, CDRs, payments), Beckn transactions, publish management, and support tickets. Backend support ticket API routes will also be created.
todos:
  - id: backend-support-tickets
    content: Create backend support ticket API routes and module in pulse-ubc-ocpi-adaptor (support-tickets.routes.ts, DashboardSupportTicketsModule.ts, register in index.ts)
    status: completed
  - id: scaffold-project
    content: Scaffold Vite + React 19 + TS project in pulse-ubc-ocpi-adaptor-dashboard. Install deps, init shadcn with preset b2D2iPEVG (Luma style, Mist base, Emerald theme), install all required shadcn components, configure Tailwind v4 theme with DM Sans + JetBrains Mono fonts
    status: completed
  - id: core-infra
    content: "Build core infrastructure: Axios client with auth interceptor, AuthProvider/PartnerProvider contexts, React Router routes, AuthGuard, AppLayout with collapsible sidebar + header + breadcrumbs + partner switcher"
    status: completed
  - id: login-page
    content: Build login page with two-step email OTP flow (request OTP -> verify OTP), form validation with Zod, distinctive visual design
    status: completed
  - id: dashboard-summary
    content: Build dashboard summary page with stat cards grid, date range filter, partner-aware data fetching from /summary endpoint
    status: completed
  - id: locations-module
    content: Build locations list (search, filter by city/publish, pagination, sort) and detail page (location info + EVSEs table + connectors per EVSE)
    status: completed
  - id: evses-module
    content: Build EVSEs list (search, filter by status/location, pagination) and detail page (EVSE info + connectors table + tariffs)
    status: completed
  - id: sessions-module
    content: "Build sessions list (search, filter by status/date/location, pagination) and detail page with tabbed sub-views: OCPI logs, Beckn logs, CDRs, payments"
    status: completed
  - id: beckn-transactions-module
    content: Build Beckn transactions list (filter by domain/action/date, search by transaction_id) and detail page (logs timeline + linked session info)
    status: completed
  - id: connectors-publish-module
    content: Build connectors publish management page with table, publish status filter, inline publish/unpublish toggle, bulk selection + bulk publish/unpublish actions
    status: completed
  - id: support-tickets-module
    content: Build support tickets list (filter by status/ref_type, search, pagination) and detail page (ticket info + linked session/connector)
    status: completed
  - id: polish-and-review
    content: "Final polish: loading states with skeletons, error states, empty states, responsive layout adjustments, accessibility check, code cleanup"
    status: completed
isProject: false
---

# UBC OCPI Adaptor Dashboard

## Design Direction

**Aesthetic**: Industrial-utilitarian meets modern data dashboard -- fitting for an EV charging infrastructure control panel. Dark mode primary with an emerald accent palette, evoking energy, sustainability, and precision.

**shadcn/ui Preset**: `b2D2iPEVG` ([preview](https://ui.shadcn.com/create?preset=b2D2iPEVG&template=vite))

- **Style**: Luma
- **Base Color**: Mist
- **Theme Color**: Emerald
- **Chart Color**: Emerald
- **Init command**: `npx shadcn@latest init --preset b2D2iPEVG -f`
- **Typography**: "DM Sans" for UI text (geometric, modern, distinctive), "JetBrains Mono" for data/code/IDs/timestamps
- **Color**: Mist-toned backgrounds with emerald as the primary accent -- aligns naturally with EV/green energy branding. Amber for warnings, red for destructive/errors.
- **Layout**: Collapsible sidebar (icon-only or full), breadcrumbs, card-based content with compact data tables
- **Motion**: Staggered page-load reveals, smooth sidebar collapse, subtle hover states on table rows

## Tech Stack

| Layer | Choice |
|-------|--------|
| Build | Vite 6 + `@vitejs/plugin-react` |
| UI | React 19 + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui (Luma style, Mist base, Emerald theme, preset `b2D2iPEVG`) |
| Routing | React Router v7 (proper URL-based routing) |
| Server State | TanStack React Query v5 |
| Forms | React Hook Form + Zod |
| HTTP | Axios |
| Tables | TanStack Table v8 (sortable, filterable, paginated) |
| Icons | Lucide React |
| Dates | date-fns |

## Project Structure

```
pulse-ubc-ocpi-adaptor-dashboard/
├── public/
├── src/
│   ├── api/                    # Axios instance + endpoint functions
│   │   ├── client.ts           # Axios setup, interceptors, auth header
│   │   ├── auth.ts             # login, verify, logout, me
│   │   ├── summary.ts
│   │   ├── locations.ts
│   │   ├── evses.ts
│   │   ├── sessions.ts
│   │   ├── beckn-transactions.ts
│   │   ├── connectors.ts       # publish routes
│   │   └── support-tickets.ts
│   ├── components/
│   │   ├── ui/                 # shadcn components (auto-generated)
│   │   ├── layout/             # AppLayout, Sidebar, Header, Breadcrumbs
│   │   ├── data-table/         # Reusable DataTable with pagination, sorting, filters
│   │   ├── partner-switcher.tsx
│   │   └── auth-guard.tsx
│   ├── hooks/
│   │   ├── use-auth.ts
│   │   └── use-partner.ts      # partner context/switcher
│   ├── lib/
│   │   └── utils.ts            # cn(), formatters, date helpers
│   ├── pages/
│   │   ├── login.tsx
│   │   ├── dashboard.tsx       # Summary/overview
│   │   ├── locations/
│   │   │   ├── list.tsx
│   │   │   └── detail.tsx      # Location + EVSEs + connectors
│   │   ├── evses/
│   │   │   ├── list.tsx
│   │   │   └── detail.tsx      # EVSE + connectors + tariffs
│   │   ├── sessions/
│   │   │   ├── list.tsx
│   │   │   └── detail.tsx      # Session + tabs: OCPI logs, Beckn logs, CDRs, Payments
│   │   ├── beckn-transactions/
│   │   │   ├── list.tsx
│   │   │   └── detail.tsx      # Transaction logs + linked session
│   │   ├── connectors/
│   │   │   └── list.tsx        # Publish/unpublish management
│   │   └── support-tickets/
│   │       ├── list.tsx
│   │       └── detail.tsx
│   ├── providers/
│   │   ├── auth-provider.tsx
│   │   ├── partner-provider.tsx
│   │   └── query-provider.tsx
│   ├── routes/
│   │   └── index.tsx           # All route definitions
│   ├── types/                  # Shared TS types mirroring backend models
│   │   └── index.ts
│   ├── App.tsx
│   ├── main.tsx
│   └── index.css               # Tailwind v4 + shadcn theme vars
├── components.json
├── index.html
├── package.json
├── tsconfig.json
├── tsconfig.app.json
├── vite.config.ts
└── .env.development             # VITE_API_BASE_URL
```

## Backend: Support Ticket Routes

New file: [`pulse-ubc-ocpi-adaptor/src/dashboard/routes/support-tickets.routes.ts`](pulse-ubc-ocpi-adaptor/src/dashboard/routes/support-tickets.routes.ts)

New module: [`pulse-ubc-ocpi-adaptor/src/dashboard/modules/DashboardSupportTicketsModule.ts`](pulse-ubc-ocpi-adaptor/src/dashboard/modules/DashboardSupportTicketsModule.ts)

Endpoints to create:

- **`GET /api/dashboard/support-tickets/`** -- List with pagination. Filters: `partner_id`, `status` (OPEN/IN_PROGRESS/RESOLVED/CLOSED), `ref_type` (ITEM/ORDER), `search` (matches `ref_id`, `beckn_transaction_id`), `from_date`/`to_date`, `page`, `per_page`
- **`GET /api/dashboard/support-tickets/:id`** -- Detail with related session and connector info included

Register in [`pulse-ubc-ocpi-adaptor/src/dashboard/routes/index.ts`](pulse-ubc-ocpi-adaptor/src/dashboard/routes/index.ts).

Follow the exact same patterns as existing routes (e.g., [`sessions.routes.ts`](pulse-ubc-ocpi-adaptor/src/dashboard/routes/sessions.routes.ts)) -- use `handleRequest`, `dashboardAuth` middleware, Prisma queries with `where`/`include`/`skip`/`take`/`orderBy`.

## API Integration Map

| Page | Backend Endpoint(s) |
|------|---------------------|
| Login (request OTP) | `POST /auth/request_otp` |
| Login (verify OTP) | `POST /auth/verify_otp` |
| Auth check | `GET /auth/me` |
| Logout | `POST /auth/logout` |
| Dashboard summary | `GET /summary/?partner_id=X` |
| Partner list (switcher) | `GET /setup/partners` |
| Locations list | `GET /locations/?partner_id=X&page=&per_page=&search=&city=&publish=` |
| Location detail | `GET /locations/:id` |
| EVSEs list | `GET /evses/?partner_id=X&location_id=&status=&search=&page=&per_page=` |
| EVSE detail | `GET /evses/:id` |
| Sessions list | `GET /sessions/?partner_id=X&status=&from_date=&to_date=&search=&page=&per_page=` |
| Session detail | `GET /sessions/:id` |
| Session OCPI logs | `GET /sessions/:id/ocpi-logs?page=&per_page=` |
| Session Beckn logs | `GET /sessions/:id/beckn-logs?page=&per_page=` |
| Session CDRs | `GET /sessions/:id/cdrs` |
| Session payments | `GET /sessions/:id/payments` |
| Beckn transactions list | `GET /beckn-transactions/?domain=&action=&transaction_id=&from_date=&to_date=&page=&per_page=` |
| Beckn txn detail | `GET /beckn-transactions/:transaction_id` |
| Beckn txn session | `GET /beckn-transactions/:transaction_id/session` |
| Connectors (publish) | `GET /publish/connectors?partner_id=X&publish_status=&search=&page=&per_page=` |
| Publish connector | `POST /publish/connectors/:id/publish` |
| Unpublish connector | `POST /publish/connectors/:id/unpublish` |
| Bulk publish | `POST /publish/bulk` |
| Support tickets list | `GET /support-tickets/?partner_id=X&status=&ref_type=&search=&page=&per_page=` (NEW) |
| Support ticket detail | `GET /support-tickets/:id` (NEW) |

## Page Designs

### Login Page
Full-screen dark background with centered card. Two-step flow: email input -> OTP input. Subtle energy-themed gradient mesh background.

### Dashboard (Summary)
Top: partner switcher + date range picker. Grid of stat cards (locations count, EVSEs, connectors, published connectors, active sessions, completed sessions, total energy kWh). Each card has an icon, value, and label.

### List Pages (Locations, EVSEs, Sessions, etc.)
Consistent pattern: search bar + filter controls in a toolbar, data table with sortable columns, pagination footer with page info and navigation. Row click navigates to detail.

### Detail Pages
Header with key identifiers and status badge. Card-based sections for different data groups. For sessions: tabbed interface with OCPI Logs, Beckn Logs, CDRs, and Payments tabs.

### Connectors (Publish Management)
Table with publish status column and inline publish/unpublish toggle. Bulk selection with bulk publish/unpublish actions.

### Sidebar Navigation

Items (with Lucide icons):
- Dashboard (LayoutDashboard)
- Locations (MapPin)
- EVSEs (Plug)
- Sessions (Activity)
- Beckn Transactions (ArrowLeftRight)
- Connectors (Cable)
- Support Tickets (LifeBuoy)

## Key shadcn Components to Install

`button`, `card`, `dialog`, `input`, `select`, `table`, `tabs`, `command`, `dropdown-menu`, `popover`, `tooltip`, `badge`, `avatar`, `scroll-area`, `separator`, `label`, `sheet`, `skeleton`, `sidebar`, `breadcrumb`, `alert`, `pagination`, `form`, `sonner` (toast)

## Implementation Sequence

The build follows a dependency-ordered sequence -- each phase builds on the previous one. The backend support ticket API is built first so all frontend pages have APIs ready.
