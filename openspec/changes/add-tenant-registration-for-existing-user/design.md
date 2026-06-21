## Context

The IAM model separates **identity** from **tenancy**:

```
user (identity)           user_tenant_role (membership)
┌──────────────┐          ┌──────────────────────────────┐
│ user_id (PK) │◄────────┤ user_id (FK)                 │
│ email        │          │ tenant_id (FK)               │
│ google_sub   │          │ role_id (FK)                 │
│ password_hash│          └──────────────────────────────┘
└──────────────┘
```

A Google-OAuth user gets an `identity token` (no tenant scope). They can call
`GET /my-tenants` to list memberships. If empty, they're stuck — the only
tenant-creation path (`POST /billing/tenants/register`) is public and always
creates a new user.

### The gap

```
Current register flow (public):
  billing.tenants/register
    └─ iam_client.create_user(email, password, full_name, ...)
         └─ INSERT user + user_tenant_role   ◀── creates NEW user

Needed flow (authenticated existing user):
  billing.tenants/register-for-user   (identity token → user_id)
    └─ iam_client.attach_membership(user_id, tenant_id, "tenant_admin")
         └─ INSERT user_tenant_role ONLY      ◀── attaches to EXISTING user
```

The billing `register_tenant` saga (commands.rs:37-180) does:
1. Insert `pending_registration`
2. `iam_client.create_user` → new user_id
3. Begin tx → insert tenant + subscription + outbox events → commit
4. On failure: compensating `iam_client.delete_user`

The new flow reuses steps 1, 3 (tenant/subscription/outbox) but replaces
step 2 with `attach_membership` and step 4's compensation with
`detach_membership` (or just leave the membership — the tenant doesn't exist
if we roll back, so the FK is invalid anyway).

### Auth constraint

The new endpoint must NOT accept a client-supplied `user_id`. It extracts the
identity from the token. The existing `apiFetch` already supports
`authenticated: true` (sends the bearer token). The backend extracts the
`user_id` claim from the identity token.

## Goals / Non-Goals

**Goals:**
- An authenticated tenant-less user (Google or password) can register a new
  school in self-service, without logging out and creating a new account.
- The flow reuses all existing tenant/subscription/outbox logic — no
  duplication of the saga.
- The user's existing identity (email, name, google_sub) is preserved; no
  new user row is created.
- After registration, the user enters the new tenant as `tenant_admin`.

**Non-Goals:**
- Multi-tenant invitation workflow changes (covered by
  `fix-public-invitation-and-single-tenant-redirect`).
- Changing the public registration flow (it remains for truly new users).
- Adding a password to Google-only users (separate concern; the register
  flow doesn't need a password).
- Changing the 3-step wizard for the public flow.

## Decisions

### Decision 1: New endpoint, not a flag on the existing one

Create `POST /billing/tenants/register-for-user` as a separate endpoint
rather than overloading `/register` with an optional `user_id`/token. The
two flows have different inputs (no admin credentials vs. required),
different auth (public vs. identity token), and different IAM calls
(create_user vs. attach_membership). Separate endpoints keep the handlers
clean and the OpenAPI contract explicit.

*Alternative rejected:* add `existing_user_id: Option<Uuid>` to
`RegisterTenantInput`. Rejected because it conflates two auth models
(anonymous vs. authenticated) in one handler and risks a public caller
supplying an arbitrary user_id.

### Decision 2: Billing calls a new IAM internal endpoint

New IAM internal endpoint:
`POST /api/v1/iam/internal/users/:id/tenant-membership`
Body: `{ tenant_id, role_code }`
Protected by `X-Service-Token` (same as existing internal endpoints).

Billing's `iam_client` gains `attach_membership(user_id, tenant_id,
role_code)`. The IAM handler inserts a `user_tenant_role` row (reusing the
existing repo logic for membership insertion). If the user already has a
membership in that tenant, IAM returns a conflict (shouldn't happen for a
new tenant, but defensive).

*Alternative rejected:* billing directly inserts into `user_tenant_role` via
cross-DB. Rejected — violates the service boundary (billing owns
tenant/subscription, IAM owns users/memberships/roles).

### Decision 3: Extract user_id from identity token

The new endpoint requires `Authorization: Bearer <identity_token>`. The
handler decodes the token (already supported by IAM's JWT verification
infra) and extracts the `sub` (user_id) claim. This is the user who becomes
the `tenant_admin` of the new tenant.

The endpoint does NOT require a scoped tenant token (the user has no tenant
yet). It accepts an identity token specifically. The web client's `apiFetch`
already supports this via `authenticated: true`.

### Decision 4: Frontend wizard skips step 3 in existing-user mode

`/register?mode=existing` renders a 2-step wizard:
1. Profil sekolah (school_name)
2. Pilih plan (plan_id)

No "Akun Admin" step. The submit calls `register-for-user`. On success:
- The response includes `tenant_id`.
- The client calls `enterTenant(tenant_id)` to get a scoped token.
- Redirects to `/dashboard`.

```
/register (public, 3 steps):      /register?mode=existing (2 steps):
┌────────────────────┐            ┌────────────────────┐
│ 1. Profil sekolah  │            │ 1. Profil sekolah  │
│ 2. Pilih plan      │            │ 2. Pilih plan      │
│ 3. Akun admin      │            │   [Daftar sekolah] │
│    [Daftar sekolah]│            └────────────────────┘
└────────────────────┘
```

## Risks / Trade-offs

- **[Risk] User registers a tenant but IAM attach fails** → orphan tenant.
  *Mitigation:* compensation — billing deletes the tenant/subscription (or
  marks pending_registration failed). Same pattern as existing saga's
  `delete_user` compensation.
- **[Risk] User already has a tenant but hits this flow** → they'd create a
  second tenant. *Mitigation:* this is by design (multi-tenant support);
  the tenant-select page already shows multiple tenants. No restriction
  needed.
- **[Risk] Identity token expiry** → the flow requires a valid identity
  token. *Mitigation:* the web client already refreshes on 401. If the token
  is truly invalid, the user is redirected to `/login`.
- **[Trade-off] Two register endpoints** → slight API surface bloat.
  Accepted: the separation is cleaner than a flag.

## Migration Plan

1. **IAM:** add internal endpoint + repo method. Deploy.
2. **Billing:** add `iam_client.attach_membership`, add
   `register_tenant_for_user` command, add endpoint. Deploy.
3. **Web:** add `ZeroTenantState` CTA, add `?mode=existing` wizard, add
   `useRegisterTenantForUser` mutation. Deploy.
4. **Verify:** Google login → tenant-select → "Daftar Sekolah Baru" →
   2-step wizard → dashboard as tenant_admin.

## Open Questions

- Should the existing-user register endpoint also set the user's `full_name`
  if it's currently empty (e.g. Google user with no profile)? Lean: no —
  keep the flow minimal; profile completion is a separate step
  (`add-user-profile` change).
- Should the new tenant be immediately "entered" (scoped token issued) by
  the register endpoint, or should the client call `enter` separately? Lean:
  client calls `enter` separately — keeps the register endpoint focused on
  tenant creation and reuses the existing enter flow.
