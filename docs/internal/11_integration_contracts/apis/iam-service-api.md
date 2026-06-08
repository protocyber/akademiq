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
