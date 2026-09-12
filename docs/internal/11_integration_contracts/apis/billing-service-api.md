# Billing Service API

Base path: `/api/v1/billing`. Envelopes follow
`13_engineering_standards/03_api_conventions.md`. Validation errors
follow `14_validation_contract.md`. Feature-gated endpoints follow
`15_feature_entitlement.md` (return HTTP 403
`FEATURE_NOT_AVAILABLE`).

## Public endpoints

### `GET /plans`

Public. Returns the active plan catalog with the per-plan feature
matrix. The web `/register` plan-selection step consumes this endpoint.

```json
{
  "data": [
    {
      "plan_id": "uuid",
      "code": "starter|standard|premium",
      "name": "Starter",
      "price_monthly": 199000.0,
      "price_yearly": 1990000.0,
      "features": [
        { "feature_code": "academic_config", "enabled": true },
        { "feature_code": "academic_ops",    "enabled": true },
        { "feature_code": "attendance",      "enabled": false },
        { "feature_code": "grading",         "enabled": false },
        { "feature_code": "promotion",       "enabled": false },
        { "feature_code": "notification",    "enabled": false },
        { "feature_code": "file",            "enabled": false }
      ]
    }
  ],
  "meta": {}
}
```

### `POST /tenants/register`

Public. Drives the registration saga. Server allocates `tenant_id` and
ignores any `tenant_id` field supplied in the body.

Request:

```json
{
  "school_name": "string",
  "plan_id": "uuid",
  "admin_email": "string",
  "admin_password": "string (>=8 chars)",
  "admin_full_name": "string"
}
```

Success (201):

```json
{
  "data": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "subscription_id": "uuid",
    "plan_code": "starter|standard|premium"
  },
  "meta": {}
}
```

Errors:

| Code                  | HTTP | Cause |
|-----------------------|------|-------|
| `VALIDATION_ERROR`    | 400  | Per-field errors (`admin_email`, `admin_password`, `school_name`, `admin_full_name`, `plan_id`). |
| `UNKNOWN_PLAN`        | 400  | `plan_id` does not exist. |
| `EMAIL_ALREADY_EXISTS`| 409  | IAM rejected the user creation; tenant row not committed. |

The handler emits `tenant.registered` and `subscription.activated`
events via the transactional outbox before returning 201. See
`docs/internal/11_integration_contracts/events/`.

## Authenticated endpoints

All require `Authorization: Bearer <access_token>`. `tenant_id` is
resolved from the JWT; body-supplied `tenant_id` is ignored.

### `GET /tenants/me`

Returns the caller's tenant + plan + module override map.

```json
{
  "data": {
    "tenant_id": "uuid",
    "school_name": "string",
    "status": "active|suspended|cancelled",
    "current_plan": { "plan_id": "uuid", "code": "premium", "name": "Premium" },
    "modules": [
      { "feature_code": "academic_config", "plan_entitled": true,  "enabled": true  },
      { "feature_code": "attendance",      "plan_entitled": true,  "enabled": false }
    ]
  },
  "meta": {}
}
```

### `PATCH /tenants/me/modules`

Toggle a module within the current plan's entitlements.

Request:

```json
{ "feature_code": "attendance", "enabled": false }
```

Success (200): `{ "data": { "ok": true }, "meta": {} }`

Errors:

| Code                    | HTTP | Cause |
|-------------------------|------|-------|
| `FEATURE_NOT_AVAILABLE` | 403  | The current plan does not include `feature_code`. |
| `SUBSCRIPTION_EXPIRED`  | 403  | Tenant has no active subscription. |

## School profile

All require `Authorization: Bearer <access_token>` and the `billing.manage`
permission. `tenant_id` is resolved from the JWT; body-supplied `tenant_id` is
ignored. The profile does **not** include kepala sekolah / head-teacher linkage.

### `GET /tenants/me/school-profile`

Returns the complete school profile for the current tenant.

```json
{
  "data": {
    "tenant_id": "uuid",
    "school_name": "SMA Negeri 1",
    "phone_number": "031-123456",
    "email": "info@sman1.sch.id",
    "website": "https://sman1.sch.id",
    "npsn": "20512345",
    "logo_url": "string|null",
    "school_level": "sma|smp|sd|mi|mts|ma|slb",
    "school_status": "negeri|swasta",
    "accreditation": "a|b|c|belum_terakreditasi",
    "address_line": "Jl. Pendidikan No. 1",
    "village": "Kelurahan Sehat",
    "subdistrict": "Kecamatan Maju",
    "city_regency": "Kota Surabaya",
    "province": "Jawa Timur",
    "postal_code": "60111"
  },
  "meta": {}
}
```

### `PATCH /tenants/me/school-profile`

Updates one or more school profile fields for the current tenant. All fields are
optional; only supplied fields are updated.

Request (partial):

```json
{
  "school_name": "SMA Negeri 1 Surabaya",
  "phone_number": "031-654321",
  "school_level": "sma",
  "school_status": "negeri",
  "accreditation": "a",
  "address_line": "Jl. Pendidikan No. 1",
  "province": "Jawa Timur"
}
```

Success (200): the updated school profile (same shape as `GET`).

Errors:

| Code              | HTTP | Cause |
|-------------------|------|-------|
| `VALIDATION_ERROR`| 400  | Per-field errors (`school_level`, `school_status`, `accreditation`, `email`, etc.). |
| `FORBIDDEN`       | 403  | Caller lacks `billing.manage`. |

## School profile logo

### `POST /tenants/me/school-profile/logo`

Uploads a new school logo (multipart `file`). Validates JPG/PNG/WebP up to 512 KB.
The new logo replaces the previous one (single-active, no history retained).
The previous logo's storage object is garbage-collected on replace.

Response (201):

```json
{
  "data": { "logo_url": "/api/v1/billing/media/school/{media_id}" },
  "meta": {}
}
```

Errors: `400 INVALID_FILE_TYPE` for a non-JPG/PNG/WebP upload,
`400 FILE_TOO_LARGE` for a file over 512 KB.

### `DELETE /tenants/me/school-profile/logo`

Clears the school logo: deletes the backing storage object and nulls `logo_url`.
Idempotent — a tenant with no logo succeeds silently.

Success (204): empty body.

Errors:

| Code       | HTTP | Cause |
|------------|------|-------|
| `FORBIDDEN`| 403  | Caller lacks `billing.manage`. |

## Internal platform operator endpoints

All internal endpoints require `X-Service-Token` and do not accept tenant access
tokens. Missing or invalid service tokens return `401 UNAUTHORIZED_SERVICE_CALL`.
These endpoints are called by platform-service; billing remains the source of
truth for tenant status, plans, and subscriptions.

### `POST /internal/tenants/{tenant_id}/suspend`

Suspends the tenant and emits `tenant.suspended` when state changes. Repeated
suspend is idempotent.

Success: `{ "data": { "changed": true|false }, "meta": {} }`

### `POST /internal/tenants/{tenant_id}/reactivate`

Reactivates the tenant and emits `tenant.reactivated` when state changes.

Success: `{ "data": { "changed": true|false }, "meta": {} }`

### `GET /internal/tenants/{tenant_id}/modules`

Operator-facing read of a tenant's **effective** module state, for
platform-service's `GET /platform/tenants/{tenant_id}/modules`. Billing owns
both halves of the answer, so the operator console reports what billing actually
enforces.

```json
{
  "data": {
    "modules": [
      { "feature_code": "academic_config", "plan_entitled": true,  "enabled": true  },
      { "feature_code": "grading",         "plan_entitled": true,  "enabled": false },
      { "feature_code": "promotion",       "plan_entitled": false, "enabled": false }
    ]
  },
  "meta": {}
}
```

| Field           | Meaning |
|-----------------|---------|
| `feature_code`  | Feature code from `features.toml`. |
| `plan_entitled` | Does the tenant's current plan include the feature. |
| `enabled`       | Is the module in force right now. |

Two rules decide `enabled`, both shared with the tenant-facing
`GET /tenants/me` via `queries::resolve_modules`, so the two views cannot drift:

1. **An absent `tenant_module` override means the plan default, not `false`.**
   `toggle_module` and every entitlement check resolve it that way, so an
   entitled feature nobody has touched is genuinely running.
2. **An override for a feature the plan no longer entitles is still listed**, as
   `enabled: true, plan_entitled: false`. It remains in force, and this is the
   only way an operator can see and clear the leftover. Note that
   `internal_create_plan` writes a `plan_feature` row only for the features it
   is given, so such a feature may have no plan row at all.

A tenant with no active subscription returns an empty `modules` array with HTTP
200 — not `404`. The operator console reads this for any tenant id it holds, and
an unknown tenant is a normal input.

### `PATCH /internal/tenants/{tenant_id}/modules`

Operator-initiated module toggle. Enforces the same plan-entitlement and
subscription-status rules as the tenant-facing
`PATCH /tenants/me/modules`, and emits `tenant.module_toggled` on success.
`tenant_id` comes from the path because this route is authenticated by
`X-Service-Token`, not a tenant access token.

Request:

```json
{ "feature_code": "grading", "enabled": false }
```

Success (200): `{ "data": { "ok": true }, "meta": {} }`

Errors:

| Code                        | HTTP | Cause |
|-----------------------------|------|-------|
| `FEATURE_NOT_AVAILABLE`     | 403  | The tenant's current plan does not entitle `feature_code`. |
| `SUBSCRIPTION_EXPIRED`      | 403  | The tenant has no subscription, or it is not `active`. |
| `UNAUTHORIZED_SERVICE_CALL` | 401  | Missing or invalid `X-Service-Token`. |

A rejected toggle writes nothing: no `tenant_module` row and no event.

The entitlement gate runs **before** the handler inspects the requested value, so
an unentitled module cannot be switched *off* either — `{"enabled": false}` on an
unentitled feature still returns `FEATURE_NOT_AVAILABLE`.

### `POST /internal/plans`

Creates a plan and emits a plan-catalog event. Duplicate `code` returns `409`.

### `PUT /internal/plans/{plan_id}`

Updates plan metadata/features and emits a plan-catalog event. Success: `204`.

### `DELETE /internal/plans/{plan_id}`

Deactivates the plan and emits a plan-catalog event. Success: `204`.

### `POST /internal/tenants/{tenant_id}/subscription`

Overrides a tenant subscription to an existing `plan_id`. Unknown plans return
`400 UNKNOWN_PLAN`. Success: `204`.

### `GET /internal/registrations?state=&page=&page_size=`

Operator listing of registration saga rows from `pending_registration`, newest
first (`attempted_at DESC, registration_id DESC`). Service-token guarded like the
other `internal/` routes: these rows carry the email of a user who never finished
signing up and are not tenant-scoped, so no tenant JWT can authorize them.

```json
{
  "data": [
    {
      "registration_id": "uuid",
      "email": "string",
      "iam_user_id": "uuid|null",
      "tenant_id": "uuid|null",
      "state": "user_created|tenant_created|completed|failed",
      "attempted_at": "timestamp"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

`page` defaults to 1 (floor-clamped), `page_size` defaults to 20 and is clamped
to 1-100. The offset is computed with saturating arithmetic because this endpoint
is reachable directly by any service-token holder and cannot assume the caller
bounded `page`.

`state` narrows to a single value; absent or blank lists every state. It is bound
as a query parameter and never interpolated, and `NULL` means "no filter", so a
caller cannot widen the predicate. Billing does **not** reject an unrecognised
`state` — it simply matches nothing. The four-value allowlist is enforced
upstream by platform-service's `GET /registrations`, which returns
`VALIDATION_ERROR`.

Lifecycle caveats for consumers:

- Only `user_created` and `completed` are written today. `tenant_created` and
  `failed` are permitted by `pending_registration_state_chk` but have no producer.
- The janitor (`run_pending_registration_janitor`, every 60s) deletes any
  non-`completed` row older than 5 minutes after compensating the orphaned IAM
  user and tenant. `completed` rows are retained indefinitely.

### `GET /media/school/{media_id}`

Serves the logo bytes (no auth required). If the storage backend exposes a public
URL (R2), returns a 302 redirect to that URL; otherwise streams the bytes inline
with the stored content type and a one-year cache header.

## Health

### `GET /healthz`

Public. Returns 200 after `SELECT 1` against the database. The body is
the standard success envelope.
