## Context

The parent repo, `apps/backend`, and `apps/web` are scaffolded but contain no
application code. Architecture is fully documented in `docs/internal/` (13
levels) and the dev orchestration (Makefiles, `docker-compose.yml`, mprocs)
already runs Postgres 18 + RabbitMQ. We need to land the first executable
slice across two services and the web frontend, then publish the phased
roadmap that will guide subsequent changes.

The user-visible target for this phase is the onboarding flow: a new school
visits the marketing site, registers as a tenant, picks a plan, lands on the
admin dashboard authenticated, and can toggle the modules their plan
entitles them to. Two services (IAM + Billing) own this flow end-to-end, so
they ship together.

Stakeholders:

- **Engineering team**: needs a working monorepo skeleton, shared libs, test
  scaffolding, and a clear pattern other services will copy.
- **Product / sales demos**: needs `make seed && make dev` to land in a
  browser showing real plans and at least one demo tenant.
- **Future service authors**: need event contracts (`tenant.registered`,
  `subscription.activated`) finalized so phase 2 (Academic Config) can
  consume them without reshaping data later.

Constraints:

- `13_engineering_standards/02_tech_stack.md`: Rust + Axum, SQLx,
  PostgreSQL 18, refinery, JWT RS256, Argon2, RabbitMQ, tracing + OTLP.
- `13_engineering_standards/03_api_conventions.md`: `/api/v1/{service}` base
  path, `{ data, meta }` success envelope, `{ error: { code, message } }`
  error envelope.
- `13_engineering_standards/14_validation_contract.md`: validation errors
  align with frontend Zod (`fields: { name: ["msg"] }`).
- `13_engineering_standards/10_cqrs_pattern.md`: command and query handlers
  in separate modules.
- `AGENTS.md`: never trust client-supplied `tenant_id`; resolve from JWT.

## Goals / Non-Goals

**Goals:**

- A phased implementation roadmap published in
  `docs/internal/13_engineering_standards/16_implementation_phases.md`.
- A working tenant-registration → login → modules flow exercising IAM and
  Billing services and the web app.
- A shared `libs/common-*` set that future services will reuse without
  modification — the patterns are settled here, not in phase 2.
- An automated test suite (unit, integration, e2e) green in CI, plus a
  `make seed` target that loads demo tenants and plans for manual testing.
- Event contracts for `tenant.registered` and `subscription.activated`
  documented in `docs/internal/11_integration_contracts/events/` so phase 2
  consumers can subscribe without rework.
- The IAM `/internal/users` boundary is fully defined and protected so
  Billing's saga can call it across the network.

**Non-Goals:**

- Academic year, curriculum, subjects, students, teachers, import — phase 2
  and 3.
- Tenant user management UI (inviting/removing tenant users) — phase 4.
  Phase 1 only creates the initial tenant admin.
- Real payment provider integration. Subscriptions activate on
  registration without payment; invoices are recorded but not collected.
- Email/SMS/WhatsApp delivery. Notifications are written to logs and
  events emitted, but the notification service itself is phase 5.
- Attendance, grading, promotion services and their data models.
- Multi-region or HA deployment concerns. This is a local + single-region
  staging deployment target.
- API gateway. Web calls services directly over docker-compose networks;
  gateway lands when there are >2 services to multiplex.

## Decisions

### Decision 1: Co-develop IAM and Billing rather than building them sequentially

**Choice**: Build IAM and Billing in the same change, ship them together.

**Why**: The end-to-end flow you can demo (register → login) requires both.
Building IAM first leaves nothing exercising it; building Billing first means
mocking authentication. Co-developing forces the IAM ↔ Billing boundary
(internal user creation API, JWT format, claims structure) to be real on day
one. The shared libs benefit too — `common-auth` gets exercised by both
services immediately.

**Alternatives considered**:

- *IAM-first, then Billing*: smaller per-PR diff, but the IAM API ends up
  guessing what Billing needs and gets reshaped during phase 2.
- *Billing-first with mocked auth*: defers the JWT decisions, leads to
  duplicate work when IAM lands.

### Decision 2: Tenant registration as a saga in Billing, not in IAM

**Choice**: `POST /api/v1/billing/tenants/register` is the public entry
point. Billing creates the tenant row, calls IAM's internal `POST
/internal/users` to create the admin user, then creates the subscription. On
IAM failure, Billing issues a compensating `DELETE /internal/users/{id}` (or
the user row never gets committed if IAM hasn't returned 201) and rolls back
its own transaction.

**Why**:

- A tenant is a Billing-owned aggregate; it cannot exist without a
  subscription, so the saga's commit point belongs in Billing.
- IAM should not know about plans or subscriptions. Putting the flow in IAM
  would couple it to Billing.
- The saga is short (two calls) and the failure modes are limited (IAM
  unreachable, duplicate email, validation). A two-phase commit is overkill.

**Alternatives considered**:

- *Sync transactional outbox in IAM*: IAM creates user + emits
  `user.created`, Billing subscribes and creates tenant. Rejected because
  the user must end up in the same tenant context at registration time, and
  Billing needs to surface `VALIDATION_ERROR` synchronously to the web form.
- *Single shared database*: violates the bounded context boundary.

**Trade-off**: Billing must know IAM's error envelope and translate it.
Acceptable because the contract is small and tested in the e2e suite.

### Decision 3: RS256 JWT with claims `{ sub, tenant_id, role, exp, iat, jti }`

**Choice**: Asymmetric signing with the public key shipped to other services
via env var. 15-minute access tokens; 7-day refresh tokens stored as Argon2
hashes in `iam.refresh_token` keyed by `(user_id, jti)`.

**Why**: Other services (Billing today, Academic Config tomorrow) verify
tokens locally without round-tripping to IAM. RS256 keeps signing
centralized in IAM. Refresh tokens hashed at rest mean leaked DB rows don't
grant sessions.

**Alternatives considered**:

- *HS256*: requires every service to hold the same shared secret. Rotation
  is harder.
- *PASETO*: better defaults, but tooling is thinner across the Rust
  ecosystem and the team knows JWT.

**Trade-off**: We must ship the IAM public key to other services via env
var. `make doctor` checks the var is set.

### Decision 4: Plans and feature entitlements as data, not code

**Choice**: `plan` rows + `plan_feature` rows (`plan_id`, `feature_code`,
`enabled`). The middleware in `common-auth` looks up the tenant's active
subscription, joins to `plan_feature`, and returns 403
`FEATURE_NOT_AVAILABLE` if the feature is disabled. Per-tenant overrides go
in `tenant_module` (`tenant_id`, `feature_code`, `enabled`) so admins can
turn entitled modules on/off without changing plans.

**Why**: Adding/changing plans is a marketing decision, not a code release.
Per-tenant overrides give us the flex to disable a module for a specific
school without giving them a custom plan.

**Alternatives considered**:

- *Hardcoded enum of plans*: simpler, but every plan change is a deploy.
- *Plan + override merged in IAM JWT*: faster check, but the JWT changes on
  every plan toggle and would force re-login.

**Trade-off**: One DB lookup per request needing entitlement check. Cached
per-request in `common-auth`'s extractor.

### Decision 5: Separate database per service from day one

**Choice**: `iam_db` and `billing_db` as separate logical databases on the
same Postgres 18 instance. Each service has its own SQLx pool and refinery
migration history. Services SHALL NOT issue cross-database joins.

**Why**: Encodes the bounded context boundary in infrastructure. Phase 2's
Academic Config service will copy the same pattern. Splitting later is much
harder than starting split.

**Alternatives considered**:

- *Single `akademiq_dev` DB with schemas*: one fewer config knob, but
  schemas don't enforce isolation as cleanly and don't translate to a
  multi-DB cluster later.

### Decision 6: Test pyramid with one e2e suite

**Choice**:

- **Unit** in each crate (`cargo test`) on pure domain logic.
- **Integration** per service: spin a Postgres testcontainer, run migrations,
  exercise HTTP handlers via `axum::Router`'s in-process testing.
- **One e2e crate** at `apps/backend/tests/e2e/` that runs `compose.test.yml`
  (Postgres + RabbitMQ + iam-service + billing-service), walks the full
  flow, then tears down.
- **Web Playwright** runs against a backend brought up by the same compose
  file.

**Why**: The integration tests cover happy + error paths per service. The
single e2e crate covers cross-service contracts (the saga, JWT validation
across services, event emission). Splitting e2e per flow gives no extra
coverage and triples runtime.

**Trade-off**: e2e adds ~30s to CI. Acceptable.

### Decision 7: Stub the RabbitMQ consumer until phase 4

**Choice**: Producers in IAM and Billing publish events through the standard
envelope, but no service subscribes in phase 1. The exchange + queues are
declared in `docker-compose.yml` so messages don't bounce; a dead-letter
queue retains them for inspection.

**Why**: Producing events early locks the contract. Building consumers when
no service consumes them yet is wasted work. Phase 2 (Academic Config) is
the first consumer (`subscription.activated` gates academic year creation).

**Trade-off**: We can't run end-to-end consumer tests until phase 2. The
event payload is unit-tested for serialization.

### Decision 8: Web app uses client components + TanStack Query + shadcn/ui exclusively

**Choice**:

- **UI primitives**: shadcn/ui (New York style) on Tailwind v4. Every form
  control, button, switch, select, dialog, card, alert, tooltip, and toast
  comes from `components/ui/`. Native HTML form controls (`<button>`,
  `<input>`, `<select>`, `<textarea>`, raw `<form>`) are forbidden in
  feature components. ESLint `react/forbid-elements` enforces it. Next.js
  `<Link>` is required for in-app navigation.
- **Data access**: TanStack Query for everything. Reads via `useQuery` /
  `useInfiniteQuery`, writes via `useMutation`. Direct `fetch()` is
  confined to `lib/api.ts`. No `useEffect`-based fetching anywhere.
- **Forms**: React Hook Form with `zodResolver`. Schemas live in
  `lib/schemas/` and are reused by tests. A shared
  `applyServerFieldErrors(form, error)` helper maps `VALIDATION_ERROR`
  payloads to RHF `setError` calls; field keys in Zod match backend names
  exactly.
- **Loading state**: two tiers. Action-bound controls (buttons, switch
  rows, select triggers) render a circular `<Spinner />` (Lucide
  `Loader2` + `animate-spin`) inside themselves and become `disabled`
  while pending. Layout regions (lists, cards, tables that depend on
  initial query data) render shadcn `<Skeleton>` placeholders that mirror
  the final shape. Each surface picks one tier; never both at once.
- **SSR**: per-request `QueryClient` factory; read-heavy public pages
  (`/register` plan catalog) prefetch on the server with `dehydrate` and
  rehydrate via `HydrationBoundary` so the same hooks read prefetched
  data on the client. Other pages render skeletons and fetch client-side.
- **Toaster**: a single shadcn `<Toaster />` mounted in `app/layout.tsx`
  for mutation success/error feedback.

**Why**: One paradigm everywhere keeps the codebase scannable. shadcn gives
us accessible, themable primitives without a heavy component-library
runtime. TanStack Query handles caching, background refetch,
optimistic updates, and refresh-on-401 in one place. RHF + Zod gives the
same schema for client validation and a clean mapping for backend
errors. The two-tier loading rule prevents the "is this loading or
broken?" UX bug.

**Alternatives considered**:

- *Next.js server actions for forms*: progressive enhancement is nice,
  but mixing actions with TanStack mutations creates two error-handling
  paths, doubles the field-error mapping code, and complicates the
  loading-state convention. Rejected because the SaaS admin console is
  already JS-required.
- *Headless UI / Radix directly without shadcn*: equivalent power but no
  copy-in component code, harder to theme, more boilerplate per primitive.
- *SWR instead of TanStack Query*: lighter API but weaker mutation story
  and worse devtools.

**Trade-offs**:

- Forms require JavaScript. Acceptable for an authenticated admin console.
- Per-page SSR prefetch is opt-in and adds boilerplate where used.
  Acceptable; only `/register` needs it in phase 1.
- Skeleton placeholders must mirror final layouts. Drift between skeleton
  and real layout is an explicit lint concern (visual review during PR).

### Decision 9: `common-testing` lib for shared fixtures

**Choice**: A workspace-internal crate with builders (`TenantBuilder`,
`PlanBuilder`, `UserBuilder`) and a `mint_jwt(user_id, tenant_id, role)`
helper. Used by every service's integration tests and the e2e crate.

**Why**: Avoids per-service test boilerplate drift. The first time we'd
copy-paste a `mint_jwt` helper between services is the day the format
diverges.

### Decision 10: Seed data is a binary in `billing-service`, not SQL files

**Choice**: `apps/backend/services/billing-service/src/bin/seed.rs` runs
through the same domain types as the API handlers (calling
`register_tenant` etc.) so seeded data is structurally identical to data
created via the UI.

**Why**: SQL seed files drift from the schema. Going through domain code
also exercises the saga during dev setup, surfacing issues earlier.

**Trade-off**: Slightly slower than `psql -f`. Acceptable (sub-second).

## Risks / Trade-offs

- **[Risk] Saga compensation in tenant registration is best-effort**: if
  Billing crashes between IAM user creation and subscription creation, an
  orphaned IAM user can remain.
  → **Mitigation**: each registration writes a `pending_registration` row in
  Billing before calling IAM; a 1-minute janitor job inside Billing reaps
  any pending registration older than 5 minutes by calling
  `DELETE /internal/users/{id}` and removing the tenant row. Janitor lands
  in this change; tested in the e2e suite by injecting a panic between the
  IAM call and the subscription insert.

- **[Risk] JWT public key distribution becomes operationally annoying**: every
  new service needs the IAM public key in its env.
  → **Mitigation**: `apps/backend/.env.example` ships a dev key pair
  (clearly labeled as dev-only). `make doctor` warns if any service is
  missing `IAM_PUBLIC_KEY`. Production rotation lands in phase 5 with the
  observability stack.

- **[Risk] The plan/feature matrix grows faster than we expect** and
  `tenant_module` overrides become unmanageable.
  → **Mitigation**: keep feature codes as a Rust enum mirrored from a single
  source of truth (`features.toml`) used by the seed binary, the migration,
  and a `make verify-features` check in CI. New features in later phases
  add a row, never a column.

- **[Risk] Web Playwright tests are flaky against compose-driven backends**.
  → **Mitigation**: web e2e waits on a `/healthz` endpoint that checks DB
  and RabbitMQ connectivity, not just process up. Retries set to 1; flake
  budget tracked.

- **[Trade-off] No payment provider means phase 1 subscriptions are
  free-by-default**. We accept this; the `subscription.activated` event
  carries a `payment_method = "manual"` field so phase 5 can add real
  providers without breaking the contract.

- **[Trade-off] Co-development of two services in one change inflates the
  PR size**. We accept this for the boundary-correctness reasons above; the
  implementation tasks are sliced so each task can land as its own commit
  inside the change branch.

## Migration Plan

**Deploy steps:**

1. Merge change to parent repo `main` after both submodule PRs land in
   their own `main` branches.
2. `make submodules` on the deploy host pulls latest.
3. `make migrate` runs IAM and Billing refinery migrations. Both are
   additive (no destructive ops).
4. `make seed` (staging only) loads demo plans + tenants.
5. `make up` brings the stack online.
6. Smoke test via `curl` the flow: register → login → /me → list plans →
   toggle module.

**Rollback:**

- Each service has `make migrate-down` that reverses the latest migration.
- The compose file pins service image tags; revert the tag and
  `docker compose up -d`.
- Refinery's history table makes selective rollback possible if only one
  service needs reverting.

**Backwards compat:**

- This is a greenfield change. No backwards compat concerns.
- The `tenant.registered` and `subscription.activated` event payloads are
  versioned (`event_type` includes no version suffix initially; breaking
  changes use `_v2` per `04_event_standards.md`).

## Open Questions

- **Q**: Should the initial tenant admin's email be verified before login is
  allowed?
  → **Proposed**: Skip in phase 1 (auto-verified on registration). Email
  verification lands with the notification service in phase 5. Acceptable
  for a demo; not acceptable for production launch.

- **Q**: Where does the "trial" plan go? (Free, time-limited.)
  → **Proposed**: Add a `trial_until` column on `subscription`. Trial logic
  is just a plan with `trial_until = now() + 14 days`. Defer to phase 2
  unless explicitly needed for the demo.

- **Q**: Do we run iam-service and billing-service as separate binaries or
  one binary with two routers?
  → **Proposed**: Separate binaries. Doubles container count but matches
  how every other service will run. Container overhead is negligible
  locally.

- **Q**: Should `common-testing` be `[dev-dependencies]` only?
  → **Proposed**: Yes, gated behind `#[cfg(any(test, feature = "test-utils"))]`
  so it never ships in release builds.
