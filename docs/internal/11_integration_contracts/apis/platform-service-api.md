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

## Usage overview

### `GET /overview`

Platform-wide aggregates for the operator dashboard, computed only from local
projections (`platform_tenant`, `platform_tenant_stats`) with no synchronous
calls to other services.

```json
{
  "data": {
    "tenants_by_status": { "active": 2 },
    "totals": { "tenants": 2, "students": 195, "teachers": 15 }
  },
  "meta": {}
}
```

Tenants with no `platform_tenant_stats` row contribute zero to the student and
teacher totals. The endpoint is a point-in-time snapshot: freshness follows the
projection (events + `scripts/bootstrap-projections.sh` backfill).

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

### `GET /users?email=&page=&page_size=`

Cross-tenant directory from `platform_user`. `email` is an **optional** filter:

- With `email`: returns users whose email matches (case-insensitive).
- Without `email` (or blank): returns a paginated listing of the directory,
  ordered by email. Previously this returned `VALIDATION_ERROR`; the contract
  changed when the listing was added.

`page_size` defaults to 20 and is clamped to 1-100.

```json
{
  "data": [
    {
      "user_id": "uuid",
      "email": "string",
      "display_name": "string|null",
      "memberships": [
        { "tenant_id": "uuid", "tenant_name": "string", "roles": ["tenant_admin"] }
      ]
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

### `GET /users/{user_id}`

Returns one projected user with tenant memberships. Unknown ids return `404
NOT_FOUND`.

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

## Plan catalog

### `GET /plans`

Returns the subscription-plan catalog. The request is forwarded to
billing-service's `GET /api/v1/billing/plans` over `X-Service-Token` —
platform-service keeps no local copy, so the operator view cannot diverge from
the billing source of truth. Reads are not audited.

The billing response is adapted to the platform plan contract: feature entries
use `code` (billing's `feature_code`), and each plan carries an explicit
`active: true` (billing lists active plans only).

```json
{
  "data": [
    {
      "plan_id": "uuid",
      "code": "standard",
      "name": "Standard",
      "price_monthly": 199000.0,
      "price_yearly": 1990000.0,
      "features": [{ "code": "grading", "enabled": true }],
      "active": true
    }
  ],
  "meta": {}
}
```

Downstream billing failures surface as the mapped error (e.g.
`DOWNSTREAM_ERROR`), never as an empty catalog.

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
