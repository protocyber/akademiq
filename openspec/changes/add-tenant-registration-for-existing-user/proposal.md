## Why

A user who signs up or logs in via Google OAuth is created in IAM with **no
tenant membership** (`insert_user` adds a `user` row but no
`user_tenant_role`). They land on `/tenant-select`, which shows the correct
" Anda belum terdaftar di sekolah mana pun" message — but the only action
available is "Keluar" (logout). There is no path for an authenticated
tenant-less user to register a new school.

The public tenant registration endpoint
(`POST /api/v1/billing/tenants/register`) always creates a **brand-new** IAM
user via `iam_client.create_user` — it has no way to accept an existing
`user_id`. So an authenticated Google user cannot self-service register a
tenant under their existing account.

This means the onboarding dead-ends:

```
Google login → identity token → tenant-select → "not in any school"
                                                    │
                                               [Keluar] only
                                                    │
                                                    ▼
                                              DEAD END
```

## What Changes

- **New backend endpoint: register tenant for authenticated user.**
  `POST /api/v1/billing/tenants/register-for-user` (requires a scoped… no —
  requires an identity/auth token; the caller is already a user). Accepts
  `{ school_name, plan_id }` (NO admin credentials — the user already exists).
  Creates the tenant + subscription, then asks IAM to attach a
  `tenant_admin` membership to the **existing** `user_id` (not create a new
  user). Returns `{ tenant_id, user_id, subscription_id }`.
- **New IAM internal endpoint: attach membership to existing user.**
  `POST /api/v1/iam/internal/users/:id/tenant-membership` (service-token
  protected) accepts `{ tenant_id, role_code }` and inserts a
  `user_tenant_role` row. This is what billing calls instead of `create_user`
  for the existing-user flow.
- **Web: add "Daftar Sekolah Baru" button to `ZeroTenantState`.**
  `tenant-select/page.tsx` `ZeroTenantState` gains a primary button
  "Daftar Sekolah Baru" that navigates to `/register?mode=existing`.
- **Web: register page supports "existing user" mode.**
  `/register?mode=existing` skips step 3 ("Akun Admin") entirely — the wizard
  is 2 steps: school profile → plan. On submit, calls the new
  `register-for-user` endpoint with the identity token. On success, enters
  the new tenant and redirects to `/dashboard`.

## Capabilities

### New Capabilities
- `tenant-registration-for-existing-user`: a self-service flow for an
  authenticated tenant-less user to register a new school under their
  existing account.

### Modified Capabilities
- `billing-service`: gains `register-for-user` command + endpoint (reuses
  tenant/subscription/outbox logic, skips IAM user creation).
- `iam-service`: gains internal endpoint to attach a tenant membership to an
  existing user.
- `web-onboarding-ui`: `ZeroTenantState` gains a registration CTA; register
  wizard supports a 2-step "existing user" mode.

## Impact

- **Backend** (`apps/backend`):
  - `billing-service`: new command `register_tenant_for_user`, new endpoint,
    new `iam_client` method `attach_membership`.
  - `iam-service`: new internal route, new repo method
    `insert_user_tenant_role` (or reuse existing membership insert).
- **Web** (`apps/web`):
  - `tenant-select/page.tsx`: add CTA button.
  - `register/register-client.tsx`: support `?mode=existing` (2-step wizard).
  - `lib/query/mutations/use-register-tenant.ts`: add
    `useRegisterTenantForUser` mutation.
  - `lib/schemas/register.ts`: add `registerExistingUserSchema` (school_name,
    plan_id only).
- **No migration needed** — reuses existing `tenant`, `subscription`,
  `user_tenant_role` tables. No schema changes.
- **Auth model:** the new billing endpoint accepts the user's identity token
  (not a scoped tenant token — the user has no tenant yet). The endpoint
  extracts `user_id` from the token rather than trusting a client-supplied
  id.
