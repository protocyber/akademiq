# Platform Service API

Base path: `/api/v1/platform`. All protected endpoints require
`Authorization: Bearer <platform_token>` where the JWT has `typ:"platform"` and
`platform_admin`. Tenant `access`, `identity`, and `refresh` tokens are rejected.

All endpoints follow the standard envelopes:

- Success: `{ "data": {...}, "meta": {...} }`
- Error: `{ "error": { "code": "...", "message": "...", "fields?": {...} } }`

## Health

### `GET /healthz`

Performs `SELECT 1` against `platform_db`.

Success: `{ "data": { "status": "ok" }, "meta": {} }`

## Operator identity

### `GET /me`

Returns the authenticated platform operator.

```json
{
  "data": { "user_id": "uuid", "roles": ["platform_admin"] },
  "meta": {}
}
```

## Tenant directory

### `GET /tenants?page=&page_size=`

Returns the local cross-tenant projection from `platform_tenant`.

```json
{
  "data": [
    {
      "tenant_id": "uuid",
      "school_name": "string",
      "status": "active|suspended|cancelled",
      "current_plan_code": "premium",
      "registered_at": "timestamp"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

### `GET /tenants/{tenant_id}`

Returns tenant profile plus usage stats from local projections. Unknown tenants
return `404 NOT_FOUND`.

### `GET /tenants/{tenant_id}/usage`

Returns `student_count` and `teacher_count` from `platform_tenant_stats`.

## User lookup

### `GET /users?email=...`

Returns matching users and tenant memberships from `platform_user`.

Errors: `VALIDATION_ERROR` when `email` is empty.

## Audit

### `GET /audit?page=&page_size=`

Read-only operator audit listing. There is no mutate/delete endpoint.

## Tenant lifecycle commands

These endpoints forward to billing-service internal endpoints with
`X-Service-Token`. platform-service writes `operator_audit` only after a 2xx
billing response.

### `POST /tenants/{tenant_id}/suspend`

Request:

```json
{ "reason": "string|null" }
```

Success: forwards billing's `{ "data": { "changed": true|false }, "meta": {} }`.

### `POST /tenants/{tenant_id}/reactivate`

Success: forwards billing's `{ "data": { "changed": true|false }, "meta": {} }`.

## Plan catalog commands

### `POST /plans`

Request:

```json
{
  "code": "premium",
  "name": "Premium",
  "price_monthly": 499000.0,
  "price_yearly": 4990000.0,
  "features": [["academic_config", true]]
}
```

Success: `201` with billing's plan envelope. Duplicate codes surface as `409`.
Validation failures use `VALIDATION_ERROR` with field keys such as `code` and
`name`.

### `PUT /plans/{plan_id}`

Partial update forwarded to billing-service. Success: `204`.

### `DELETE /plans/{plan_id}`

Deactivates the plan through billing-service. Success: `204`.

## Subscription override

### `POST /tenants/{tenant_id}/subscription`

Request:

```json
{ "plan_id": "uuid" }
```

Success: `204`. Unknown plans surface billing's `UNKNOWN_PLAN` error.
