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
   (`{ sub, tenant_id, roles, perms, typ:"access" }`, 15-min TTL) plus a
   tenant-scoped refresh token. This is the token every other service verifies.

A user may belong to zero, one, or many tenants. Refresh tokens are scoped to a
tenant; switching tenants is a fresh `/enter`, not a refresh.

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
| `INVALID_CREDENTIALS` | 401  | Identifier unknown or password mismatch (or account has no password). Identical body and timing for every case. |
| `USER_INACTIVE`       | 403  | User exists but `status != 'active'`. |

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
`USERNAME_ALREADY_EXISTS` (409).

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

Authenticated via `Authorization: Bearer <expired-or-valid tenant-scoped access>`.

Request body:

```json
{ "refresh_token": "<jti>.<random>" }
```

Returns a rotated **tenant-scoped** token envelope for the refresh token's bound
tenant (it cannot change tenants). Old `(user_id, jti)` row is marked revoked.

Errors: `INVALID_REFRESH_TOKEN` (401), `EXPIRED_REFRESH_TOKEN` (401).

### `POST /auth/logout`

Authenticated. Body: `{ "refresh_token": "..." }`. Returns 204.

## Tenant selection endpoints

Authenticated by an **identity token**.

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
tenant-scoped token. Returns the user's profile and memberships. `email` may be
`null` for users without one.

```json
{
  "data": {
    "user_id": "uuid",
    "username": "string",
    "email": "string|null",
    "email_verified": false,
    "full_name": "string",
    "status": "active|disabled|pending",
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

The raw token is returned only once. IAM stores only an Argon2 hash, sends the
activation email when `EMAIL_PROVIDER=resend`, and emits `tenant_user.invited`.
The activation link is built from `PUBLIC_WEB_BASE_URL`, for example
`https://akademiq-web.vercel.app/invitations/accept?token=<token>`.

Errors: `VALIDATION_ERROR` (400), `ROLE_NOT_ASSIGNABLE` (400),
`PENDING_INVITATION_EXISTS` (409), `FORBIDDEN` (403).

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
{ "token": "<token>", "password": "password123!", "full_name": "Teacher Name", "username": "teacher_one?" }
```

Success (201): same token envelope as `/auth/login`. IAM creates the user with a
unique username (auto-generated when omitted), keeps the invitation email as the
optional contact address, and creates the tenant role in the same transaction
that marks the invitation `accepted`, then emits `tenant_user.activated`.

Errors: `VALIDATION_ERROR` (400), `INVALID_INVITATION_TOKEN` (401),
`INVITATION_ALREADY_USED` (409), `INVITATION_REVOKED` (409),
`INVITATION_EXPIRED` (410), `EMAIL_ALREADY_EXISTS` (409).

### `GET /tenants/me/users`

Returns tenant users and roles.

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
  "meta": {}
}
```

### `POST /tenants/me/users/{id}/roles/{roleId}`

Requires `user.role.assign`. Adds one built-in or tenant-scoped custom role to
the user. Returns 204 and emits `tenant_user.role_assigned`.

### `DELETE /tenants/me/users/{id}/roles/{roleId}`

Requires `user.role.assign`. Removes one role from the user. Returns 204 and
emits `tenant_user.role_removed`. A removal that would leave zero tenant users
holding `user.role.assign` returns `409 LAST_ADMIN`.

`PATCH /tenants/me/users/{id}/role` is retained as a legacy single-role swap for
one compatibility window; new clients should use the add/remove endpoints.
Existing access tokens keep their old role set until expiry; refresh-token
rotation issues a new access token with current `roles[]`/`perms[]`.

### `POST /tenants/me/users/{id}/disable`

Disables login for the account. Returns 204 and emits `tenant_user.disabled`.

### `POST /tenants/me/users/{id}/enable`

Re-enables login for the account. Returns 204.

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
and tenant custom roles.

```json
{
  "data": [
    { "role_id": "uuid", "code": "teacher", "name": "Subject teacher", "is_builtin": true, "permissions": ["grade.record"] }
  ],
  "meta": {}
}
```

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
username). A passwordless account omits `password`.

Request:

```json
{
  "email": "string?",
  "username": "string?",
  "password": "string?",
  "full_name": "string",
  "tenant_id": "uuid",
  "role_code": "tenant_admin"
}
```

Success (201):

```json
{ "data": { "user_id": "uuid", "username": "string", "email": "string|null" }, "meta": {} }
```

Errors:

| Code                       | HTTP | Cause |
|----------------------------|------|-------|
| `VALIDATION_ERROR`         | 400  | Field-level errors. |
| `EMAIL_ALREADY_EXISTS`     | 409  | `email` already in `user.email` (case-insensitive). |
| `USERNAME_ALREADY_EXISTS`  | 409  | `username` already taken (case-insensitive). |
| `UNAUTHORIZED_SERVICE_CALL`| 401  | Missing or wrong `X-Service-Token`. |

### `DELETE /internal/users/{id}`

Idempotent. Returns 204 whether or not the row existed. Same auth as
above.

## Health

### `GET /healthz`

Public. Returns 200 + `{ "data": { "ok": true } }` after a successful
`SELECT 1` against the database.
