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
    "logo_media_id": "uuid|null",
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

## School profile media

### `GET /tenants/me/school-profile/media`

Returns the media history for the school logo (active first, then previous assets).

```json
{
  "data": [
    {
      "media_id": "uuid",
      "owner_type": "school",
      "owner_id": "uuid",
      "file_url": "string",
      "content_type": "image/jpeg",
      "size_bytes": 51200,
      "is_active": true,
      "uploaded_at": "2026-06-19T00:00:00Z"
    }
  ],
  "meta": {}
}
```

### `POST /tenants/me/school-profile/media`

Uploads a new school logo (multipart `file`). Validates JPG/PNG/WebP up to 2MB.
The new asset becomes active and previous assets remain visible in history.

Errors: `400 VALIDATION_ERROR` (`file` field) for invalid type/size.

## Health

### `GET /healthz`

Public. Returns 200 after `SELECT 1` against the database. The body is
the standard success envelope.
