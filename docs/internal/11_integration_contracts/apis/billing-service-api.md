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
  "admin_password": "string (>=8 chars)?",
  "admin_full_name": "string"
}
```

**`admin_password` is optional.** Omitting it registers the school without
anyone choosing, seeing, or transporting the admin's password: IAM creates a
`pending` account and returns a one-time link, which this endpoint forwards as
`activation_link`. A *supplied* password is still held to the eight-character
minimum — the optionality widens what may be absent, not what may be weak — and
`None` must never be replaced by a placeholder, since the missing password is
exactly what makes IAM mint a set-password token instead of hashing one.

Success (201):

```json
{
  "data": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "subscription_id": "uuid",
    "plan_code": "starter|standard|premium",
    "activation_link": "https://app.example/set-password?token=<token>"
  },
  "meta": {}
}
```

`activation_link` is serialised with `skip_serializing_if = "Option::is_none"`,
so it is **absent from the wire** — not `null` — whenever no link was minted.
Clients must type it as optional. It is present only for a passwordless
registration; a password-bearing one has nothing to hand over, and
`POST /tenants/register-for-user` attaches an already-authenticated account and
never carries one.

**The link is shown once and is not retrievable afterwards.** IAM stores only an
Argon2 hash of the token and will not mint a second one for a `pending` user, so
this response is the only place it exists. Billing forwards IAM's URL verbatim
rather than re-deriving one — the token resolves only on the page IAM chose
(`/set-password`, not `/invitations/accept`) — and neither logs nor persists it.
`RegisterTenantOutput`'s hand-written `Debug` redacts the field so a `?out`
trace cannot print it.

Errors:

| Code                  | HTTP | Cause |
|-----------------------|------|-------|
| `VALIDATION_ERROR`    | 400  | Per-field errors (`admin_email`, `admin_password`, `school_name`, `admin_full_name`, `plan_id`). An unknown `plan_id` is reported here, as field `plan_id`. |
| `UNKNOWN_PLAN`        | 400  | The plan disappeared between validation and subscription creation. |
| `EMAIL_ALREADY_EXISTS`| 409  | IAM rejected the user creation; tenant row not committed. |

The handler emits `tenant.registered` and `subscription.activated`
events via the transactional outbox before returning 201. See
`docs/internal/11_integration_contracts/events/`.

Either failure parks the saga's `pending_registration` row in `failed` with a
`failure_reason`, readable through `GET /internal/registrations` below.

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

### `POST /internal/tenants`

Operator-initiated school registration, behind platform-service's
`POST /platform/tenants`. Routes through the same `register_tenant` command as
the public `POST /tenants/register`, so validation, the IAM call, the
subscription, the outbox events, and the compensating delete on failure are
shared rather than reimplemented.

Request:

```json
{
  "school_name": "SMA Harapan",
  "plan_id": "uuid",
  "admin_email": "kepala@harapan.test",
  "admin_full_name": "Kepala Harapan"
}
```

**There is no `admin_password` field, and there is no way to supply one.** The
request type simply does not have it, so this route can only ever take the
passwordless path — a property of the type rather than a convention a future
caller can ignore. The operator console must never choose, see, or transport a
school's password; it receives a one-time link to hand over instead.

Success (**201**) — the same `RegisterTenantOutput` envelope as
`POST /tenants/register`, where `activation_link` is therefore always present:

```json
{
  "data": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "subscription_id": "uuid",
    "plan_code": "premium",
    "activation_link": "https://app.example/set-password?token=<token>"
  },
  "meta": {}
}
```

**The link is shown once and is not retrievable afterwards.** See
`POST /tenants/register` above for the full rule; the recovery path when it is
lost is IAM's operator invitation, not a re-read of this response.

Errors: as `POST /tenants/register`, plus `401 UNAUTHORIZED_SERVICE_CALL` for a
missing or wrong `X-Service-Token`. A failed registration is parked in `failed`
with a `failure_reason`.

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

### `GET /internal/registrations?state=&sort=&page=&page_size=`

Operator listing of registration saga rows from `pending_registration`, newest
first by default (`attempted_at DESC, registration_id DESC`). Service-token
guarded like the other `internal/` routes: these rows carry the email of a user
who never finished signing up and are not tenant-scoped, so no tenant JWT can
authorize them.

```json
{
  "data": [
    {
      "registration_id": "uuid",
      "email": "string",
      "iam_user_id": "uuid|null",
      "tenant_id": "uuid|null",
      "state": "user_created|tenant_created|completed|failed",
      "attempted_at": "timestamp",
      "failure_reason": "string|null"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

`failure_reason` is why a `failed` row stopped, and `null` for every other
state. It is written only by `domain::failure_reason`, never from a raw error
string, which fixes three properties consumers can rely on:

- It is **prefixed with the `AppError` code** — `CONFLICT: …`,
  `VALIDATION_ERROR: …` — so an operator can classify it at a glance. The prefix
  is for a human reader; `state` remains the machine-readable signal.
- It is **sanitised**. An `AppError::Internal` never contributes its text: it is
  replaced wholesale with
  `INTERNAL_ERROR: registration failed unexpectedly; see service logs`. That
  variant wraps an arbitrary `Box<dyn Error>` — a `sqlx` driver error, a
  `reqwest` failure, an `anyhow` chain around a downstream response body — and a
  downstream body on this path can contain a live activation link. Every other
  variant carries a message this codebase or IAM's error envelope authored, so
  those are kept. The dropped detail still reaches the service log.
- It is **truncated to 300 bytes** on a character boundary, with the trailing
  `…` charged against the budget rather than appended to it, so one pathological
  downstream body cannot turn a stalled registration into an unbounded row.

`mark_failed` deliberately leaves `attempted_at` alone: the janitor reaps on it,
and bumping it would buy every failed row a fresh TTL and delay cleanup of the
orphaned IAM user the saga just abandoned.

`page` defaults to 1 (floor-clamped), `page_size` defaults to 20 and is clamped
to 1-100. The offset is computed with saturating arithmetic because this endpoint
is reachable directly by any service-token holder and cannot assume the caller
bounded `page`.

`sort` accepts `attempted_at`, `email`, `state` and their `-` forms; absent or
blank means `-attempted_at`. Unlike `state`, an unrecognised value is **rejected**
with `VALIDATION_ERROR` on field `sort` — the chosen clause is interpolated into
the statement, so it must come from a closed set. Operator input never reaches
SQL: it selects one of those variants or the request fails. Every ordering ends in
`registration_id` so paging cannot drop or duplicate a row when several sagas
share an `attempted_at`, which a batch of registrations routinely does.

`state` narrows to a single value; absent or blank lists every state. It is bound
as a query parameter and never interpolated, and `NULL` means "no filter", so a
caller cannot widen the predicate. Billing does **not** reject an unrecognised
`state` — it simply matches nothing. The four-value allowlist is enforced
upstream by platform-service's `GET /registrations`, which returns
`VALIDATION_ERROR`.

Lifecycle caveats for consumers:

- `failed` **has a producer**: `register_tenant` parks the row there at both of
  its failure points — when IAM refuses to create the admin, and when
  tenant/subscription creation fails afterwards. The second one records the
  reason *before* the compensating IAM delete, because that delete can itself
  fail, and the reason is the only thing that tells an operator which of the two
  happened. `tenant_created` is still permitted by
  `pending_registration_state_chk` with no producer.
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
