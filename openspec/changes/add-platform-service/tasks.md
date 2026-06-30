## 1. Token-type gating in common-auth (safety gate — land first)

- [ ] 1.1 Add a `typ`-aware verification API to `common-auth` (e.g. `verify_for_plane(expected_typ)`), deny-by-default when `typ` is absent or unexpected
- [ ] 1.2 Define the `typ:"platform"` claim shape (no `tenant_id`, carries operator scope/role) alongside existing `identity`/`access`/`refresh`
- [ ] 1.3 Update iam, billing, academic-config, academic-ops, grading middleware to declare expected plane and reject `typ:"platform"`
- [ ] 1.4 Add a cross-service test in each of the five services asserting a valid-signature `typ:"platform"` token is rejected on a protected route
- [ ] 1.5 Add a `common-auth` unit test matrix covering accept/reject for every `typ` × expected-plane combination

## 2. iam-service: platform-operator identity

- [ ] 2.1 Refinery migration seeding the `platform_admin` system role (leave `super_admin` untouched)
- [ ] 2.2 Operator account model: IAM user with `platform_admin`, zero tenant memberships; password via `common-auth::hash_password`
- [ ] 2.3 Operator login endpoint issuing a `typ:"platform"` access token (no `tenant_id`) + platform refresh token
- [ ] 2.4 Operator refresh endpoint that rotates the platform refresh token and reissues a `typ:"platform"` access token
- [ ] 2.5 Reject operator login for accounts lacking `platform_admin`
- [ ] 2.6 `akademiq platform create-operator` CLI command (parameterized email/password, reuse `common-auth::hash_password`, never prints secrets/hashes, non-zero exit on duplicate/no-op) — the ONLY way operators are created (no migration seed)
- [ ] 2.7 `tenant.suspended` consumer in iam: tenant-scoped force-revoke of active refresh tokens, idempotent on re-delivery, leaves other-tenant sessions intact
- [ ] 2.8 Integration tests: successful operator login/refresh, non-operator rejected, tenant route rejects platform token
- [ ] 2.9 Tests for D8/D9: fresh DB has no operator until CLI run; duplicate-email CLI exits non-zero; suspend revokes only the suspended tenant's refresh tokens; re-delivered suspend is a no-op

## 3. billing-service: internal operator endpoints + events

- [ ] 3.1 Internal endpoints gated by `X-Service-Token` (reject with `UNAUTHORIZED_SERVICE_CALL` when missing/wrong)
- [ ] 3.2 Suspend tenant endpoint: flip status, emit `tenant.suspended` via outbox, idempotent no-op when already suspended
- [ ] 3.3 Reactivate tenant endpoint: restore status, emit `tenant.reactivated` via outbox
- [ ] 3.4 Plan-catalog CRUD endpoints: create/update/deactivate, reject duplicate `code` with 409, emit plan-catalog event
- [ ] 3.5 Subscription-override endpoint: change a tenant's plan, reject unknown plan with `UNKNOWN_PLAN`, emit subscription-change event
- [ ] 3.6 Define new event payloads + outbox wiring; author event docs under `11_integration_contracts/events/`
- [ ] 3.7 Integration tests for each internal endpoint incl. service-token rejection and idempotency

## 4. platform-service: scaffold

- [ ] 4.1 Scaffold `apps/backend/services/platform-service` (crate `platform_service`, Axum, common-* libs)
- [ ] 4.2 Refinery migrations for `platform_db`: `platform_tenant`, `platform_subscription`, `platform_user`, `platform_tenant_stats`, `operator_audit`
- [ ] 4.3 Wire `common-auth` to require `typ:"platform"` on all protected routes; reject `access`/`identity`/`refresh`
- [ ] 4.4 `GET /api/v1/platform/healthz` returning standard envelope after `SELECT 1`
- [ ] 4.5 Per-service Makefile targets: `dev`, `migrate`, `test`, `build`, `up`, `down`

## 5. platform-service: projection consumers

- [ ] 5.1 RabbitMQ consumer for `tenant.registered` → upsert `platform_tenant`
- [ ] 5.2 Consume `subscription.activated` + `subscription-upgraded` → upsert `platform_subscription`
- [ ] 5.3 Consume `tenant.suspended` + `tenant.reactivated` → update `platform_tenant` status
- [ ] 5.4 Consume `tenant-user-events` → upsert `platform_user` with tenant memberships
- [ ] 5.5 Consume `student-enrolled` + `teacher-assigned` → maintain counts in `platform_tenant_stats`
- [ ] 5.6 Consume plan-catalog events → maintain a local plan catalog projection
- [ ] 5.7 Consumer tests: re-delivery is a no-op (idempotent upsert)

## 6. platform-service: read APIs

- [ ] 6.1 `GET /tenants` paginated directory from `platform_tenant`
- [ ] 6.2 `GET /tenants/{id}` detail (profile + subscription + modules + stats), 404 when absent
- [ ] 6.3 `GET /users?email=` cross-tenant user lookup with memberships
- [ ] 6.4 `GET /tenants/{id}/usage` (or equivalent) from `platform_tenant_stats`
- [ ] 6.5 `GET /audit` read-only operator audit listing (no mutate/delete API)

## 7. platform-service: command APIs (forward to owners)

- [ ] 7.1 `POST /tenants/{id}/suspend` → call billing internal suspend; audit on 2xx only
- [ ] 7.2 `POST /tenants/{id}/reactivate` → call billing internal reactivate; audit on 2xx only
- [ ] 7.3 Plan-catalog CRUD endpoints → forward to billing; surface 409 on duplicate code
- [ ] 7.4 `POST /tenants/{id}/subscription` override → forward to billing
- [ ] 7.5 Audit-write helper: record actor `sub`, action, target, outcome; skip on downstream failure
- [ ] 7.6 Standard envelope + `VALIDATION_ERROR` field map on invalid payloads
- [ ] 7.7 Integration tests incl. downstream-failure path (no success audit, error surfaced)

## 8. Orchestration, infra, and contracts

- [ ] 8.1 `apps/backend/.env.example`: add `PLATFORM_PORT=8087` (+ service token slot if new)
- [ ] 8.2 `docker-compose.yml`: add `platform-service` + `platform_db` wiring
- [ ] 8.3 Parent `Makefile`: include platform-service in `dev`, `test`, `build`, `migrate`
- [ ] 8.4 `infra/traefik/akademiq.dynamic.yaml`: `PathPrefix(/api/v1/platform)` router at priority 100 + service entry
- [ ] 8.5 Author `docs/internal/11_integration_contracts/apis/platform-service-api.md`
- [ ] 8.6 Update iam + billing API docs with the new operator/internal endpoints
- [ ] 8.7 Update `docs/internal` use-case / container docs to reflect the implemented platform plane

## 9. Verification

- [ ] 9.1 Run backend test suite (`make test` / per-service) and fix failures
- [ ] 9.2 Manual smoke: create operator via CLI, login, list tenants, suspend a test tenant, confirm `tenant.suspended` consumed and projection updated
- [ ] 9.3 Confirm a tenant access token is rejected by `/api/v1/platform` and a platform token is rejected by all five tenant services
