# Design Spec: Web Admin Feature Roadmap & Phase 1 Detail

Date: 2026-09-12
Topic: `apps/web-admin` platform operator console — feature roadmap
Status: approved (design); Phase 1 ready for implementation planning

## 1. Scope and Positioning

`apps/web-admin` is the **platform operator console** for AkademiQ staff
holding the `platform_admin` role. It authenticates with a `typ:"platform"`
JWT (no `tenant_id`) issued by `POST /api/v1/iam/platform/auth/login`.

It is **not** a school-facing admin panel. School administrators continue to
use the tenant app at `apps/web`. Any feature in this roadmap that appears to
manage school-internal data (students, classes, schedules) is out of scope by
definition.

Stack: Nuxt 4 + Nuxt UI 4, TanStack Vue Query, port 3010. All code follows
`apps/web-admin/CONVENTIONS.md`; backend work follows
`apps/backend/CONVENTIONS.md`.

## 2. Current State

### 2.1 Shipped in web-admin

| Route | Backing endpoint |
|---|---|
| `/` (overview) | `GET /platform/overview` |
| `/login` | `POST /iam/platform/auth/login` |
| `/tenants`, `/tenants/[id]` | `GET /platform/tenants`, `/tenants/:id`, `/tenants/:id/usage` |
| `/users`, `/users/[id]` | `GET /platform/users`, `/users/:id` |
| `/billing/plans` (+ `new`, `[id]/edit`) | `GET/POST /platform/plans`, `PUT/DELETE /platform/plans/:id` |
| `/audit` | `GET /platform/audit` |

Tenant lifecycle commands (`POST /platform/tenants/:id/suspend`,
`/reactivate`) and subscription override
(`POST /platform/tenants/:id/subscription`) exist and are wired to the tenant
detail page.

### 2.2 Gap analysis

**Backend capability exists, no operator UI** (lowest-hanging fruit, no new
infrastructure):

| Capability | Backend location | UI status |
|---|---|---|
| Per-tenant module toggle | `PATCH /billing/tenants/me/modules`, table `tenant_module` | none; and the command emits no event, so projections never see it |
| Stalled/failed registrations | table `pending_registration` (billing_db) | no endpoint, no UI |
| Subscription lifecycle detail | table `subscription` (billing_db), projection `platform_subscription` | UI shows plan code only |
| Per-service health | `GET /<service>/healthz` × 6 | none |
| Tenant school profile + logo | `GET/PATCH /billing/tenants/me/school-profile` | none |

**Requires new platform endpoints** (backend + UI work):

- Operator-initiated tenant creation. Only the public self-service path
  (`POST /billing/tenants/register`) exists today.
- Inviting the first tenant admin and resetting a tenant user's password.
  IAM has tenant-scoped equivalents (`POST /iam/tenants/me/invitations`,
  `POST /iam/tenants/me/users/:id/reset-password`) but no platform-scoped
  variant.
- Audited tenant impersonation.
- Management of platform operators themselves. `user_platform_role` is
  currently writable only through SQL or the `akademiq` CLI.

**Requires infrastructure that does not exist yet:**

- **Mailer / notification service.** There is no mail crate (no `lettre`, no
  SMTP config) anywhere in the backend. IAM already mints invitation URLs of
  the form `/invitations/accept?token=<token>`, but delivery is manual.
- **Payment gateway.** `subscription.payment_method` is hardcoded `manual`;
  `subscription.activated` documents `stripe`/`xendit` as future values only.
- **Metrics / tracing sink.** OpenTelemetry is mandated by
  `docs/internal/13_engineering_standards/` but no collector or sink is
  deployed.

The sharpest operational debt found: `pending_registration` already records
onboarding failures, but no human can see them.

## 3. Roadmap Structure

Features are grouped into five functional tracks (Onboarding, Billing,
Support, Observability, Governance) and sequenced into six phases ordered by
`operator pain × infrastructure readiness`. Phases 1-3 introduce **no new
infrastructure**. Infrastructure-dependent work is named as its own explicit
phase with its dependency stated.

Phase 1 is deliberately read-only (with one exception) so operators gain
visibility before they are handed buttons that mutate data.

### Phase 1 — See before acting (no new infra)

1. **Subscription health on tenant detail** — surface the real subscription
   record, not just the plan code.
2. **Tenant module panel** — view and toggle `tenant_module` entitlements.
   The sole write in this phase, justified because the billing write path
   already exists.
3. **Failed-registration board** — expose `pending_registration`, flag rows
   stuck in `user_created` / `tenant_created`.
4. **Service health board** — fan-out `/healthz` across all six services.

### Phase 2 — Onboarding without email (no new infra)

5. **Create tenant from the UI** — operator endpoint wrapping the billing
   registration flow, with initial plan selection.
6. **Invite first tenant admin, copy link** — operator generates the
   `invitations/accept?token=` URL and copies it; delivery stays manual until
   Phase 4.
7. **Operator-initiated tenant user password reset** — platform-scoped
   variant of `admin_reset_password`, also producing a copyable link.
8. **Retry / clear stalled registrations** — action buttons layered on the
   Phase 1 board.

### Phase 3 — Support & governance (no new infra)

9. **Audited impersonation** — time-boxed tenant-scoped token, mandatory
   reason, recorded in `operator_audit`, prominent banner in the tenant app.
10. **Platform operator management** — CRUD over `user_platform_role` from
    the UI instead of SQL.
11. **Searchable audit log** — filter by actor, action, tenant, date range.
    Today it is a raw paginated list.
12. **Manual subscription lifecycle** — renew, adjust end date, cancel, mark
    expired.

### Phase 4 — Mailer (new infra: notification service + SMTP)

13. Automated delivery of invitations, password resets, email verification,
    and subscription-expiry warnings. Removes the "copy link" step from
    Phase 2.

### Phase 5 — Payment (new infra: payment gateway, e.g. Midtrans/Xendit)

14. Invoices, payment history, dunning, automatic suspension on non-payment.

### Phase 6 — Deep observability (new infra: metrics sink)

15. Per-service error rate, RabbitMQ queue depth, outbox/projection lag,
    p95 latency.

## 4. Phase 1 Detailed Design

All four features lean on platform-service. Existing architectural rules
hold: reads come from local projections with no synchronous cross-service
calls, except where explicitly noted in 4.4.

### 4.1 Subscription health on tenant detail

`platform_subscription` already exists as a projection table but is never
read by the HTTP layer.

- **Endpoint:** `GET /api/v1/platform/tenants/:tenant_id/subscription`
- **Response:** `plan_code`, `status`, `started_at`, `ends_at`. These are the
  actual `platform_subscription` column names. `payment_method` is **not**
  projected today and is therefore out of scope for Phase 1; adding it would
  require extending the `subscription.activated` event payload.
- **Missing projection row:** respond with a `null` payload meaning "no
  subscription on record". This is not an error condition.
- **UI:** a new card on `/tenants/[id]` using `StatusBadge`, plus a warning
  when `ends_at` is less than 30 days away. `ends_at` is nullable
  (open-ended subscription) — render "no end date" rather than a warning.

### 4.2 Tenant module panel

`platform_subscription.modules` (JSONB) already exists and is already
populated by the projection consumer from `subscription.activated` /
`subscription.plan_changed`. **No new projection table is needed** — the read
comes from that column.

There is, however, a freshness hole: billing's `toggle_module`
(`services/billing-service/src/commands.rs`) writes `tenant_module` but
**publishes no event**. Operator toggles would therefore never reach the
projection. Phase 1 closes this hole:

- Billing emits a new `tenant.module_toggled` event through the outbox when a
  toggle changes state, carrying `tenant_id`, `feature_code`, `enabled`.
- The platform projection consumer handles it by patching the single key
  inside `platform_subscription.modules`, leaving other keys untouched.

Endpoints:

- `GET /api/v1/platform/tenants/:tenant_id/modules` — reads the projection.
- `PUT /api/v1/platform/tenants/:tenant_id/modules` — forwards to billing's
  internal endpoint over `X-Service-Token`, mirroring the existing
  suspend/reactivate pattern, and writes `operator_audit` **only after** a 2xx
  billing response.

Billing's existing entitlement rules are authoritative and are **not**
duplicated in platform-service: `toggle_module` already rejects a
non-active subscription with `SUBSCRIPTION_EXPIRED` and a non-entitled feature
with `FEATURE_NOT_AVAILABLE`. platform-service surfaces those errors as-is.

- **UI:** a list of features with `USwitch` controls. The entitled feature
  list comes from the tenant's plan (`platform_plan_catalog.features`) so the
  operator can see which toggles fall outside the plan's entitlement; those
  render disabled with an explanatory hint rather than failing on submit.

### 4.3 Failed-registration board

`pending_registration` lives in `billing_db`, and platform-service must not
read across databases.

- **New billing endpoint:** `GET /api/v1/billing/internal/registrations?state=`
- **Platform proxy:** `GET /api/v1/platform/registrations`, forwarding over
  `X-Service-Token` — the same proxy pattern already used for `/plans`.
- **No projection.** This is low-volume operational data where freshness is
  the entire point.
- **UI:** a `DataTableCard` with a state filter, highlighting rows stuck for
  more than 15 minutes. Read-only in this phase.

### 4.4 Service health board

- **Endpoint:** `GET /api/v1/platform/health`, fanning out to all six
  `/healthz` endpoints in parallel with a 2-second per-service timeout,
  returning per-service status.
- This is the one place synchronous cross-service calls are correct — that is
  precisely what the endpoint is for.
- **UI:** a card grid with `refetchInterval` of 30 seconds via Vue Query.

### 4.5 Explicitly out of scope for Phase 1

- Storing health history (requires a time-series store).
- Alerting when a service goes down (requires the mailer — Phase 4).
- Any mutation on the registration board (Phase 2, item 8).

## 5. Testing Plan

- Each new platform endpoint gets an integration test in
  `apps/backend/services/platform-service/tests/integration.rs`, following
  the existing pattern.
- Each new Vue Query hook under `app/lib/queries/` gets a Vitest spec.
- One Playwright e2e covering the failed-registration board, as the
  highest-risk operator flow in this phase.
- The module toggle gets an integration test asserting that `operator_audit`
  is written only on a 2xx billing response.
- The projection consumer gets a test asserting that `tenant.module_toggled`
  patches exactly one key in `platform_subscription.modules` and leaves the
  other keys intact.

## 6. Documentation Impact

- `docs/internal/11_integration_contracts/apis/platform-service-api.md` —
  document the five new endpoints.
- `docs/internal/11_integration_contracts/apis/billing-service-api.md` —
  document `GET /internal/registrations` and
  `PATCH /internal/tenants/:id/modules`.
- `docs/internal/11_integration_contracts/events/` — add
  `tenant.module_toggled.md`, following the existing per-event file pattern.
