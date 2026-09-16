# IAM Service API

Base path: `/api/v1/iam`. All endpoints follow the standard envelopes
from `13_engineering_standards/03_api_conventions.md`:

- Success: `{ "data": {...}, "meta": {...} }`
- Error: `{ "error": { "code": "...", "message": "...", "fields?": {...} } }`

Validation errors use `code = "VALIDATION_ERROR"` and a `fields` map
keyed by request-body field name, per
`13_engineering_standards/14_validation_contract.md`.

## Token model

Login is a **two-step exchange**:

1. **Login** (email/username/Google) → a tenant-less **identity token**
   (`{ sub, typ:"identity" }`, short-lived, non-refreshable). It authorizes only
   tenant-less routes: `GET /me`, `GET /my-tenants`, `POST /tenants/{id}/enter`,
   and invitation acceptance.
2. **Enter a tenant** (`POST /tenants/{id}/enter`) → a **tenant-scoped token**
   (`{ sub, tenant_id, roles, perms, typ:"access" }`) plus a tenant-scoped
   refresh token. This is the token every other service verifies.

A user may belong to zero, one, or many tenants. Refresh tokens are scoped to a
tenant; switching tenants is a fresh `/enter`, not a refresh.

**Lifetimes** (defaults; all configurable via env on iam-service):

| Token | Env var | Default | Refreshable |
| --- | --- | --- | --- |
| identity | `IDENTITY_TOKEN_TTL_SECONDS` | 600 (10 min) | no — re-login |
| access | `ACCESS_TOKEN_TTL_SECONDS` | 900 (15 min) | yes — via refresh token |
| refresh | — | 7 days | rotated on each refresh |
| platform | `ACCESS_TOKEN_TTL_SECONDS` | 900 (15 min) | yes — via platform refresh |

Platform operators use a separate `typ:"platform"` token with no `tenant_id`.
Tenant-scoped services reject platform tokens; platform-service rejects tenant,
identity, and refresh tokens.

Because the identity token is short-lived and non-refreshable, clients SHOULD
switch to the tenant-scoped access token once a tenant has been entered (e.g. for
`/me`), so an expired token triggers a silent refresh rather than a forced logout.

## Auth endpoints

### `POST /auth/login`

Authenticate by email **or** username. The server classifies `identifier` by the
presence of `@` (contains `@` → email lookup; otherwise → username lookup).

Request:

```json
{ "identifier": "string", "password": "string" }
```

Success (200) — returns an **identity token**:

```json
{
  "data": {
    "identity_token": "<RS256 JWT, typ=identity>",
    "expires_in": 600
  },
  "meta": { "user_id": "uuid" }
}
```

The client then calls `GET /my-tenants` and `POST /tenants/{id}/enter` to obtain a
tenant-scoped token (see below).

Errors:

| Code                  | HTTP | Cause |
|-----------------------|------|-------|
| `VALIDATION_ERROR`    | 400  | Missing or malformed fields. |
| `INVALID_CREDENTIALS` | 401  | Identifier unknown, password mismatch, **or the account has no password set** (passwordless invite accept or Google-only). Identical body and timing for every case; a no-password account is never distinguishable. Route no-password detection off `GET /me`'s `password_set` flag, not the login error. |
| `USER_INACTIVE`       | 403  | User exists but `status != 'active'`. |

> **BREAKING:** the distinct `PASSWORD_NOT_SET` code was removed from login.
> A no-password account now returns `INVALID_CREDENTIALS`, exactly like a
> wrong password, to eliminate account enumeration. Clients that branched on
> `PASSWORD_NOT_SET` (the web `login` page) must route off `password_set`
> from `GET /me` instead.

### `POST /auth/register`

Public, rate-limited. Creates an account with **no** tenant membership and returns
an identity token. `username` is optional (auto-generated when absent).

Request:

```json
{ "email": "string", "password": "string", "username": "string?", "full_name": "string" }
```

Success (201): same identity-token envelope as `/auth/login`. The account starts
with `email_verified=false` and is usable immediately (verify-later).

Errors: `VALIDATION_ERROR` (400), `EMAIL_ALREADY_EXISTS` (409),
`USERNAME_TAKEN` (409).

### `GET /auth/google/start`

Public. Generates `state` + PKCE, stores the verifier server-side with a short
TTL, and redirects the browser to Google consent. Requires IAM-only environment
configuration: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and
`GOOGLE_REDIRECT_URI`.

Success: temporary redirect to Google with `response_type=code`, `scope=openid
email profile`, `state`, `code_challenge`, and `code_challenge_method=S256`.

Errors: `GOOGLE_OAUTH_DISABLED` (400) when Google OAuth env is not configured.

### `GET /auth/google/callback`

Public. Validates `state`, exchanges the code server-side, verifies the Google ID
token (JWKS, `aud`, `iss`, expiry), resolves the account
(match `google_sub` → verified-email auto-link → auto-provision), issues an
**identity token**, and redirects to the web app. The client secret and Google's
tokens are never exposed to the browser.

Success: temporary redirect to `${PUBLIC_WEB_BASE_URL}/auth/callback` with
`identity_token=<IAM identity JWT>`.

Failure: temporary redirect to `${PUBLIC_WEB_BASE_URL}/auth/callback` with
`oauth_error=<code>`. Stable callback error codes include `invalid_state`,
`exchange_failed`, `verification_failed`, `missing_code`, and `google_denied`.

Account resolution rules:

1. Existing `google_sub` logs in the matching user.
2. If no `google_sub` match and Google reports `email_verified=true`, a matching
   email account is auto-linked (`google_sub` stored and `email_verified=true`).
3. Otherwise IAM auto-provisions a user with generated `username`, Google email,
   `email_verified=true`, `password_hash=NULL`, `google_sub` set, and no tenant
   membership. If an unverified Google email collides with an existing account,
   IAM refuses rather than linking that account.

### `POST /auth/refresh`

Authenticated by the **refresh token alone** — no access token required. The
handler resolves the owning user from the refresh token's embedded `jti`, so an
expired (or absent) access token does not block refresh. Any `Authorization`
header is ignored.

Request body:

```json
{ "refresh_token": "<jti>.<random>" }
```

Returns a rotated **tenant-scoped** token envelope for the refresh token's bound
tenant (it cannot change tenants). Old `(user_id, jti)` row is marked revoked.

Errors: `INVALID_REFRESH_TOKEN` (401), `EXPIRED_REFRESH_TOKEN` (401).

### `POST /auth/logout`

Body: `{ "refresh_token": "..." }`. Revokes the refresh token by its `jti` and
returns 204. Like refresh, it requires no live access token.

## Platform operator auth

Operators are IAM users with `platform_admin` and zero tenant memberships. They
are created only with `akademiq platform create-operator`; migrations never seed a
bootstrap operator account.

### `POST /platform/auth/login`

Request:

```json
{ "identifier": "operator@example.com", "password": "string" }
```

Success: returns a `typ:"platform"` access token with no `tenant_id` and a
platform refresh token. Non-operators receive `INVALID_CREDENTIALS`/`FORBIDDEN`
and no platform token.

### `POST /platform/auth/refresh`

Request:

```json
{ "refresh_token": "<jti>.<random>" }
```

Success: rotates the platform refresh token and returns a new `typ:"platform"`
access token. Platform refresh tokens are not tenant-scoped.

## Tenant selection endpoints

Authenticated by an **identity token or a tenant-scoped access token** —
`/my-tenants` and `/me` accept either, so a user who has already entered a tenant
(holding only an access token) can still list memberships and switch tenants.
`POST /tenants/{id}/enter` likewise accepts either token.

### `GET /my-tenants`

Returns the caller's memberships (empty for a 0-tenant user):

```json
{
  "data": [
    { "tenant_id": "uuid", "tenant_name": "string", "roles": ["tenant_admin"] }
  ],
  "meta": {}
}
```

### `POST /tenants/{id}/enter`

Verifies membership in `{id}` and issues a **tenant-scoped** token:

```json
{
  "data": {
    "access_token": "<RS256 JWT, typ=access>",
    "refresh_token": "<jti>.<random>",
    "expires_in": 900
  },
  "meta": {
    "user_id": "uuid",
    "tenant_id": "uuid",
    "roles": ["tenant_admin"],
    "perms": ["user.invite", "user.role.assign", "role.manage"]
  }
}
```

Errors: `FORBIDDEN` (403) when the caller is not a member of `{id}`.

## Self endpoints

### `GET /me`

Authenticated — works with an **identity token** (no tenant entered) or a
tenant-scoped access token. Returns the user's profile and memberships. `email`
may be `null` for users without one. An expired access token returns `401`
`EXPIRED_ACCESS_TOKEN` so the web client triggers a silent refresh instead of
logging out.

```json
{
  "data": {
    "user_id": "uuid",
    "username": "string",
    "email": "string|null",
    "email_verified": false,
    "full_name": "string",
    "status": "active|disabled|pending",
    "password_set": true,
    "memberships": [
      { "tenant_id": "uuid", "roles": ["tenant_admin"] }
    ]
  },
  "meta": {}
}
```

## Tenant user management endpoints

All `/tenants/me/*` endpoints are authenticated with a tenant-scoped access
JWT. Authorization checks use `perms[]`, not a single role name. The tenant
scope is resolved from the JWT `tenant_id` claim; clients MUST NOT send
`tenant_id` in these requests.

Built-in roles are immutable templates. Tenant admins may create custom roles
from the fixed permission palette and assign users one or more roles.

### `POST /tenants/me/invitations`

Request:

```json
{ "email": "teacher@school.test", "roles": ["teacher", "homeroom_teacher"] }
```

Success (201):

```json
{
  "data": {
    "invitation_id": "uuid",
    "email": "teacher@school.test",
      "roles": ["teacher", "homeroom_teacher"],
    "status": "pending",
    "expires_at": "2026-06-16T12:00:00Z",
    "activation_link": "/invitations/accept?token=<token>",
    "token": "<token>"
  },
  "meta": {}
}
```

The raw token is returned only once — **the link is shown once and is not
retrievable afterwards.** IAM stores only an Argon2 hash, sends the activation
email when `EMAIL_PROVIDER=resend`, and emits `tenant_user.invited`. The
activation link is built from `PUBLIC_WEB_BASE_URL`, for example
`https://akademiq-web.vercel.app/invitations/accept?token=<token>`.

A tenant admin may assign `teacher`, `homeroom_teacher`, `principal`, `parent`,
and `student`, plus any custom role of their own tenant. `tenant_admin` is
**not** assignable here — a school admin must not be able to mint another school
admin. Only a platform operator can, through
`POST /internal/tenants/{tenant_id}/invitations`. `super_admin` is assignable
from neither path.

Errors: `VALIDATION_ERROR` (400), `ROLE_NOT_ASSIGNABLE` (400),
`MEMBERSHIP_ALREADY_EXISTS` (409), `PENDING_INVITATION_EXISTS` (409),
`FORBIDDEN` (403).

### `GET /tenants/me/invitations`

Returns invitations for the current tenant.

```json
{
  "data": [
    {
      "invitation_id": "uuid",
      "tenant_id": "uuid",
      "email": "teacher@school.test",
    "roles": ["teacher", "homeroom_teacher"],
      "status": "pending",
      "expires_at": "2026-06-16T12:00:00Z",
      "invited_by": "uuid",
      "accepted_at": null,
      "created_at": "2026-06-09T12:00:00Z"
    }
  ],
  "meta": {}
}
```

### `POST /tenants/me/invitations/{id}/revoke`

Revokes a pending invitation. Returns 204. A revoked token cannot be accepted.

### `POST /invitations/accept`

Public endpoint.

Request:

```json
{ "token": "<token>", "password": "password123?", "full_name": "Teacher Name?", "username": "teacher_one?" }
```

`password` and `full_name` are **optional** on the new-account path:

- **Without `password`** (button-only): the account is created with a NULL
  `password_hash`. Password login returns the standard `INVALID_CREDENTIALS`
  response until the user completes the set-password flow. The response includes
  a `set_password_token` for this purpose.
- **With `password`** (legacy/explicit): the account is created with the
  password set and password login works immediately.

`full_name`, when omitted on the passwordless path, falls back to the
invitation email local-part (editable later via profile).

Success (201) — returns a tenant-scoped token envelope with an extra
`password_set` flag. When `password_set` is `false`, a `set_password_token`
(single-use, time-bound) is also returned:

```json
{
  "data": {
    "access_token": "<RS256 JWT, typ=access>",
    "refresh_token": "<jti>.<random>",
    "expires_in": 900,
    "password_set": false,
    "set_password_token": "<single-use token>"
  },
  "meta": { "user_id": "uuid", "tenant_id": "uuid", "roles": ["teacher"], "perms": [] }
}
```

If the invited email already has an account, the membership is attached to
that account (no password change). IAM creates the user with a unique username
(auto-generated when omitted), creates the tenant role in the same transaction
that marks the invitation `accepted`, then emits `tenant_user.activated`.

Errors: `VALIDATION_ERROR` (400), `INVALID_INVITATION_TOKEN` (401),
`INVITATION_ALREADY_USED` (409), `INVITATION_REVOKED` (409),
`INVITATION_EXPIRED` (410), `EMAIL_ALREADY_EXISTS` (409).

### `POST /auth/set-password`

Public endpoint (no `Authorization` required when a token is supplied).
Self-service password set for accounts created without one. Accepts either:

1. A single-use **set-password token** (from the passwordless accept
   response), **or**
2. An **authenticated no-password session** (send the access token in the
   `Authorization: Bearer` header with no `token` in the body).

Request:

```json
{ "password": "newpassword123!", "token": "<set-password token>?" }
```

On success, the password is hashed and persisted, the token is consumed
(single-use), and **all refresh tokens for the user are revoked**. The client
must clear stored scoped tokens and send the user back to login. Returns 204
(no content).

Errors:

| Code                          | HTTP | Cause |
|-------------------------------|------|-------|
| `VALIDATION_ERROR`            | 400  | Password shorter than 8 chars. |
| `INVALID_SET_PASSWORD_TOKEN`  | 401  | No token or session, token already used, or token not found. |
| `SET_PASSWORD_TOKEN_EXPIRED`  | 410  | Token recognized but past its expiry. |
| `NOT_FOUND`                   | 404  | Token's user no longer exists. |

### `POST /auth/set-password/resend`

Public endpoint with optional `Authorization`. Re-issues a fresh single-use
set-password token for a no-password account and consumes prior unconsumed
set-password tokens for that user. The caller can identify the account either
by sending a bearer token (identity or scoped access token) or by posting an
identifier.

Request:

```json
{ "identifier": "teacher@school.test or teacher_username" }
```

Success (200) always uses a generic success-like shape to avoid account
enumeration. For local/dev delivery the raw token may be present for a
no-password account; for an existing account that already has a password or an
unknown identifier it is `null`.

```json
{
  "data": {
    "accepted": true,
    "set_password_token": "<single-use token or null>"
  },
  "meta": {}
}
```

The endpoint must not return a distinguishable error for unknown identifiers or
accounts that already have a password. It is rate-limited per identifier and per
source address where the deployment's auth limiter is configured.

### `GET /tenants/me/users`

Returns tenant users and roles in a server-paginated envelope. Query params:
`search` matches `full_name`, `email`, or `username`; `role` filters by role code;
`status` filters by account status; `page` defaults to `1`; `page_size` defaults
to `25` and clamps to `100`; `sort` accepts `name`, `-name`, `status`,
`-status`, `role`, or `-role`.

```json
{
  "data": [
    {
      "user_id": "uuid",
      "tenant_id": "uuid",
      "username": "teacher_one",
      "email": "teacher@school.test|null",
      "full_name": "Teacher Name",
      "status": "active",
      "roles": ["teacher", "homeroom_teacher"]
    }
  ],
  "meta": { "page": 1, "page_size": 25, "total": 1 }
}
```

Invalid sort values return `400 INVALID_SORT`.

### `GET /tenants/me/users/export`

Returns a CSV download (`text/csv`) for the same `search`, `role`, and `status`
filters as the list endpoint, without pagination. The response sets
`Content-Disposition: attachment; filename=tenant-users.csv`.

### `POST /tenants/me/users`

Requires `user.invite`. Creates a brand-new user and grants one or more
assignable roles in a single transaction. `tenant_id` is resolved from the
access token (never the body). Request:

```json
{
  "username": "budi_guru",
  "full_name": "Budi Santoso",
  "roles": ["teacher", "homeroom_teacher"],
  "email": "budi@school.test",
  "password": "optional-secret"
}
```

`username` is required, must not contain `@`, must match
`^[a-z][a-z0-9_-]{2,63}$`, and must be globally unique case-insensitively.
`email` is optional and, when present, must be unique-if-present
case-insensitively. `password` is optional: when omitted the account is created
in `pending` status (reset-required, the same end state as an unaccepted
invitation) and the admin issues an activation link via the reset-password
endpoint. At least one assignable role is required.

Create is strictly for *new* people. If the `username` or `email` already
belongs to an existing user the request fails with a conflict
(`409 USERNAME_TAKEN` or `409 EMAIL_ALREADY_EXISTS`) whose message directs the
admin to the invitation flow — there is no silent upsert into membership.

Success (201):

```json
{
  "data": {
    "user_id": "uuid",
    "username": "budi_guru",
    "email": "budi@school.test|null",
    "full_name": "Budi Santoso",
    "roles": ["teacher", "homeroom_teacher"]
  },
  "meta": {}
}
```

Emits `tenant_user.created`. Errors: `VALIDATION_ERROR` (400, including a
`username` field error when it contains `@` or is malformed), `USERNAME_TAKEN`
(409), `EMAIL_ALREADY_EXISTS` (409), `403` for callers without `user.invite`.

### `PATCH /tenants/me/users/{id}`

Requires the `user.update` permission (distinct from `user.invite` because a
changed `username` rewrites the global login key). Updates a member user's
identity fields. Only the fields present in the body are changed:

```json
{ "username": "budi_baru", "email": "new@school.test", "full_name": "Budi S." }
```

`username` must remain globally unique case-insensitively and must not contain
`@`; `email` must remain unique-if-present. The target must be a member of the
caller's tenant (≥1 role) or the response is `404`. Editing `username` does NOT
invalidate live sessions (access tokens key off `sub`, not `username`). Success
(200) returns the updated user and emits `tenant_user.updated`, whose payload
records which identity fields changed (consumed by the audit log). Errors:
`VALIDATION_ERROR` (400), `USERNAME_TAKEN` (409), `404` for non-members, `403`
for callers without `user.update`.

### `DELETE /tenants/me/users/{id}`

Requires `user.disable`. Explicit off-boarding: removes ALL of the user's roles
in the caller's tenant in one transaction and un-enrolls them from the tenant.
This is the sanctioned path to remove a member now that dropping a user's last
role is refused with `LAST_ROLE`. Honors the last-admin guard: removing the
tenant's only holder of `user.role.assign` returns `409 LAST_ADMIN`. Returns
`404` when the user is not a member. Returns 204 on success and emits
`tenant_user.removed`. The global `user` record is NOT deleted.

### `POST /tenants/me/users/{id}/roles/{roleId}`

Requires `user.role.assign`. Adds one built-in or tenant-scoped custom role to
the user. Returns 204 and emits `tenant_user.role_assigned`.

### `DELETE /tenants/me/users/{id}/roles/{roleId}`

Requires `user.role.assign`. Removes one role from the user. Returns 204 and
emits `tenant_user.role_removed`. A removal that would leave zero tenant users
holding `user.role.assign` returns `409 LAST_ADMIN`. A removal that would leave
the user with zero roles in the tenant returns `409 LAST_ROLE` (tenant
membership is expressed solely through `user_tenant_role` rows, so dropping the
last role would silently un-enroll the user; use an explicit tenant-removal
action instead).

`PATCH /tenants/me/users/{id}/role` is retained as a legacy single-role swap for
one compatibility window; new clients should use the add/remove endpoints.
Existing access tokens keep their old role set until expiry; refresh-token
rotation issues a new access token with current `roles[]`/`perms[]`.

### `POST /tenants/me/users/bulk/enable`

Enables multiple users. Request: `{ "user_ids": ["uuid"] }`. Returns a per-user
result list and emits one `tenant_user.enabled` event per successful user.

```json
{ "data": [{ "user_id": "uuid", "success": true, "reason": null }], "meta": {} }
```

### `POST /tenants/me/users/bulk/disable`

Disables multiple users. Request: `{ "user_ids": ["uuid"] }`. Returns the same
per-user result shape and emits one `tenant_user.disabled` event per successful
user.

### `POST /tenants/me/users/bulk/role`

Changes role for multiple users through the legacy role-swap command. Request:
`{ "user_ids": ["uuid"], "role": "teacher" }`. Returns the same per-user result
shape. Partial failures are reported per user. There is no bulk-delete endpoint.

### `POST /tenants/me/users/{id}/disable`

Disables login for the account. Returns 204 and emits `tenant_user.disabled`.

### `POST /tenants/me/users/{id}/enable`

Re-enables login for the account. Returns 204 and emits `tenant_user.enabled`.

### `POST /tenants/me/users/{id}/reset-password`

Returns a temporary password for the admin to share manually.

```json
{ "data": { "temporary_password": "string" }, "meta": {} }
```

## Role catalog endpoints

### `GET /tenants/me/permissions`

Requires `role.manage`. Returns the fixed assignable permission palette; each
entry includes whether the current admin holds it, so clients can hide disabled
escalation choices.

```json
{ "data": [{ "code": "user.invite", "description": "...", "held": true }], "meta": {} }
```

### `GET /tenants/me/roles`

Requires `role.manage`. Returns built-in roles (`is_builtin=true`, read-only)
and tenant custom roles in a server-paginated envelope. Query params: `search`
matches role name or code case-insensitively; `page` defaults to `1`;
`page_size` defaults to `25` and clamps to `100`; `sort` accepts `name`,
`-name`, `type`, `-type`, `users`, or `-users` (default lists built-in roles
before custom roles, then by code). Each role view includes `user_count`: the
number of users **in the calling tenant** holding that role (computed
per-tenant even for built-in roles).

```json
{
  "data": [
    {
      "role_id": "uuid",
      "code": "teacher",
      "name": "Subject teacher",
      "is_builtin": true,
      "permissions": ["grade.record"],
      "user_count": 3
    }
  ],
  "meta": { "page": 1, "page_size": 25, "total": 1 }
}
```

Invalid sort values return `400 INVALID_SORT`.

### `POST /tenants/me/roles`

Requires `role.manage`. Creates a tenant-scoped custom role.

```json
{ "code": "wakil_kurikulum", "name": "Wakil Kepala Kurikulum", "permissions": ["academic.config.write"] }
```

The server rejects built-in code shadowing with `VALIDATION_ERROR` and rejects
permissions the caller lacks with `403 PRIVILEGE_ESCALATION`.

### `GET/PATCH/DELETE /tenants/me/roles/{id}`

Requires `role.manage`. Built-in roles are immutable (`BUILT_IN_ROLE_IMMUTABLE`).
Deleting a role that is still assigned returns `409 ROLE_IN_USE`.

### `POST /tenants/me/roles/bulk/delete`

Requires `role.manage`. Deletes multiple custom roles in one all-or-nothing
request. Request:

```json
{ "role_ids": ["uuid", "uuid"] }
```

The endpoint pre-validates **every** id before deleting anything: if any id is a
built-in role the whole request is refused with `403 BUILT_IN_ROLE_IMMUTABLE`;
if any id is still assigned to one or more users the whole request is refused
with `409 ROLE_IN_USE`; any id that is not a custom role of the calling tenant
returns `404`. Only when every id passes does it delete them all in a single
transaction, emitting one `role.deleted` event per deleted role (the same event
the single-role delete emits). Returns 204 on success.

## Internal endpoints

These endpoints are reachable only inside the cluster. They require an
`X-Service-Token: <secret>` header that matches
`IAM_INTERNAL_SERVICE_TOKEN`. Calls without a valid token return
`UNAUTHORIZED_SERVICE_CALL` (401).

### `POST /internal/users`

Used by `billing-service` during the registration saga, and for admin-created
accounts. `email` and `username` are both optional: an email-less account (e.g.
an older teacher/parent) omits `email`, and a blank `username` is auto-generated.
At least one of `email` or `username` must end up set (the server guarantees a
username).

**`password` is optional.** Omitting it creates a `pending` account with a NULL
`password_hash`, and the response then carries a one-time set-password token and
the link built from it. This is how a platform operator creates a school admin
without ever choosing, seeing, or transporting that school's credential.

Omission is the *only* way to take that path. A supplied password is still held
to the eight-character minimum — the `Option` widens what may be absent, not
what may be weak — and must never be replaced by a placeholder or an empty
string, which would hash to a real credential and skip token issuance. Public
self-service signup (`POST /auth/register`) always supplies a password and is
unaffected.

Request:

```json
{
  "email": "string?",
  "username": "string?",
  "password": "string?",
  "full_name": "string",
  "tenant_id": "uuid",
  "tenant_name": "string?",
  "role_code": "tenant_admin"
}
```

An absent `password` key and an explicit `"password": null` are accepted
identically. Callers should omit the key; that is the form the wire contract is
tested against.

`tenant_name`, when present and non-blank, also upserts IAM's display-name row
for the tenant — the same write as `POST /internal/tenants/{id}` below, folded
into the saga's first call.

Success (201):

```json
{
  "data": {
    "user_id": "uuid",
    "username": "string",
    "email": "string|null",
    "set_password_token": "<single-use token>|null",
    "activation_link": "https://app.example/set-password?token=<token>|null"
  },
  "meta": {}
}
```

| Field                | When it is non-null |
|----------------------|---------------------|
| `set_password_token` | Only when the request omitted `password`. |
| `activation_link`    | Exactly when `set_password_token` is; it is that token rendered as a URL. |

Both are `null` for a password-bearing creation — an account that can already
log in needs no handover.

**The link is shown once and is not retrievable afterwards.** IAM stores only an
Argon2 hash of the token, and `POST /auth/set-password/resend` will not mint a
replacement for a `pending` account — it answers 200 with
`set_password_token: null`, so the caller sees a success carrying nothing. This
response is therefore the one and only place the raw value exists, and a caller
that drops it strands the account. Do not log it, persist it, or echo it into an
audit trail. The recovery path is
`POST /internal/users/{user_id}/reset-password` below.

The link points at `/set-password`, built from `PUBLIC_WEB_BASE_URL`. That is
deliberate and not interchangeable with the invitation link above:
`/invitations/accept` resolves against `tenant_invitation`, a different table,
and rejects a set-password token with `INVALID_INVITATION_TOKEN`.

Errors:

| Code                       | HTTP | Cause |
|----------------------------|------|-------|
| `VALIDATION_ERROR`         | 400  | Field-level errors. A supplied `password` under 8 characters is one of them. |
| `EMAIL_ALREADY_EXISTS`     | 409  | `email` already in `user.email` (case-insensitive). |
| `USERNAME_TAKEN`           | 409  | `username` already taken (case-insensitive). |
| `UNAUTHORIZED_SERVICE_CALL`| 401  | Missing or wrong `X-Service-Token`. |

### `POST /internal/tenants/{tenant_id}/invitations`

Operator-initiated invitation, called by platform-service for
`POST /platform/tenants/{tenant_id}/invitations`. Reuses the same
`invite_tenant_user` command as the tenant-scoped
`POST /tenants/me/invitations`: token minting, the single-pending-invitation
constraint, the membership guard, the outbox event, and the email attempt are
one implementation. Three things differ — `tenant_id` comes from the path rather
than a JWT, authorization is the service token rather than `user.invite`, and
the actor may assign a wider role set.

Request:

```json
{
  "email": "admin2@school.test",
  "roles": ["tenant_admin"],
  "invited_by": "uuid?",
  "issued_by_operator": "uuid?"
}
```

`tenant_id` is **not** a body field. A platform operator holds a token with no
tenant claim, so there is no `AuthContext` to resolve one from; the service-token
boundary is what makes an explicit tenant acceptable here.

`roles` may contain the five roles a tenant admin can assign **plus
`tenant_admin`** — the operator's carve-out, and the reason this route exists.
`super_admin` is assignable from neither path. A built-in role outside that set
is `VALIDATION_ERROR` on field `roles`, with a message naming platform operators
rather than tenant admins.

`invited_by` names the tenant member credited as the inviter.
`tenant_invitation.invited_by` is a foreign key to `"user"` and an operator is a
member of no tenant, so a real member must be named. **platform-service never
sends it**, so the resolution path below is what every production request
actually uses: IAM picks one itself, preferring a `tenant_admin`, then an
`active` account, then the oldest. A school with no `active` or `pending` member
at all returns `404` rather than writing a dangling reference.

`issued_by_operator` carries the operator who really performed this, and is
copied into the `tenant_user.invited` event so the invitation can be joined to
the `operator_audit` row naming the true actor. platform-service injects it from
the caller's JWT; direct callers of this internal route should send it when an
operator is behind the request and omit it otherwise — the key's *presence* in
the event is the signal, so it is never emitted as an explicit null. See
`events/tenant-user-events.md`.

Success (201) — the same shape as the tenant-scoped invitation response, plus
`tenant_id`:

```json
{
  "data": {
    "invitation_id": "uuid",
    "email": "admin2@school.test",
    "roles": ["tenant_admin"],
    "status": "pending",
    "expires_at": "2026-09-21T12:00:00Z",
    "tenant_id": "uuid",
    "activation_link": "https://app.example/invitations/accept?token=<token>",
    "token": "<token>"
  },
  "meta": {}
}
```

**The link is shown once and is not retrievable afterwards** — only the token's
Argon2 hash is stored. It points at `/invitations/accept`, the opposite page to
`POST /internal/users` above.

Errors:

| Code                        | HTTP | Cause |
|-----------------------------|------|-------|
| `VALIDATION_ERROR`          | 400  | `email` invalid, `roles` empty, or a built-in role this actor may not assign. |
| `NOT_FOUND`                 | 404  | No member of the tenant can be credited as the inviter. |
| `MEMBERSHIP_ALREADY_EXISTS` | 409  | The address already belongs to a member of this tenant. |
| `PENDING_INVITATION_EXISTS` | 409  | The address already holds a pending invitation here. |
| `UNAUTHORIZED_SERVICE_CALL` | 401  | Missing or wrong `X-Service-Token`. |

### `POST /internal/users/{user_id}/reset-password`

Mints a set-password link for an existing user on an operator's behalf. Called
by platform-service for `POST /platform/users/{user_id}/reset-password`.

**No request body.** Success (200):

```json
{
  "data": {
    "user_id": "uuid",
    "set_password_link": "https://app.example/set-password?token=<token>"
  },
  "meta": {}
}
```

The field is `set_password_link`, **not** `activation_link`: the name says which
of the two token types this is, and `/invitations/accept` would reject it with
`INVALID_INVITATION_TOKEN`. **The link is shown once and is not retrievable
afterwards.**

This route is deliberately **not** `POST /auth/set-password/resend`. That
endpoint is public and unauthenticated, and its guard — declining whenever
`password_hash` is set or the account is not `active` — is anti-abuse: without
it an anonymous caller could mint a live link for someone else's account. It
must stay exactly as it is. Two consequences follow, and both are why this route
exists: it declines a user who already *has* a password, which is what a reset
is for; and it declines a `pending` user, which is every operator-created admin
who has not activated yet. Worse, it declines by returning **200 with
`set_password_token: null`** — an anti-enumeration measure there, and an empty
success at an operator console. The authorization the public guard supplies by
declining is supplied here by the caller instead: the service-token boundary,
plus platform-service's platform-admin check. This route answers with a link or
a real error, never a hollow success.

Who can be reset:

| Account state | Outcome |
|---------------|---------|
| Does not exist | `404 NOT_FOUND` — a mistyped id must not read as a domain refusal. |
| `disabled`    | `409 USER_DISABLED`. |
| `pending`     | **Succeeds.** |
| `active`      | Succeeds, with or without an existing password. |

`pending` succeeding is the point, not an oversight: it is the
stranded-invited-admin recovery path, and redeeming the link activates the
account. `disabled` is the only refusal because `login` rejects a non-active
user *before* it checks a password and
`set_password_hash_activating_pending` promotes only `Pending` — so a disabled
user would redeem the link successfully and still be unable to log in. Issuing
one would be a silent lie; the operator's fix is to enable the account first.

Issuing supersedes any unconsumed set-password link for that user, so its holder
cannot race the operator onto the account. Refresh tokens are **not** revoked
here — issuing a link does not yet change the password, and
`POST /auth/set-password` already revokes them at redemption, which is when the
credential actually changes.

Errors:

| Code                        | HTTP | Cause |
|-----------------------------|------|-------|
| `NOT_FOUND`                 | 404  | No such user. |
| `USER_DISABLED`             | 409  | The account is disabled; enable it before resetting. |
| `UNAUTHORIZED_SERVICE_CALL` | 401  | Missing or wrong `X-Service-Token`. |

### `DELETE /internal/users/{id}`

Idempotent. Returns 204 whether or not the row existed. Same auth as
above.

### `POST /internal/tenants/{id}`

Upserts the tenant profile row IAM keeps for display purposes (`tenant_name`).
Called by billing during registration. Returns 204. A blank `tenant_name` is
`VALIDATION_ERROR`.

### `POST /internal/users/{id}/tenant-membership`

Attaches an existing user to a tenant with one role code. Used by billing's
register-for-an-existing-user path. Returns 204; an unknown user is `404`, and a
membership that already exists is `409 MEMBERSHIP_ALREADY_EXISTS`.

## Health

### `GET /healthz`

Public. Returns 200 + `{ "data": { "ok": true } }` after a successful
`SELECT 1` against the database.
