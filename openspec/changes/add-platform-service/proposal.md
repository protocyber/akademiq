## Why

AkademiQ's backend is entirely tenant-scoped: every access token carries a single
`tenant_id` and every service rejects cross-tenant access. There is no way for the
AkademiQ company itself to operate the SaaS — list every school tenant, suspend a
delinquent tenant, manage the subscription-plan catalog, or look up a user across
tenants. The `02_use_cases` docs already name a "SaaS Super Admin" with exactly
these jobs (Manage School Tenants, Manage Subscription Plans, Monitor System
Usage), but nothing in the backend implements them. This change introduces the
missing **platform plane** so the operator-facing admin app
(`add-platform-admin-web`) has a backend to talk to.

## What Changes

- **New `platform-service`** (folder `platform-service`, DB `platform_db`, crate
  `platform_service`, base path `/api/v1/platform`, container `platform-service`,
  port `8087`). It is the cross-tenant control plane: it aggregates a read-model
  over all tenants and exposes operator commands.
- **Operator identity in iam-service**: a platform operator is an account that
  belongs to **no tenant**. iam-service gains a platform-operator login that issues
  a **platform token** (`typ:"platform"`, no `tenant_id`, cross-tenant scope) plus
  a matching refresh token, reusing the existing Argon2 + RS256 + refresh
  machinery. The existing mislabeled `super_admin` role (named "Platform super
  admin" but only granted `academic.config.*` inside a tenant) is left untouched;
  a new `platform_admin` role governs operator access.
- **Operator seeding via CLI**: the first and every operator is created with
  `akademiq platform create-operator` (parameterized email/password). There is **no
  migration-seeded bootstrap account** — that would ship a default credential into
  every environment. The command reuses `common-auth::hash_password`, never prints
  the password or hash, and exits non-zero on no-op.
- **Token-type gating (security-critical)**: `common-auth` MUST validate the `typ`
  claim. The five tenant-scoped services (`iam`, `billing`, `academic-config`,
  `academic-ops`, `grading`) MUST reject `typ:"platform"` tokens, and
  platform-service MUST reject `typ:"access"`/`typ:"identity"` tokens. Without
  this, an operator token becomes a master key over every tenant. **BREAKING** for
  `common-auth`'s verifier contract.
- **Cross-tenant read-model**: `platform_db` is populated by consuming **existing**
  events (`tenant.registered`, `subscription.activated`, `subscription-upgraded`,
  `tenant-user-events`, `student-enrolled`, `teacher-assigned`) into projection
  tables (`platform_tenant`, `platform_subscription`, `platform_user`,
  `platform_tenant_stats`). No cross-DB queries, no physical FKs — same projection
  pattern grading-service already uses.
- **Cross-tenant commands via hybrid ownership**: operator mutations
  (suspend/reactivate tenant, CRUD plan catalog, change a tenant's subscription)
  are **forwarded** to billing/iam over an internal `X-Service-Token` call;
  billing/iam remain the source of truth and emit events. platform-service does not
  duplicate ownership of tenant/plan data.
- **New domain events** for operator actions that flow back to tenant services:
  `tenant.suspended`, `tenant.reactivated` (consumed by billing + iam to block
  login/access), plus plan-catalog change events owned by billing. On
  `tenant.suspended`, iam-service **force-revokes that tenant's active refresh
  tokens** so a suspended tenant's users cannot refresh past one access-token
  lifetime; services also gate on the tenant-status projection.
- **Operator audit log**: every operator action is recorded in `platform_db`
  (`operator_audit`) — distinct from the in-tenant `tenant-audit-log` change.
- **Orchestration + infra**: docker-compose entry, `PLATFORM_PORT` in
  `apps/backend/.env.example`, Traefik `PathPrefix(/api/v1/platform)` router at
  priority 100, and the per-service Makefile targets.

## Capabilities

### New Capabilities
- `platform-service`: the cross-tenant control-plane service — read-model
  aggregation, tenant lifecycle commands, plan-catalog management, subscription
  override, system-usage monitoring, and operator audit log over `platform_db`.
- `platform-operator-auth`: platform-operator accounts, login, and the
  `typ:"platform"` token + refresh model issued by iam-service, including the
  cross-service rule that tenant-scoped services reject platform tokens.

### Modified Capabilities
- `iam-service`: add platform-operator account model, operator login/refresh
  endpoints, the `platform_admin` role, and `typ`-claim verification so tenant
  tokens and platform tokens are not interchangeable.
- `billing-service`: add internal (`X-Service-Token`) operator endpoints for
  cross-tenant tenant lifecycle (suspend/reactivate), plan-catalog CRUD, and
  subscription override; emit the new `tenant.suspended` / `tenant.reactivated`
  and plan-catalog events.

## Impact

- **New service**: `apps/backend/services/platform-service` + `platform_db`
  migrations (refinery) + RabbitMQ projection consumers + outbox.
- **Modified backend**: `libs/common-auth` (`typ` gating — affects all five
  services), `iam-service` (operator accounts/login/role), `billing-service`
  (internal operator endpoints + new events).
- **Contracts**: new `docs/internal/11_integration_contracts/apis/platform-service-api.md`,
  new event docs (`tenant.suspended`, `tenant.reactivated`, plan-catalog events),
  and updates to iam/billing API docs.
- **Infra/orchestration**: `docker-compose.yml`, `apps/backend/.env.example`
  (`PLATFORM_PORT=8087`), `infra/traefik/akademiq.dynamic.yaml`, parent `Makefile`.
- **Consumer of this change**: `add-platform-admin-web` (Nuxt admin frontend)
  depends on the `/api/v1/platform` contract and the operator token model defined
  here.
- **Security**: introduces a cross-tenant trust boundary; the `typ`-gating
  requirement is the primary risk and must be covered by tests in every service.
