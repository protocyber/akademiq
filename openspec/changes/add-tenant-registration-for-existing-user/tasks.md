# Tasks: add-tenant-registration-for-existing-user

Backend submodule `apps/backend`, web submodule `apps/web`.

## 1. IAM — internal membership attach endpoint

- [x] 1.1 In `iam-service/src/repo.rs`, add (or reuse)
      `insert_user_tenant_role(user_id, tenant_id, role_id)` that inserts a
      `user_tenant_role` row; return conflict if already exists.
- [x] 1.2 In `iam-service/src/http.rs`, add route
      `POST /api/v1/iam/internal/users/:id/tenant-membership` → handler
      `attach_membership`; protected by `X-Service-Token`.
- [x] 1.3 Body: `{ tenant_id, role_code }`; validate user exists (404
      `USER_NOT_FOUND`), validate role_code, insert membership (409
      `MEMBERSHIP_ALREADY_EXISTS` on duplicate).
- [ ] 1.4 Integration test: attach succeeds; duplicate returns 409; unknown
      user returns 404; missing token returns 401.

## 2. Billing — iam_client.attach_membership

- [x] 2.1 In `billing-service/src/iam_client.rs`, add
      `attach_membership(&self, user_id, tenant_id, role_code) ->
      Result<(), AppError>` calling the new IAM endpoint.
- [x] 2.2 Map IAM error responses (404, 409, 401) to appropriate
      `AppError` variants.

## 3. Billing — register_tenant_for_user command

- [x] 3.1 In `billing-service/src/commands.rs`, add
      `register_tenant_for_user(state, input, user_id)` that:
      - validates `{ school_name, plan_id }`
      - inserts `pending_registration`
      - creates tenant + subscription + outbox events in one tx (reuse
        existing logic from `register_tenant`)
      - calls `iam_client.attach_membership(user_id, tenant_id,
        "tenant_admin")`
      - on IAM failure: compensate by deleting/rolling back the tenant
- [x] 3.2 Extract the shared tenant+subscription+outbox tx logic from
      `register_tenant` into a helper to avoid duplication.

## 4. Billing — endpoint

- [x] 4.1 In `billing-service/src/http.rs`, add
      `POST /api/v1/billing/tenants/register-for-user`.
- [x] 4.2 The handler MUST require an identity bearer token (not a scoped
      tenant token), extract `user_id` from the JWT `sub` claim, and pass it
      to `register_tenant_for_user`.
- [x] 4.3 Body: `{ school_name, plan_id }` (no admin credentials).
- [x] 4.4 Return `{ tenant_id, user_id, subscription_id }` on success.
- [ ] 4.5 Integration test: authenticated tenant-less user registers;
      unauthenticated returns 401; missing fields return VALIDATION_ERROR.

## 5. Web — ZeroTenantState CTA

- [x] 5.1 In `tenant-select/page.tsx` `ZeroTenantState`, add a primary
      "Daftar Sekolah Baru" button (variant="default") that navigates to
      `/register?mode=existing`. Place it above the "Keluar" button.
- [x] 5.2 The "Keluar" button remains as a secondary/outline button.

## 6. Web — register existing-user mode

- [x] 6.1 In `register/register-client.tsx`, read `mode` from
      `useSearchParams()`. When `mode === "existing"`, set STEPS to 2
      (school, plan) and skip the admin step.
- [x] 6.2 In `lib/schemas/register.ts`, add `registerExistingUserSchema`
      with `{ school_name, plan_id }` only.
- [x] 6.3 In `lib/query/mutations/use-register-tenant.ts`, add
      `useRegisterTenantForUser` mutation → POST
      `/billing/tenants/register-for-user`, authenticated (identity token),
      body `{ school_name, plan_id }`.
- [x] 6.4 On success: call `enterTenant(tenant_id)` with the returned
      `tenant_id`, then redirect to `/dashboard`.
- [x] 6.5 Guard: if `mode=existing` but user is not authenticated, redirect
      to `/login`.

## 7. Verification

- [ ] 7.1 `make test` (backend + web) green — backend portion skipped by apply; run manually using the command below.
- [ ] 7.1a Web checks: `cd apps/web && bun run lint && bun run typecheck` green.
- [ ] 7.2 End-to-end: Google login → tenant-select → "Daftar Sekolah Baru"
      → 2-step wizard → dashboard as tenant_admin of the new tenant.
- [ ] 7.3 Confirm no new IAM user is created (same user_id before and
      after).

## Manual Backend Tests

Run this manually after implementation (skipped by `/opsx-apply`):

```sh
cd apps/backend && make test
```
