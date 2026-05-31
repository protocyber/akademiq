## 1. Roadmap & cross-repo prep

- [x] 1.1 Draft `docs/internal/13_engineering_standards/16_implementation_phases.md` with phases 1-4 (scope, owning services, exit criteria, demo flows) and a Deferred section covering attendance, grading, promotion, notification, file/storage, payment provider, email/SMS
- [x] 1.2 Reference the new file from `docs/internal/13_engineering_standards/README.md`
- [x] 1.3 Add `IAM_PUBLIC_KEY`, `IAM_PRIVATE_KEY`, `IAM_INTERNAL_SERVICE_TOKEN`, `BILLING_DATABASE_URL`, `IAM_DATABASE_URL`, `RABBITMQ_URL` slots to `apps/backend/.env.example` (commented for future services)
- [x] 1.4 Add `make seed`, `make test-e2e`, `make test-web` to the parent `Makefile`; extend `make doctor` to check Rust toolchain and Playwright browsers
- [x] 1.5 Document the registration → login → modules quick-start in root `README.md`

## 2. Backend workspace skeleton (`apps/backend`)

- [x] 2.1 Initialize Cargo workspace at `apps/backend/Cargo.toml` listing `services/iam-service`, `services/billing-service`, `libs/common-auth`, `libs/common-db`, `libs/common-logging`, `libs/common-errors`, `libs/common-testing`, and `tests/e2e`
- [x] 2.2 Pin shared dependencies in `[workspace.dependencies]`: `axum`, `tokio`, `sqlx`, `refinery`, `argon2`, `jsonwebtoken`, `tracing`, `tracing-subscriber`, `opentelemetry-otlp`, `lapin`, `serde`, `serde_json`, `validator`, `uuid`, `chrono`, `thiserror`, `anyhow`, `testcontainers`
- [x] 2.3 Add per-service `Makefile` targets `dev`, `migrate`, `migrate-down`, `test`, `build`, `up`, `down` aligned with `13_engineering_standards/12_makefile_standards.md`
- [x] 2.4 Extend `apps/backend/docker-compose.yml` to bring up `iam-service` and `billing-service` containers using the `Dockerfile.service-template`, on the existing app network
- [x] 2.5 Create `apps/backend/compose.test.yml` (Postgres, RabbitMQ, iam-service, billing-service) with deterministic ports for the e2e crate

## 3. `libs/common-errors`

- [x] 3.1 Define `AppError` enum with variants for validation, not found, unauthorized, forbidden, conflict, internal
- [x] 3.2 Implement `IntoResponse` so every variant serializes to the standard error envelope (`{ "error": { "code", "message", "fields?" } }`)
- [x] 3.3 Add a `validation_error(fields: HashMap<String, Vec<String>>)` constructor matching `13_engineering_standards/14_validation_contract.md`
- [x] 3.4 Unit tests covering each variant's HTTP status and JSON shape

## 4. `libs/common-logging`

- [x] 4.1 Build a `tracing` JSON subscriber emitting `request_id`, `user_id`, `tenant_id`, `service_name` per line
- [x] 4.2 Add a request-id middleware that generates a UUID per request and stores it in the tracing span
- [ ] 4.3 Wire OTLP exporter behind a `OTEL_EXPORTER_OTLP_ENDPOINT` env var (disabled when unset)
- [x] 4.4 Unit tests asserting the JSON output contains required keys

## 5. `libs/common-db`

- [x] 5.1 SQLx pool builder with sane defaults (max connections, acquire timeout, idle timeout) configurable via env
- [x] 5.2 Refinery migration runner with `run_pending(&pool, "<service>")` entry point
- [x] 5.3 Transaction helpers: `with_tx<F>(pool, F) -> Result<R>` for handlers
- [ ] 5.4 Unit tests using a Postgres testcontainer

## 6. `libs/common-auth`

- [x] 6.1 RS256 JWT signer with claims `{ sub, tenant_id, role, iat, exp, jti }`; 15 min expiry
- [x] 6.2 RS256 verifier reading the public key from `IAM_PUBLIC_KEY`; surfaces `INVALID_TOKEN`, `EXPIRED_ACCESS_TOKEN`
- [x] 6.3 Argon2id wrapper: `hash(password)` and `verify(hash, password)` with parameters `m=19456, t=2, p=1`
- [x] 6.4 Axum extractor `AuthContext { user_id, tenant_id, role }` that rejects requests missing/invalid tokens with 401
- [ ] 6.5 Feature-entitlement middleware: looks up active subscription + plan_feature + tenant_module, returns 403 `FEATURE_NOT_AVAILABLE` or `SUBSCRIPTION_EXPIRED`
- [x] 6.6 Service-token guard for `/internal/*` routes verifying `X-Service-Token` against env
- [x] 6.7 Unit + integration tests for each piece (JWT round-trip, Argon2 verify constant-time, extractor rejection cases)

## 7. `libs/common-testing`

- [ ] 7.1 `TenantBuilder`, `PlanBuilder`, `UserBuilder`, `SubscriptionBuilder` with `.persist(&pool)` methods
- [x] 7.2 `mint_jwt(user_id, tenant_id, role)` helper that signs with the dev key
- [x] 7.3 `start_postgres()` + `start_rabbitmq()` testcontainer helpers with one-time init
- [x] 7.4 Gate behind `#[cfg(any(test, feature = "test-utils"))]`; export only what tests need

## 8. IAM service — schema & migrations

- [x] 8.1 Refinery migration `V1__init.sql`: `user`, `role`, `permission`, `role_permission`, `user_tenant_role`, `refresh_token` tables with indexes on `user.email` (unique), `user_tenant_role(user_id, tenant_id)`, `refresh_token(user_id, jti)`
- [x] 8.2 Refinery migration `V2__seed_roles.sql`: insert `super_admin`, `tenant_admin`, `teacher`, `homeroom_teacher`, `student`, `parent` with stable `role.code` values
- [x] 8.3 Add `make migrate` / `make migrate-down` targets in `services/iam-service/Makefile`

## 9. IAM service — domain & repos (CQRS-separated)

- [x] 9.1 Domain types: `User`, `Role`, `Permission`, `Membership`, `RefreshToken`
- [x] 9.2 Command module: `RegisterUserCommand` (internal), `LoginCommand`, `RefreshCommand`, `LogoutCommand`, `DeleteUserCommand` — each in its own file under `src/commands/`
- [x] 9.3 Query module: `GetMeQuery`, `GetUserByEmailQuery` under `src/queries/`
- [x] 9.4 Repository traits + SQLx impls for `UserRepo`, `RoleRepo`, `RefreshTokenRepo`

## 10. IAM service — HTTP layer

- [x] 10.1 `POST /api/v1/iam/auth/login` handler with input validation, Argon2 verify, token issuance, persists refresh token hash
- [x] 10.2 `POST /api/v1/iam/auth/refresh` handler with rotation; old token marked revoked
- [x] 10.3 `POST /api/v1/iam/auth/logout` handler that revokes the active refresh token
- [x] 10.4 `GET /api/v1/iam/me` handler reading `AuthContext`, returning user + memberships
- [x] 10.5 `POST /api/v1/iam/internal/users` handler protected by service-token guard; creates user + `user_tenant_role`
- [x] 10.6 `DELETE /api/v1/iam/internal/users/{id}` idempotent handler protected by service-token guard
- [x] 10.7 `GET /api/v1/iam/healthz` handler verifying DB connectivity

## 11. IAM service — integration tests

- [ ] 11.1 Login happy path + invalid credentials path (uniform error)
- [ ] 11.2 Refresh rotation revokes old token; expired refresh rejected
- [ ] 11.3 Logout invalidates refresh token
- [ ] 11.4 `/me` with valid + expired tokens
- [ ] 11.5 `/internal/users` happy path, missing service token, duplicate email returns 409
- [ ] 11.6 `/internal/users/{id}` delete is idempotent
- [ ] 11.7 Argon2 timing test: existence vs non-existence within 50 ms

## 12. Billing service — schema & migrations

- [x] 12.1 Refinery migration `V1__init.sql`: `tenant`, `plan`, `plan_feature`, `subscription`, `tenant_module`, `pending_registration`, `outbox` tables with indexes on `tenant.status`, `subscription(tenant_id, status)`, `plan_feature(plan_id, feature_code)` (unique), `tenant_module(tenant_id, feature_code)` (unique)
- [x] 12.2 Add `features.toml` at the repo root listing canonical feature codes; codegen or build-time check that DB rows + Rust enum match
- [x] 12.3 Add `make migrate` / `make migrate-down` targets in `services/billing-service/Makefile`

## 13. Billing service — domain & repos

- [x] 13.1 Domain types: `Tenant`, `Plan`, `PlanFeature`, `Subscription`, `TenantModule`, `PendingRegistration`, `OutboxEvent`
- [x] 13.2 Commands: `RegisterTenantCommand`, `ToggleModuleCommand`, `ExpireSubscriptionCommand` under `src/commands/`
- [x] 13.3 Queries: `ListPlansQuery`, `GetTenantMeQuery`, `GetTenantModulesQuery` under `src/queries/`
- [x] 13.4 Repository traits + SQLx impls for `TenantRepo`, `PlanRepo`, `SubscriptionRepo`, `TenantModuleRepo`, `OutboxRepo`

## 14. Billing service — registration saga

- [x] 14.1 Implement `register_tenant` saga: write `pending_registration`, call IAM `/internal/users`, write `tenant`, `subscription`, `tenant_module` defaults, enqueue events to outbox, mark `pending_registration` complete — all in one DB transaction except the IAM call
- [x] 14.2 Implement compensating `delete_user` call on IAM failure paths (validation, conflict, network)
- [x] 14.3 Implement janitor job (tokio interval) that reaps `pending_registration` rows older than 5 minutes by calling IAM delete + cleaning local rows
- [x] 14.4 Outbox publisher loop that drains `outbox` to RabbitMQ in `event_id` order with at-least-once semantics

## 15. Billing service — HTTP layer

- [x] 15.1 `POST /api/v1/billing/tenants/register` handler invoking the saga; returns tokens minted via the IAM internal flow
- [x] 15.2 `GET /api/v1/billing/plans` public handler returning plans + feature matrix
- [x] 15.3 `GET /api/v1/billing/tenants/me` authenticated handler resolving tenant from JWT
- [x] 15.4 `PATCH /api/v1/billing/tenants/me/modules` handler enforcing plan entitlement
- [x] 15.5 `GET /api/v1/billing/healthz` handler verifying DB and RabbitMQ
- [x] 15.6 Wire feature-entitlement middleware on `/tenants/me/modules`

## 16. Billing service — seed binary

- [x] 16.1 `apps/backend/services/billing-service/src/bin/seed.rs` reads `features.toml`, upserts plans `Starter`, `Standard`, `Premium` with the documented matrix, idempotently
- [x] 16.2 Seed binary creates two demo tenants (Starter + Premium) and one tenant admin per tenant by calling the same `register_tenant` domain code (not raw SQL)
- [x] 16.3 Wire `make seed` (parent) → `cd apps/backend && cargo run -p billing-service --bin seed`

## 17. Billing service — integration tests

- [ ] 17.1 `GET /plans` returns expected catalog after seed
- [ ] 17.2 `POST /tenants/register` happy path persists tenant, subscription, tenant_module rows, returns tokens
- [ ] 17.3 Validation error returns per-field shape
- [ ] 17.4 IAM 409 from saga rolls back tenant row
- [ ] 17.5 Janitor reaps an injected mid-saga panic and the same email succeeds afterward
- [ ] 17.6 `PATCH /tenants/me/modules` toggles entitled module; non-entitled returns 403 `FEATURE_NOT_AVAILABLE`
- [ ] 17.7 Expired subscription path returns 403 `SUBSCRIPTION_EXPIRED`
- [ ] 17.8 Outbox publisher writes both events to RabbitMQ in the documented order

## 18. Event contracts documentation

- [x] 18.1 `docs/internal/11_integration_contracts/events/tenant.registered.md` with payload schema (`tenant_id`, `school_name`, `created_by_user_id`)
- [x] 18.2 `docs/internal/11_integration_contracts/events/subscription.activated.md` with payload schema (`tenant_id`, `subscription_id`, `plan_id`, `start_date`, `end_date`, `payment_method`)
- [x] 18.3 Add API contract docs under `docs/internal/11_integration_contracts/apis/iam-service.md` and `billing-service.md` listing every public endpoint with request/response shapes

## 19. Cross-service e2e crate

- [ ] 19.1 `apps/backend/tests/e2e/Cargo.toml` and harness that brings up `compose.test.yml`, waits for `/healthz` on both services and Postgres+RabbitMQ readiness
- [ ] 19.2 Test 1: register → login → /me → list plans → toggle module → assert 403 on non-entitled
- [ ] 19.3 Test 2: register with duplicate email → 409 → tenant row absent
- [ ] 19.4 Test 3: registration with injected mid-saga panic → janitor cleans up → retry succeeds
- [ ] 19.5 Assert `tenant.registered` and `subscription.activated` events arrive in order via a temporary RabbitMQ consumer
- [ ] 19.6 Wire `make test-e2e` (parent) → run the e2e crate against compose.test.yml; teardown on success or failure

## 20. Web app — scaffold (`apps/web`)

- [ ] 20.1 `pnpm create next-app@latest` with TypeScript + App Router + Tailwind v4, pinned versions
- [ ] 20.2 Run `pnpm dlx shadcn@latest init` (New York style, Tailwind v4); commit `components.json` and base CSS variables in `app/globals.css`
- [ ] 20.3 Install shadcn primitives via CLI: `button`, `input`, `label`, `form`, `select`, `switch`, `card`, `dialog`, `tooltip`, `alert`, `sonner`, `separator`, `skeleton`
- [ ] 20.4 Add deps: `@tanstack/react-query`, `@tanstack/react-query-devtools` (dev), `react-hook-form`, `@hookform/resolvers`, `zod`, `lucide-react`, `class-variance-authority`, `clsx`, `tailwind-merge`, `@playwright/test`, `vitest`, `@testing-library/react`, `@testing-library/jest-dom`
- [ ] 20.5 Configure ESLint with `react/forbid-elements` blocking `button`, `input`, `select`, `textarea` in `apps/web/{app,components/features,components/pages}`; add a rule that flags `<a href="/...">` and requires Next.js `<Link>` for in-app routes
- [ ] 20.6 Configure `NEXT_PUBLIC_API_BASE_URL`, `IAM_BASE`, `BILLING_BASE` env wiring
- [ ] 20.7 Update `apps/web/Makefile` with `test`, `test:unit`, `test:e2e`, `lint` targets

## 20a. Web conventions & shared infrastructure

- [ ] 20a.1 Create `components/ui/spinner.tsx` using Lucide `Loader2` + `animate-spin`, with size variants (`sm`, `md`, `lg`) via CVA
- [ ] 20a.2 Create `lib/query/client.ts` (per-request `QueryClient` factory) and `lib/query/provider.tsx` (client component wrapping `QueryClientProvider` + `HydrationBoundary` + Devtools)
- [ ] 20a.3 Create `lib/forms/apply-server-field-errors.ts` typed against the API client's `FieldErrors`; calls RHF `setError(field, { type: "server", message })` for each entry
- [ ] 20a.4 Mount `QueryClientProvider` and shadcn `<Toaster />` in `app/layout.tsx`
- [ ] 20a.5 Add `apps/web/CONVENTIONS.md` documenting: shadcn-only UI, TanStack Query for all data, two-tier loading rule (spinner for action-bound controls, skeleton for layout regions), Zod + RHF + `applyServerFieldErrors` flow, Next `<Link>` for navigation
- [ ] 20a.6 Add `lib/schemas/` directory with one schema file per form (`register.ts`, `login.ts`, `module-toggle.ts`); export inferred TypeScript types

## 21. Web app — API client & query layer

- [ ] 21.1 Build `lib/api.ts`: typed fetch wrapper that attaches `Authorization`, parses success/error envelopes, transforms `VALIDATION_ERROR` into a typed `FieldErrors` object, and is the only place `fetch()` is called
- [ ] 21.2 Implement transparent refresh on 401 `EXPIRED_ACCESS_TOKEN` inside `lib/api.ts`; redirect to `/login?next=...` on refresh failure; ensure refresh logic is shared by every TanStack hook
- [ ] 21.3 Create `lib/query/queries/use-plans.ts`, `use-tenant-me.ts`, `use-me.ts` (each wraps `useQuery` and calls `lib/api.ts`)
- [ ] 21.4 Create `lib/query/mutations/use-register-tenant.ts`, `use-login.ts`, `use-logout.ts`, `use-toggle-module.ts` (each wraps `useMutation`)
- [ ] 21.5 Add SSR prefetch helper for `/register` plan catalog using `dehydrate` + `HydrationBoundary` so `usePlans` reads prefetched data on hydration
- [ ] 21.6 Auth context becomes a thin client wrapper over `useMe` + token storage; exposes `useAuth()` hook
- [ ] 21.7 Server-side helper that reads tokens from cookies for SSR-protected pages

## 22. Web app — pages

- [ ] 22.1 `/register` multi-step wizard built with shadcn `<Card>` per step + a stepper composed from shadcn primitives. Step 1 (school details), step 2 (plan selection — SSR-prefetched plan cards with skeleton fallback), step 3 (admin account), step 4 (submit). Submission uses `useRegisterTenant`; submit `<Button>` shows inline `<Spinner />` and is disabled while `isPending`. Backend `VALIDATION_ERROR` responses route through `applyServerFieldErrors`
- [ ] 22.2 `/login` form built with shadcn `<Form>` + RHF + Zod + `useLogin`; submit `<Button>` shows inline `<Spinner />` and is disabled while `isPending`; non-field errors render via shadcn `<Alert>` plus toast
- [ ] 22.3 `/dashboard` placeholder page protected by auth; header reads `useTenantMe` and renders `<Skeleton>` until resolved; shows tenant name + plan
- [ ] 22.4 `/settings/modules` page reads `useTenantMe`; renders shadcn `<Skeleton>` rows on first paint; entitled rows use shadcn `<Switch>` bound to `useToggleModule` with inline row spinner during `isPending`; non-entitled rows render disabled `<Switch>` wrapped in shadcn `<Tooltip>` with "Upgrade plan" hint
- [ ] 22.5 `/login` and `/register` redirect to `/dashboard` when already authenticated
- [ ] 22.6 Each page that owns a `useQuery` renders a shadcn `<Alert variant="destructive">` with a retry `<Button>` (containing inline `<Spinner />` while retrying) on non-auth errors

## 23. Web app — tests

- [ ] 23.1 Vitest: Zod schemas in `lib/schemas/` — at least one valid and one invalid case per schema (`register`, `login`, `module-toggle`)
- [ ] 23.2 Vitest: `applyServerFieldErrors` maps a multi-field `VALIDATION_ERROR` payload to RHF `setError` calls with `{ type: "server" }` and matching messages
- [ ] 23.3 Vitest: `lib/api.ts` triggers refresh on 401 `EXPIRED_ACCESS_TOKEN`, retries the original request, and redirects to `/login?next=...` on refresh failure
- [ ] 23.4 Vitest + Testing Library: an action-bound component renders the inline `<Spinner />` and is `disabled` while the underlying mutation is `isPending`
- [ ] 23.5 Vitest + Testing Library: a layout-bound component renders shadcn `<Skeleton>` placeholders while the underlying `useQuery` is in initial loading state
- [ ] 23.6 ESLint check passes via `pnpm lint`; `react/forbid-elements` violations fail CI
- [ ] 23.7 Playwright e2e: register new tenant → land on dashboard → log out → log in → toggle module → reload reflects state
- [ ] 23.8 Playwright e2e: assert spinner inside submit button on `/register`, skeleton cards on plan step before plans arrive, skeleton list on `/settings/modules` first paint
- [ ] 23.9 Playwright e2e: assert non-entitled module toggle is disabled, tooltip is reachable, and clicking emits no network request

## 24. CI

- [ ] 24.1 GitHub Actions workflow in `apps/backend/.github/workflows/ci.yml`: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test --workspace`, `make test-e2e`
- [ ] 24.2 GitHub Actions workflow in `apps/web/.github/workflows/ci.yml`: `pnpm lint`, `pnpm test:unit`, `pnpm test:e2e` against compose.test.yml from backend
- [ ] 24.3 Parent repo workflow that fails fast if either submodule SHA references a non-merged commit

## 25. Docs & wrap-up

- [ ] 25.1 Update `docs/internal/13_engineering_standards/01_repo_structure.md` to reflect the workspace layout that now exists (mark phase 1 services as built, others as planned)
- [ ] 25.2 Cross-link the API and event contract docs from `docs/internal/11_integration_contracts/README.md`
- [ ] 25.3 Run `openspec validate mvp-foundation-iam-billing --strict` and confirm green
- [ ] 25.4 Run the full local pipeline: `make doctor && make submodules && make migrate && make seed && make test && make test-e2e && make test-web && make dev`, then walk the demo flow in a browser
