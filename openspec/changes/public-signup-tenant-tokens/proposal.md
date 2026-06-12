## Why

Two assumptions are baked into IAM today and both must change:

1. **Account creation is invitation-only.** A `"user"` row can only come into
   existence through a tenant invitation or the registration saga. The client
   now wants **public self-service signup**: anyone can create an account with
   email + password, independent of any tenant.

2. **Identity and tenant membership are fused.** The access JWT bakes in exactly
   one `tenant_id` + `role` at login, which only works if every user belongs to
   exactly one tenant. The client confirmed a user can belong to **many**
   tenants (e.g. a teacher at two schools), and — with public signup — a user
   can belong to **zero** tenants at the moment they sign up.

This change **separates identity from membership** into two layers and
introduces a **two-token model** so login no longer needs to know a tenant:

```
  LAYER 1 — IDENTITY      who you are        ← public signup / invitation / Google
  LAYER 2 — MEMBERSHIP    where you act      ← tenant invitation acceptance
```

Login (any method) issues a tenant-less **identity token**. The user then
**enters a tenant** to exchange it for the existing tenant-scoped token. Crucially,
**downstream services are unchanged** — they keep receiving the exact
`{ sub, tenant_id, role }` token they verify today. All new complexity is
quarantined in IAM and the web client.

Depends on [[username-identity-login]] (email-nullable + username identity is the
prerequisite for an account that exists without a tenant or, in
[[google-oauth-login]], without a password).

## What Changes

### Two-token model (`iam-service`)

- **NEW token type — identity token.** Issued by every login method. Claims:
  `{ sub, typ: "identity", iat, exp, jti }`. **No `tenant_id`, no `role`.**
  Short-lived (default 10 min) and **non-refreshable** — it is a stepping stone
  to tenant selection, not a session.
- **Existing token — tenant-scoped token, unchanged shape.** Claims
  `{ sub, tenant_id, role, iat, exp, jti }`. Still 15-min TTL. This is the token
  every other service already verifies; its structure does not change.
- **MODIFIED `POST /auth/login`**: on success returns an **identity token** (plus
  the `/my-tenants` result inlined or a follow-up call), NOT a tenant-scoped
  token. The single-tenant fast path (below) preserves today's UX.

### Tenant selection endpoints (`iam-service`)

- **NEW `GET /my-tenants`** — authenticated by an identity token. Returns the
  caller's memberships: `[{ tenant_id, tenant_name, role_code }]`. Empty array
  for a 0-tenant user.
- **NEW `POST /tenants/{id}/enter`** — authenticated by an identity token.
  Verifies the caller is a member of `{id}` via `user_tenant_role`, then issues a
  **tenant-scoped** access token + a **tenant-scoped refresh token**. Returns the
  standard token envelope. `403` if not a member.
- **Single-tenant fast path**: when `/my-tenants` returns exactly one membership,
  the web client immediately calls `/enter` so the experience matches today
  (log in → land in the app). With zero memberships the client shows the
  0-tenant empty state; with many, a tenant picker. "Switch school" re-invokes
  `/enter` with a different id.

### Tenant-scoped refresh tokens (`iam-service`)

- **MODIFIED `refresh_token` table**: add `tenant_id`. A refresh token is now
  bound to `(user_id, jti, tenant_id)`. Refreshing re-issues a tenant-scoped
  access token **for that same tenant**. Switching tenants mints a fresh
  refresh token via `/enter`; it does not mutate an existing one.
- **MODIFIED `POST /auth/refresh`**: rotates within the token's bound tenant.
- Identity tokens are non-refreshable, so they have no `refresh_token` row.

### Public signup (`iam-service`)

- **NEW `POST /auth/register`** — public, rate-limited. Creates a `"user"` with
  email + password (+ optional username; auto-generated if absent per
  [[username-identity-login]]) and **no tenant membership**. Returns an identity
  token. The account starts in a state that can hold zero tenants.
- **Account creation is decoupled from invitations.** Invitations
  ([[tenant-user-management]]) now grant *membership* to an account (existing or
  newly created in the same transaction), rather than being the only way an
  account can exist.
- **Email verification policy** *(open decision)*: default is **verify-later** —
  the account is usable immediately, `email_verified=false`, with a verification
  email sent when `EMAIL_PROVIDER` is configured. Sensitive actions can be gated
  on verification later. Alternative: block login until verified.

### 0-tenant application state (`web-auth-onboarding`)

- **NEW empty state**: a logged-in user with zero memberships sees a
  "You're not part of any school yet" screen. Auth guards and routing MUST treat
  "authenticated with identity token, no tenant entered" as a valid state that
  can reach only tenant-less routes (`/me`, `/my-tenants`, accept-invitation),
  not tenant-scoped app pages.
- **NEW tenant picker** for users with multiple memberships; **NEW signup page**
  for `POST /auth/register`.

### `GET /me` (`iam-service`)

- **MODIFIED**: continues to return `memberships`, and now MUST work when
  authenticated by an **identity token** (tenant-less). `email` MAY be `null`.

## Capabilities

### Modified Capabilities

- `iam-service`: introduces the identity-token vs tenant-scoped-token split,
  `/my-tenants` and `/tenants/{id}/enter`, tenant-scoped refresh tokens, public
  `/auth/register`, and decouples account existence from tenant membership.
- `web-auth-onboarding`: adds the signup page, tenant picker, single-tenant fast
  path, and the 0-tenant empty state; login now yields an identity token and a
  tenant-selection step.
- `tenant-user-management`: invitations now attach membership to an account that
  may already exist (or is created in the accept transaction), rather than being
  the sole account-creation mechanism.

## Impact

- **Blast radius is contained to IAM + web.** Downstream services keep verifying
  the unchanged tenant-scoped token. This is the central design property and the
  reason Option 2 (token exchange) was chosen over per-request tenant headers.
- **`refresh_token` schema change** (`+ tenant_id`) requires a migration;
  existing refresh tokens are invalidated on deploy (users re-login). Acceptable
  pre-GA.
- **New public attack surface**: `/auth/register` needs rate limiting and abuse
  protection that an invitation-only system never required; unverified emails are
  a spam vector handled by the verification policy.
- **Affected code**: IAM `commands.rs` (login now mints identity token; new
  enter/register commands), `queries.rs` (`/my-tenants`), `http.rs` (routes +
  which token type each accepts), `repo.rs` (refresh token `tenant_id`), JWT
  claims/`typ` handling in `common-auth`; web login/signup/picker/guards.
- **Docs**: login sequence diagram, IAM domain model, ERD (`refresh_token`),
  component diagram, and API contract.

## Open Decisions (defaults chosen, confirm before build)

1. **Email verification on public signup** — default: **verify-later** (account
   usable immediately, `email_verified=false`). Alternative: block login until
   verified.
2. **Identity-token TTL** — default: **10 minutes**, non-refreshable.
   Alternative: shorter (5 min) or give it its own refresh for long picker
   sessions.
3. **Where `/my-tenants` is delivered** — default: a **separate call** after
   login. Alternative: inline the membership list in the login response to save
   a round-trip on the single-tenant fast path.
