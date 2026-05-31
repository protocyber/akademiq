## Why

The architecture for AcademiQ is documented end-to-end in `docs/internal/`, and
`init-dev-orchestration` has landed the dev loop, but neither submodule contains
any code yet. We need a phased roadmap that takes us from empty submodules to a
running MVP, **and** the first executable slice of that roadmap so the team can
demo the onboarding flow (register tenant → pick plan → log in → enable
modules) end-to-end on day one. Phase 1 is a small but real vertical slice
through IAM (Identity & Access Service) and Billing (Tenant & Subscription
Service) with automated tests and seedable demo data. Subsequent phases —
Academic Config, Academic Operations (students/teachers/import), and tenant
user management — land in their own changes once the foundation is stable.

## What Changes

### Roadmap (documentation deliverable)

- **NEW** `docs/internal/13_engineering_standards/16_implementation_phases.md`
  — phased build order with rationale, scope per phase, and explicit exit
  criteria. Phases:
  1. **Foundation: IAM + Billing** (this change). Tenant registration, plan
     catalog, plan selection, login, module entitlements per plan, web
     onboarding + login screens.
  2. **Academic Configuration**. Academic year, curriculum version, subjects,
     grading policy, class templates.
  3. **Academic Operations**. Student & teacher master data, Excel import,
     homerooms, enrollment, teaching assignments.
  4. **Tenant user management**. Inviting/managing users inside a tenant
     (admin, teacher, homeroom, parent, student accounts) with role scoping.
- Phase 5+ (attendance, grading, promotion, notification) tracked in the
  roadmap but out of scope until the foundation is proven.

### Phase 1 implementation (this change)

**Backend (`apps/backend`):**

- Cargo workspace at `apps/backend/Cargo.toml` with two services and four shared
  libs from `13_engineering_standards/01_repo_structure.md`:
  `services/iam-service`, `services/billing-service`,
  `libs/common-{auth,db,logging,errors}`.
- **Billing Service** (`/api/v1/billing`):
  - Tables `tenant`, `plan`, `plan_feature`, `subscription`, `tenant_module` (refinery migrations).
  - `POST /tenants/register` — public endpoint that creates tenant + initial
    admin user (delegates user creation to IAM via internal call), assigns the
    selected plan, creates a `subscription`, and emits `tenant.registered` and
    `subscription.activated` events.
  - `GET /plans` — public plan catalog with feature matrix.
  - `GET /tenants/me` and `PATCH /tenants/me/modules` — authenticated tenant
    admin can toggle modules **within** the entitlements granted by their
    current plan. Modules outside the plan return HTTP 403
    `FEATURE_NOT_AVAILABLE`.
  - Seed data: three plans (`Starter`, `Standard`, `Premium`) with module
    matrix matching `04_bounded_context` (academic_config, academic_ops,
    attendance, grading, promotion, notification, file).
- **IAM Service** (`/api/v1/iam`):
  - Tables `user`, `role`, `permission`, `role_permission`, `user_tenant_role`
    (refinery migrations).
  - `POST /auth/login` — email + password, returns RS256 access token (15 min)
    + refresh token (7 days). Argon2id password hashing.
  - `POST /auth/refresh`, `POST /auth/logout`.
  - `GET /me` — returns user + tenant memberships + role.
  - Internal `POST /internal/users` consumed by Billing during tenant
    registration; protected by a service-to-service shared secret.
  - Built-in roles seeded: `super_admin`, `tenant_admin`, `teacher`,
    `homeroom_teacher`, `student`, `parent`.
- **`common-auth`**: JWT (RS256) signing + verification, Argon2id wrapper,
  Axum extractor that injects `(user_id, tenant_id, role)` into request
  context. Servers MUST resolve `tenant_id` from the JWT, never from the
  request body.
- **`common-db`**: SQLx pool builder, refinery migration runner with one entry
  point per service, transaction helpers.
- **`common-logging`**: `tracing` subscriber that emits structured JSON with
  `request_id`, `user_id`, `tenant_id`, `service_name` on every line; OTLP
  exporter wired but disabled by default.
- **`common-errors`**: shared `AppError` → HTTP envelope (`{ "error":
  { "code", "message", "fields?" } }`) matching the validation contract.
- API responses follow `{ "data", "meta" }` envelopes.
- RabbitMQ wiring is **stubbed at the publisher boundary** in this change —
  events are produced and serialized through the standard envelope, but the
  consumer side is not built until phase 4.

**Web (`apps/web`):**

- `create-next-app` scaffold with TypeScript, App Router, and Tailwind v4.
- **shadcn/ui (New York style)** as the only source of UI primitives;
  native HTML form controls (`<button>`, `<input>`, `<select>`,
  `<textarea>`) are forbidden in feature components and pages, enforced
  by ESLint `react/forbid-elements`. In-app navigation uses Next.js
  `<Link>`.
- **TanStack Query** for all data access. Reads via `useQuery`
  (SSR-prefetched where it matters, e.g. the `/register` plan catalog),
  writes via `useMutation`. Direct `fetch()` is confined to `lib/api.ts`.
  No `useEffect`-based fetching.
- **React Hook Form + Zod (`zodResolver`)** for every form. Schemas live
  in `lib/schemas/` and are reused by tests. A shared
  `applyServerFieldErrors(form, error)` helper maps the backend's
  `VALIDATION_ERROR` envelope to RHF `setError` calls so field keys in
  Zod and the API stay aligned.
- **Two-tier loading rule**: action-bound controls (buttons, switch
  rows, select triggers) render an inline `<Spinner />` (Lucide
  `Loader2` + `animate-spin`) while pending and become `disabled`;
  layout regions (lists, cards, tables awaiting `useQuery` initial
  data) render shadcn `<Skeleton>` placeholders that mirror the final
  layout.
- Pages: `/register` (multi-step wizard: school info → plan select →
  admin account → submit), `/login`, `/dashboard` (placeholder with
  skeleton header), `/settings/modules` (shadcn `<Switch>` per row,
  inline spinner during PATCH; non-entitled rows disabled with shadcn
  `<Tooltip>` upgrade hint).
- Single shadcn `<Toaster />` mounted in the root layout.
- API client wrapper (in `lib/api.ts`) reads `NEXT_PUBLIC_API_BASE_URL`,
  attaches access token, refreshes on 401 once, redirects to `/login`
  on refresh failure. Refresh logic shared by every TanStack hook.

**Testing & seed data:**

- **Per service**: unit tests on domain logic (Argon2 hashing, JWT
  generation/validation, plan entitlement checks). Integration tests on each
  HTTP handler using `sqlx` test pool against a Postgres testcontainer.
- **Cross-service e2e suite** at `apps/backend/tests/e2e/` that boots both
  services + Postgres + RabbitMQ via `docker compose -f compose.test.yml up`,
  walks the full flow (register tenant → login → fetch `/me` → list plans →
  toggle modules → assert 403 on non-entitled), and tears down. Runs in CI
  and via `make test-e2e`.
- **Web**: Vitest for component/Zod tests, Playwright e2e against a running
  backend that exercises the same registration → login → modules flow.
- **Seed tooling**: `make seed` (parent), delegating to
  `apps/backend/services/billing-service/scripts/seed.rs` (binary target).
  Loads three plans, two demo tenants (one Starter, one Premium), and one
  tenant admin per tenant so the web UI is immediately clickable. Idempotent.
- **Test fixtures**: a `libs/common-testing` crate with builders for tenant,
  user, plan, subscription, and a helper that mints valid JWTs without going
  through the login endpoint.

### Service build order and rationale

- **IAM and Billing are co-developed** in this phase because tenant
  registration cannot complete without user creation, and login cannot
  complete without a tenant context. They ship together.
- IAM exposes the `internal/users` endpoint first; Billing's registration
  handler is built against it so the boundary is real, not mocked, before
  any other service depends on either.
- Academic Config (phase 2) is unblocked once Billing emits
  `subscription.activated` (already in scope here) — it consumes that event
  to gate `academic_year` creation behind an active subscription.

## Capabilities

### New Capabilities

- `implementation-roadmap`: defines the phased build order for the AcademiQ
  backend and web frontend, the scope and exit criteria of each phase, and
  which capabilities each phase delivers.
- `iam-service`: defines authentication (login, refresh, logout), password
  storage (Argon2id), JWT issuance and verification (RS256), the user/role/
  permission/membership data model, and the internal user-creation API
  consumed by Billing.
- `billing-service`: defines tenant registration, plan catalog, plan-to-feature
  entitlement matrix, subscription lifecycle (active/expired/cancelled), and
  per-tenant module toggling within plan entitlements.
- `tenant-onboarding`: defines the cross-service registration flow (web form
  → Billing → IAM → email-ready confirmation) including the validation
  contract, error envelope, and emitted events (`tenant.registered`,
  `subscription.activated`).
- `web-auth-onboarding`: defines the web pages and client behaviour for
  tenant registration, plan selection, login, token refresh, and module
  management, including Zod schemas aligned with the backend validation
  contract.
- `dev-test-harness`: defines the local + CI testing surface — unit,
  integration, e2e — and the `make seed` target that loads demo data so the
  flows are manually testable in a browser.

### Modified Capabilities

<!-- None. `repo-layout` and `dev-orchestration` already cover repo and tooling
concerns; this change adds new capabilities rather than changing requirements
on those existing ones. -->

## Impact

- **New code in `apps/backend`:** Cargo workspace, two service crates
  (`iam-service`, `billing-service`), four shared libs, one testing lib, one
  e2e test crate, refinery migrations per service, `compose.test.yml`, seed
  binary.
- **New code in `apps/web`:** Next.js scaffold, registration/login/dashboard/
  modules pages, API client, Zod schemas, Vitest + Playwright config.
- **New docs:** `docs/internal/13_engineering_standards/16_implementation_phases.md`.
- **Modified docs:** `docs/internal/13_engineering_standards/01_repo_structure.md`
  (mark Phase 1 services as built, others as planned),
  `docs/internal/11_integration_contracts/apis/` (add IAM + Billing API
  contracts), `docs/internal/11_integration_contracts/events/` (add
  `tenant.registered`, `subscription.activated`).
- **Parent repo:** `Makefile` gains `make seed`, `make test-e2e`,
  `make test-web`. `make doctor` adds checks for Rust toolchain and Playwright
  browsers.
- **Dependencies introduced:** `axum`, `sqlx`, `refinery`, `argon2`,
  `jsonwebtoken`, `tracing`, `tracing-subscriber`, `opentelemetry-otlp`,
  `lapin` (RabbitMQ), `testcontainers` (backend); `next`, `react`,
  `tailwindcss` (v4), `shadcn/ui` primitives, `@tanstack/react-query`,
  `@tanstack/react-query-devtools`, `react-hook-form`,
  `@hookform/resolvers`, `zod`, `lucide-react`,
  `class-variance-authority`, `clsx`, `tailwind-merge`, `vitest`,
  `@testing-library/react`, `@playwright/test` (web). All pinned to
  specific versions.
- **Out of scope (explicitly deferred):** academic year/curriculum/student/
  teacher/import features, tenant user management UI beyond the initial
  admin, real payment provider integration (subscriptions are activated
  without money changing hands in phase 1), email/SMS delivery, attendance,
  grading, promotion.
- **Risk:** the IAM ↔ Billing internal call introduces a synchronous
  dependency that complicates failure modes during registration. Design.md
  covers the chosen approach (single saga in Billing with compensating delete
  on IAM failure) and the alternatives considered.
