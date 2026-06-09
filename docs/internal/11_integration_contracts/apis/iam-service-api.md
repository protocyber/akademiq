# IAM Service API

Base path: `/api/v1/iam`. All endpoints follow the standard envelopes
from `13_engineering_standards/03_api_conventions.md`:

- Success: `{ "data": {...}, "meta": {...} }`
- Error: `{ "error": { "code": "...", "message": "...", "fields?": {...} } }`

Validation errors use `code = "VALIDATION_ERROR"` and a `fields` map
keyed by request-body field name, per
`13_engineering_standards/14_validation_contract.md`.

## Auth endpoints

### `POST /auth/login`

Request:

```json
{ "email": "string", "password": "string" }
```

Success (200):

```json
{
  "data": {
    "access_token": "<RS256 JWT>",
    "refresh_token": "<jti>.<random>",
    "expires_in": 900
  },
  "meta": {
    "user_id": "uuid",
    "tenant_id": "uuid",
    "role": "tenant_admin"
  }
}
```

Errors:

| Code                  | HTTP | Cause |
|-----------------------|------|-------|
| `VALIDATION_ERROR`    | 400  | Missing or malformed fields. |
| `INVALID_CREDENTIALS` | 401  | Email unknown or password mismatch. Identical body for either case. |
| `USER_INACTIVE`       | 403  | User exists but `status != 'active'`. |

### `POST /auth/refresh`

Authenticated via `Authorization: Bearer <expired-or-valid-access>`.

Request body:

```json
{ "refresh_token": "<jti>.<random>" }
```

Returns the same envelope as `/auth/login` with rotated refresh token.
Old refresh token's `(user_id, jti)` row is marked revoked.

Errors: `INVALID_REFRESH_TOKEN` (401), `EXPIRED_REFRESH_TOKEN` (401).

### `POST /auth/logout`

Authenticated. Body: `{ "refresh_token": "..." }`. Returns 204.

## Self endpoints

### `GET /me`

Authenticated. Returns the user's profile and memberships.

```json
{
  "data": {
    "user_id": "uuid",
    "email": "string",
    "full_name": "string",
    "status": "active|disabled|pending",
    "memberships": [
      { "tenant_id": "uuid", "role_code": "tenant_admin" }
    ]
  },
  "meta": {}
}
```

## Tenant user management endpoints

All `/tenants/me/*` endpoints are authenticated and require the `tenant_admin`
role from the JWT. The tenant scope is resolved from the JWT `tenant_id` claim;
clients MUST NOT send `tenant_id` in these requests.

Assignable roles: `teacher`, `homeroom_teacher`, `principal`, `parent`,
`student`.

### `POST /tenants/me/invitations`

Request:

```json
{ "email": "teacher@school.test", "role": "teacher" }
```

Success (201):

```json
{
  "data": {
    "invitation_id": "uuid",
    "email": "teacher@school.test",
    "role_code": "teacher",
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
      "role_code": "teacher",
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
{ "token": "<token>", "password": "password123!", "full_name": "Teacher Name" }
```

Success (201): same token envelope as `/auth/login`. IAM creates the user and
tenant role in the same transaction that marks the invitation `accepted`, then
emits `tenant_user.activated`.

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
      "email": "teacher@school.test",
      "full_name": "Teacher Name",
      "status": "active",
      "role_code": "teacher"
    }
  ],
  "meta": {}
}
```

### `PATCH /tenants/me/users/{id}/role`

Request:

```json
{ "role": "principal" }
```

Returns 204 and emits `tenant_user.role_changed`. Existing access tokens keep
their old role until expiry; refresh-token rotation issues a new access token
with the current role.

### `POST /tenants/me/users/{id}/disable`

Disables login for the account. Returns 204 and emits `tenant_user.disabled`.

### `POST /tenants/me/users/{id}/enable`

Re-enables login for the account. Returns 204.

### `POST /tenants/me/users/{id}/reset-password`

Returns a temporary password for the admin to share manually.

```json
{ "data": { "temporary_password": "string" }, "meta": {} }
```

## Internal endpoints

These endpoints are reachable only inside the cluster. They require an
`X-Service-Token: <secret>` header that matches
`IAM_INTERNAL_SERVICE_TOKEN`. Calls without a valid token return
`UNAUTHORIZED_SERVICE_CALL` (401).

### `POST /internal/users`

Used by `billing-service` during the registration saga.

Request:

```json
{
  "email": "string",
  "password": "string",
  "full_name": "string",
  "tenant_id": "uuid",
  "role_code": "tenant_admin"
}
```

Success (201):

```json
{ "data": { "user_id": "uuid", "email": "string" }, "meta": {} }
```

Errors:

| Code                       | HTTP | Cause |
|----------------------------|------|-------|
| `VALIDATION_ERROR`         | 400  | Field-level errors. |
| `EMAIL_ALREADY_EXISTS`     | 409  | `email` already in `user.email`. |
| `UNAUTHORIZED_SERVICE_CALL`| 401  | Missing or wrong `X-Service-Token`. |

### `DELETE /internal/users/{id}`

Idempotent. Returns 204 whether or not the row existed. Same auth as
above.

## Health

### `GET /healthz`

Public. Returns 200 + `{ "data": { "ok": true } }` after a successful
`SELECT 1` against the database.
