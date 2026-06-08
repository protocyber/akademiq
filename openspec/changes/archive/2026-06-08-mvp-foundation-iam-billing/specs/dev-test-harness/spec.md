## ADDED Requirements

### Requirement: Each backend service SHALL ship unit and integration tests runnable via `cargo test`

Every service crate MUST contain unit tests for domain logic and
integration tests for HTTP handlers using SQLx test pools against a
Postgres testcontainer. `cargo test -p <service>` MUST run both.

#### Scenario: Service tests run in isolation

- **WHEN** a contributor runs `cargo test -p iam-service` (or `-p billing-service`) on a clean checkout
- **THEN** unit and integration tests start a Postgres testcontainer, run refinery migrations against it, exercise the handlers, and exit zero with at least one assertion per public endpoint

#### Scenario: Tests do not interfere across runs

- **WHEN** integration tests run twice in succession
- **THEN** each run uses a fresh database (testcontainer) and the second run produces identical results to the first

### Requirement: A cross-service e2e test crate SHALL exercise the full onboarding flow

The repository MUST contain `apps/backend/tests/e2e/` as a separate test
crate that brings up `compose.test.yml` (Postgres, RabbitMQ,
iam-service, billing-service), executes the registration → login → /me →
modules flow, asserts the emitted RabbitMQ events, then tears down.

#### Scenario: e2e suite passes against compose.test.yml

- **WHEN** a contributor runs `make test-e2e` on a clean checkout with Docker available
- **THEN** the suite brings up the stack, walks the documented flow, asserts every step, and tears down without leaking containers or volumes

#### Scenario: e2e detects a broken saga

- **WHEN** a regression breaks the IAM call inside Billing's registration handler
- **THEN** at least one e2e assertion fails (registration returns non-201 or `tenant.registered` is not published) and the failing assertion message identifies the step

### Requirement: The web app SHALL ship Vitest and Playwright tests

The `apps/web` submodule MUST contain Vitest tests for components, hooks,
and Zod schemas, and Playwright tests for the registration → login →
modules user flow that run against a live backend brought up by the same
`compose.test.yml`.

#### Scenario: Vitest covers Zod schemas

- **WHEN** `pnpm test:unit` runs in `apps/web`
- **THEN** Zod schemas for registration and login forms are exercised with at least one valid and one invalid case each

#### Scenario: Playwright covers the user-visible flow

- **WHEN** `pnpm test:e2e` runs against a backend brought up by `compose.test.yml`
- **THEN** the suite registers a new tenant, logs out, logs back in, navigates to modules, toggles an entitled module, and asserts a non-entitled module is disabled

### Requirement: A `make seed` target SHALL load demo data idempotently

The parent `Makefile` MUST expose `make seed` that delegates to the seed
binary in Billing. The binary MUST insert (or upsert) three plans, two
demo tenants, and one tenant admin per tenant. Re-running `make seed`
MUST NOT produce duplicates or errors.

#### Scenario: Seed runs cleanly on an empty database

- **WHEN** a contributor runs `make seed` against an empty `iam_db` and `billing_db`
- **THEN** three plans, two tenants, and two admin users are created and the command exits zero

#### Scenario: Seed is idempotent

- **WHEN** a contributor runs `make seed` twice in succession
- **THEN** the second run completes successfully without creating duplicates or returning errors

#### Scenario: Seeded tenant admin can log in via the web app

- **WHEN** after `make seed && make dev`, a contributor opens the web app and submits the seeded admin's credentials on `/login`
- **THEN** the contributor lands on `/dashboard` authenticated and can navigate to `/settings/modules`

### Requirement: Shared test fixtures SHALL live in a workspace-internal `common-testing` crate

The crate `libs/common-testing` MUST provide `TenantBuilder`,
`PlanBuilder`, `UserBuilder`, and `mint_jwt(user_id, tenant_id, role)`.
It SHALL be gated behind `#[cfg(any(test, feature = "test-utils"))]` so
it never ships in release builds.

#### Scenario: Builders produce valid persisted rows

- **WHEN** a service's integration test calls `TenantBuilder::default().persist(&pool).await`
- **THEN** a tenant row exists in `billing_db` with sane defaults and a returned `Tenant` struct that the test can manipulate further

#### Scenario: mint_jwt produces a token accepted by common-auth

- **WHEN** a test calls `mint_jwt(user_id, tenant_id, "tenant_admin")` and includes the result as the `Authorization` header on a handler test
- **THEN** the handler's `common-auth` extractor populates the request context with the same `(user_id, tenant_id, role)`

### Requirement: CI SHALL run unit, integration, e2e, and web suites on every change

A CI workflow MUST run `cargo test` (per service), `make test-e2e`, and
`pnpm test:unit` + `pnpm test:e2e` on every PR to either submodule or the
parent repo. Failures in any suite MUST block merge.

#### Scenario: PR with a failing unit test does not merge

- **WHEN** a PR introduces a regression caught by `cargo test -p iam-service`
- **THEN** the CI run fails on the unit test step and the PR is blocked from merging until fixed

#### Scenario: PR with a passing test pyramid is mergeable

- **WHEN** a PR passes `cargo test`, `make test-e2e`, and the web Vitest + Playwright suites
- **THEN** the CI status is green and the merge button is enabled
