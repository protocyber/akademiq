## Context

IAM bakes one `tenant_id` + `role` into the access JWT at login, which assumes
exactly one tenant per user, and only creates accounts via invitation/registration
sagas. Two confirmed requirements break this: public self-service signup (a user
can exist with **zero** tenants) and multi-tenant membership (a user can belong to
**many** tenants). This change separates identity from membership and adopts a
two-token exchange so the tenant choice happens once, after login, without
changing the token every downstream service already verifies.

Depends on [[username-identity-login]] (nullable email + username identity).

## Why two tokens (Option 2), not the alternatives

Three models were considered for "a user with 0..N tenants":

- **Tenant-on-every-request (header `X-Tenant-Id`)** — every downstream service
  must re-validate membership on every call; authz logic spreads everywhere and a
  single missed check is a cross-tenant leak. Rejected.
- **Nullable tenant in one JWT, default to first** — "default to first" is
  meaningless at N>1 and sprinkles null-checks for the 0-tenant case across every
  service. Collapses into Option 2 anyway once N>1. Rejected.
- **Identity token → tenant-scoped token (Option 2)** — the tenant choice is made
  once, at "enter tenant" time; afterwards every service sees the **unchanged**
  `{ sub, tenant_id, role }` token. Multi-tenancy is invisible downstream.
  **Chosen.**

The decisive property: downstream services do not learn about multi-tenancy. All
new complexity lives in IAM and the web client.

## Decisions

### D1 — Token shapes and `typ` claim

```
  identity token        { sub, typ:"identity", iat, exp, jti }      no tenant
  tenant-scoped token   { sub, tenant_id, role, typ:"access", iat, exp, jti }
```

`common-auth` verification MUST reject an identity token on a tenant-scoped route
and vice versa, keyed off `typ`. Tenant-less routes (`/me`, `/my-tenants`,
`/tenants/{id}/enter`, accept-invitation) accept `typ:"identity"`; everything
else requires `typ:"access"` with a `tenant_id`.

### D2 — Identity token is short-lived and non-refreshable

The identity token is a stepping stone, not a session: default TTL 10 min, no
`refresh_token` row. Most users hit the single-tenant fast path and exchange it
within seconds. If a user idles on the tenant picker past expiry, they re-login.
Giving the identity token its own refresh is the documented escape hatch if
picker sessions prove long.

### D3 — Tenant-scoped refresh tokens

```sql
ALTER TABLE refresh_token ADD COLUMN tenant_id UUID NOT NULL;
-- PK / lookup becomes (user_id, jti); tenant_id travels with the row
```

A refresh token is bound to `(user_id, jti, tenant_id)`. `POST /auth/refresh`
re-issues a tenant-scoped access token for **that** tenant. "Switch tenant" is
**not** a refresh — it is a fresh `POST /tenants/{id}/enter` that mints a new
scoped refresh token. Existing refresh rows are invalidated on deploy (the column
is new and `NOT NULL`); users simply re-login. Acceptable pre-GA.

### D4 — `/enter` is the single place tenant scope is granted

`POST /tenants/{id}/enter` verifies membership in `user_tenant_role`
(`WHERE user_id = sub AND tenant_id = {id}`), reads the `role`, and only then
mints the scoped token. This is the *only* path that produces a tenant-scoped
token, so authz for "may this user act in this tenant" is enforced in exactly one
place. `403 FORBIDDEN` when not a member; `404` is avoided to not leak tenant
existence.

### D5 — Single-tenant fast path preserves today's UX

```
  login ─▶ identity token ─▶ GET /my-tenants
                               ├─ 0  ─▶ empty-state screen
                               ├─ 1  ─▶ auto POST /enter ─▶ scoped token ─▶ app
                               └─ N  ─▶ tenant picker ─▶ POST /enter ─▶ app
```

For the common single-tenant user the picker never appears; the client enters the
sole tenant automatically, so the flow feels identical to the current
login-straight-into-app behaviour.

### D6 — Public signup decouples account from membership

`POST /auth/register` creates a `"user"` with no `user_tenant_role` rows and
returns an identity token. Invitations
([[tenant-user-management]]) become a way to **attach membership** to an account —
existing (matched by email) or created inside the accept transaction — rather than
the only way an account can exist. A freshly-registered user is a valid,
authenticated, 0-tenant account.

### D7 — Email verification: verify-later (default)

Public signup sets `email_verified=false` and the account is usable immediately;
a verification email is sent when `EMAIL_PROVIDER` is configured. This keeps
signup frictionless and dovetails with [[google-oauth-login]], where a Google
login proves the email and can flip `email_verified=true`. Blocking login until
verified is the alternative if abuse demands it.

## Risks / Trade-offs

- **Extra round-trip** for tenant selection. Mitigated by the single-tenant fast
  path and the option to inline `/my-tenants` in the login response.
- **Public `/auth/register` attack surface** — rate limiting, and the
  verification policy bound the spam/abuse vector that invitation-only avoided.
- **0-tenant state is genuinely new** — guards, routing, and `/me` must all treat
  "authenticated, no tenant" as valid. A missed guard could either lock out a
  legitimate new user or expose tenant-scoped pages without scope.
- **Refresh-token migration invalidates existing sessions** on deploy. Acceptable
  pre-GA; users re-login once.

## Verified code anchors (from live source)

Verified against `apps/backend/services/iam-service` and `libs/common-auth`:

- **NAME COLLISION — do not reuse `register_user`.** `commands.rs` already has
  `pub async fn register_user(state, RegisterUserInput)` and
  `http.rs::InternalCreateUserBody` → it is the **internal, tenant-scoped**
  user-creation command behind `POST /internal/users` (requires `tenant_id` +
  `role_code`, inserts via `insert_with_role`). The new **public** signup must use
  a distinct name, e.g. `public_register` / `SignupInput` and a distinct route
  `POST /auth/register`. Keep the existing `register_user` for the internal path.
- **`issue_tokens()` hard-requires a tenant.** `commands.rs::issue_tokens(state,
  user)` calls `resolve_membership()`, which returns
  `NO_TENANT_MEMBERSHIP` (403) when the user has no `user_tenant_role`. Today
  `login()`, `refresh()`, and `accept_invitation()` all funnel through it. The
  two-token split requires a **new** issuance path that mints a tenant-less
  identity token **without** calling `resolve_membership` — only
  `POST /tenants/{id}/enter` should call the membership-resolving path. (Note:
  `resolve_membership` already "picks the first membership deterministically",
  with a comment that Phase 1 assumes one membership — this change supersedes
  that assumption.)
- **`common_auth::jwt::Claims` is tenant-mandatory.** Fields are
  `sub: Uuid, tenant_id: Uuid, role: String, iat, exp, jti` — `tenant_id`/`role`
  are **not** optional, and `jwt::issue(user_id, tenant_id, role, ttl)` requires
  them. So "identity token" needs either (a) a second claims type
  (`IdentityClaims { sub, typ, iat, exp, jti }`) + a second `issue_identity()`,
  or (b) making `tenant_id`/`role` `Option` and adding `typ`. **Decision: option
  (a), a separate identity-claims type**, so existing tenant-scoped verification
  stays strict and unchanged. This is a larger `common-auth` change than the
  proposal's "add a `typ` claim" wording implied.
- **`refresh_token`** (created in `V1__init.sql`) PK is `(user_id, jti)`; columns
  `token_hash, issued_at, expires_at, revoked_at`. `RefreshTokenRepo::insert(
  user_id, jti, token_hash, expires_at)` and `find/revoke(user_id, jti)` are the
  methods to extend with `tenant_id`. Migration file is `V7__*.sql` (after Change
  A's `V6`).
- **`http.rs::token_envelope()`** builds `meta.{user_id, tenant_id, role}` from
  `pair.access_claims` — it assumes tenant-scoped claims. The identity-token
  response needs its own envelope shape (no tenant/role).
- **`queries.rs::get_me`/`MeProfile`** must work under an identity token and
  expose `email: Option` + `email_verified`.

## Migration Plan

1. `common-auth`: add a separate identity-claims type + `issue_identity()`, and a
   `typ` discriminator; keep tenant-scoped `Claims`/`issue()` strict and add the
   matching extractor/verification so identity tokens are rejected on
   tenant-scoped routes.
2. IAM migration: `refresh_token.tenant_id` (`NOT NULL`); add `email_verified` to
   `"user"`.
3. IAM commands: login → identity token; new `enter`, `register`; refresh scoped
   to bound tenant.
4. IAM queries/routes: `/my-tenants`, `/tenants/{id}/enter`, `/auth/register`;
   tag each route with the token type it accepts.
5. Web: signup page, tenant picker, single-tenant fast path, 0-tenant empty state,
   guard updates.
6. Docs: sequence diagram, domain model, ERD, component, API contract.

## Open Questions

- Email verification: verify-later (default) vs block-until-verified.
- Identity-token TTL (default 10 min) and whether it ever gets a refresh.
- Inline `/my-tenants` in the login response vs separate call.
