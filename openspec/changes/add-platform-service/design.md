## Context

AkademiQ is a multi-tenant SaaS for schools. The backend is five tenant-scoped
services (`iam`, `billing`, `academic-config`, `academic-ops`, `grading`) sharing
strict conventions: one service = one DB, no cross-DB queries, no physical FKs
between services, and cross-service data is replicated via the
event → outbox → RabbitMQ → local-projection pattern. Auth is a two-step exchange:
login yields a tenant-less `typ:"identity"` token, then `POST /tenants/{id}/enter`
yields a `typ:"access"` token that always carries exactly one `tenant_id`. Every
service verifies and trusts that `tenant_id`.

There is no platform plane: no way to operate across all tenants. The
`02_use_cases` docs name a "SaaS Super Admin" (Manage School Tenants, Manage
Subscription Plans, Monitor System Usage) but nothing implements it. The misnamed
`super_admin` role is tenant-scoped (`academic.config.*` only), not an operator
role. This design introduces a cross-tenant control plane to back the
`add-platform-admin-web` Nuxt frontend.

Decisions already locked with the user:
- New `platform-service` (not endpoints bolted onto existing services).
- Operator identity lives in iam-service (reuse Argon2/RS256/refresh), separate
  `typ:"platform"` token rejected by tenant-scoped services.
- Hybrid ownership: billing/iam stay source of truth; platform-service forwards
  mutations via `X-Service-Token` and emits/consumes events.

## Goals / Non-Goals

**Goals:**
- A `platform-service` that aggregates a cross-tenant read-model and exposes
  operator commands, honoring the one-service-one-DB and projection conventions.
- A `typ:"platform"` operator token issued by iam-service that is structurally
  incapable of acting as a tenant token, and vice versa.
- Reuse existing events for reads; add only the events needed for operator-driven
  state changes (`tenant.suspended`, `tenant.reactivated`, plan-catalog events).
- An operator audit trail distinct from the in-tenant audit log.

**Non-Goals:**
- Moving ownership of tenant status, the plan catalog, or subscriptions out of
  billing-service (rejected: large refactor of a working service).
- Implementing impersonation, hard-delete/GDPR purge, invoicing, or
  announcement-broadcast in this change (future capabilities; flagged in
  exploration).
- Building the Nuxt admin frontend (separate change `add-platform-admin-web`).
- Changing the meaning or permissions of the existing `super_admin` role.

## Decisions

### D1. New service over endpoints on existing services
The platform plane inverts the security mental model ("see all tenants" vs "reject
non-mine"). Mixing both in one service risks a single mis-gated route leaking
cross-tenant data. A separate service gives a clean trust boundary, its own DB for
aggregated projections (which cross-DB rules otherwise forbid), and an isolated
operator audit log. *Alternative considered:* `/admin/*` routes on billing+iam —
rejected for blast-radius and convention violations.

### D2. Operator identity in iam-service, separate token type
Operators are IAM accounts with the new `platform_admin` role and zero tenant
memberships. iam-service gains an operator login that issues `typ:"platform"`
tokens (no `tenant_id`) plus a platform refresh token, reusing existing hashing,
RS256 signing, and refresh rotation. *Alternative considered:* standalone auth in
platform-service — rejected because it duplicates mature, security-sensitive
machinery.

### D3. Token-type gating is mandatory and central (security-critical)
`common-auth` must validate the `typ` claim, not just the signature. Tenant-scoped
services reject `typ:"platform"`; platform-service rejects `typ:"access"`/
`identity`/`refresh`. This is the single most important correctness property: if a
platform token were accepted by tenant services it becomes a master key. The
verifier API should require the caller to declare the expected plane so the default
is deny.

### D4. Hybrid ownership — forward mutations, own only the read-model + audit
platform_db holds projections (`platform_tenant`, `platform_subscription`,
`platform_user`, `platform_tenant_stats`) and `operator_audit`. It does **not**
own tenant status, plan catalog, or subscriptions. Operator commands forward to
billing/iam via `X-Service-Token`; those services mutate and emit events, which
platform-service then consumes to update its projection. *Alternative considered:*
full control-plane ownership in platform_db — rejected (moves source of truth out
of billing, large refactor).

### D5. Reads from existing events; new events only for operator state changes
Reads reuse `tenant.registered`, `subscription.activated`, `subscription-upgraded`,
`tenant-user-events`, `student-enrolled`, `teacher-assigned`. New events:
`tenant.suspended`, `tenant.reactivated` (emitted by billing, consumed by
billing-internal + iam to block login/access + platform projection), plus
plan-catalog change events owned by billing.

### D6. Service identity, port, and routing
Folder `platform-service`, DB `platform_db`, crate `platform_service`, base path
`/api/v1/platform`, container `platform-service`, port `8087` (8081–8086 taken).
Traefik gets a `PathPrefix(/api/v1/platform)` router at priority 100; the admin
frontend is reached by a host router for `admin.akademiq.web.id`.

```
            ┌──────── admin.akademiq.web.id (Nuxt, separate change) ────────┐
            │                       typ:"platform" token                     │
            ▼                                                                 ▼
   ┌──────────────┐    operator login/refresh    ┌───────────────────────────────┐
   │  iam-service │◀────────────────────────────▶│        platform-service        │
   │ +platform_   │   X-Service-Token (cmds)      │  platform_db: projections +    │
   │  admin role  │◀─────────────┐                │  operator_audit                │
   └──────┬───────┘              │                └──────────────┬────────────────┘
          │ emit                 │  X-Service-Token (cmds)        │ consume events
          ▼                      ▼                                ▼
       RabbitMQ ◀────── billing-service (owns tenant/plan/sub) ──▶ RabbitMQ
```

### D7. Local-dev orchestration
Add `PLATFORM_PORT=8087` to `apps/backend/.env.example`, a docker-compose entry,
the service to `make dev` / `make test` / `make build`, and the Traefik mapping —
in lockstep per AGENTS.md's "adding a new backend service" rule.

### D8. Operator seeding via CLI, never via migration
The first (and every) platform operator is created with an `akademiq platform
create-operator` CLI command, not a migration-seeded bootstrap account. Rationale:
a migration-seeded account ships a known/default credential into every environment
(a standing breach), whereas the CLI takes the email/password as parameters at
provisioning time. This honors the Akademiq CLI guardrails — the command reuses
`common-auth::hash_password`, prints the created operator's identifier but **never**
the password or hash, and exits non-zero if no account was created (e.g. duplicate
email). It performs a narrow IAM admin task (insert an operator user + grant
`platform_admin`), which is an allowed direct-SQL use per the guardrails since no
domain event is required. *Alternative considered:* migration bootstrap account —
rejected (default credentials, can't rotate per environment, secret would live in
version control or env defaults).

### D9. Suspend force-revokes tenant refresh tokens immediately (defense in depth)
When a tenant is suspended, iam-service consumes `tenant.suspended` and
**immediately revokes all active refresh tokens scoped to that tenant**, in addition
to services checking the tenant-status projection. Rationale: access tokens are
short-lived (15 min default) but refresh tokens last 7 days; relying on TTL alone
leaves a suspended tenant's users able to refresh for up to a week. Revoking refresh
tokens caps the blast radius to one access-token lifetime — a user with a live
access token can finish at most ~15 minutes, then cannot refresh. We deliberately do
**not** try to invalidate already-issued access tokens (stateless RS256 JWTs);
instead tenant services SHOULD also gate on the local tenant-status projection so a
suspended tenant is blocked even within that window. Reactivation does not
un-revoke; users simply log in / `/enter` again. *Alternatives considered:* (a)
TTL-only — rejected (7-day refresh window); (b) per-request status check only —
keeps the refresh token alive and adds a hot-path projection read everywhere;
combining revoke + projection gate is the balanced choice.

## Risks / Trade-offs

- **A platform token accepted by a tenant service = full breach** → centralize
  `typ` gating in `common-auth` with deny-by-default; add an explicit
  cross-service test in every service asserting rejection of the wrong `typ`.
- **Projection lag** (operator suspends, projection updates slightly later) →
  return downstream command result synchronously for the action's success/failure;
  treat the projection as eventually-consistent for the directory view; document
  it.
- **Hybrid forwarding doubles failure modes** (platform→billing call can fail) →
  only write a success audit row after a 2xx downstream response; surface
  downstream errors verbatim through the standard error envelope.
- **`X-Service-Token` shared secret sprawl** → reuse the existing internal
  service-token convention (as billing↔iam already do); do not invent a new
  mechanism; never log the token.
- **Idempotency of suspend/reactivate** → billing treats repeat calls as no-ops and
  does not emit duplicate state-change events.
- **Naming confusion with `super_admin`** → explicitly leave `super_admin`
  untouched; operator role is `platform_admin`; document the distinction in the
  iam spec delta.
- **Refresh-token revocation must be tenant-scoped** (D9) → the suspend consumer
  revokes only refresh tokens whose `tenant_id` matches the suspended tenant; a user
  who also belongs to other tenants keeps those sessions. Revocation must be
  idempotent (re-delivered `tenant.suspended` is a no-op).
- **Operator bootstrap on a fresh environment** (D8) → since there is no seeded
  account, document that an operator must be created via `akademiq platform
  create-operator` before the admin app is usable; `make doctor` / setup docs note
  this so a fresh deploy isn't mistaken for a broken one.

## Migration Plan

1. `common-auth`: add `typ`-aware verification (deny-by-default); update all five
   services to declare their expected plane. Land + test first — it is the safety
   gate everything else depends on.
2. iam-service: `platform_admin` role migration, operator account model, operator
   login/refresh endpoints issuing `typ:"platform"`, `tenant.suspended` consumer
   that tenant-scoped force-revokes refresh tokens (D9), and the
   `akademiq platform create-operator` CLI command (D8).
3. billing-service: internal `X-Service-Token` operator endpoints (suspend,
   reactivate, plan CRUD, subscription override) + new outbox events.
4. platform-service: scaffold (refinery migrations, `platform_db`), projection
   consumers for existing + new events, read APIs, command APIs that forward to
   billing/iam, `operator_audit`, `/healthz`.
5. Orchestration: docker-compose, `.env.example`, Makefile, Traefik mapping.
6. Contracts/docs: new `platform-service-api.md`, new event docs, iam/billing API
   doc updates; document the CLI bootstrap step for fresh environments.

Rollback: platform-service and the operator login are additive; disabling the
Traefik route and not seeding any `platform_admin` account makes the plane
unreachable. The `common-auth` `typ`-gating change is the only one that touches
existing services and must be backward-compatible for `typ:"access"`/`identity`.

## Resolved Decisions

- **Operator seeding** → resolved as **D8**: CLI command
  `akademiq platform create-operator`, no migration-seeded account.
- **Refresh-token revocation on suspend** → resolved as **D9**: `tenant.suspended`
  force-revokes that tenant's refresh tokens in iam, combined with a tenant-status
  projection gate at the services.

## Open Questions

- Plan-catalog events: confirm exact names/shapes with the existing
  `subscription.activated` / `subscription-upgraded` conventions before finalizing
  event docs.
