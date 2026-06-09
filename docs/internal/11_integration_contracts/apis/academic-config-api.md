# Academic Config Service API

Base path: `/api/v1/academic-config`. All endpoints use the standard
success and error envelopes from `13_engineering_standards/03_api_conventions.md`.
Authenticated endpoints resolve `tenant_id` from the JWT and never from the
request body.

Writes require the `academic_config` entitlement and a tenant/admin-capable
principal. Academic-year creation also requires an active subscription projection
from `subscription.activated`.

## Academic Years

### `POST /academic-years`

Request:

```json
{
  "name": "2026/2027",
  "start_date": "2026-07-01",
  "end_date": "2027-06-30"
}
```

Success (201):

```json
{
  "data": {
    "academic_year_id": "uuid",
    "tenant_id": "uuid",
    "name": "2026/2027",
    "start_date": "2026-07-01",
    "end_date": "2027-06-30",
    "status": "Planning"
  },
  "meta": {}
}
```

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `FEATURE_NOT_AVAILABLE` | 403 | Caller is not entitled to `academic_config` or cannot write config. |
| `SUBSCRIPTION_INACTIVE` | 403 | No active subscription projection exists for the tenant. |
| `VALIDATION_ERROR` | 400 | Field validation failed. |

Creates an `academic_year.created` outbox event on success.

### `GET /academic-years`

Returns all academic years for the caller's tenant.

Success (200):

```json
{
  "data": [
    {
      "academic_year_id": "uuid",
      "tenant_id": "uuid",
      "name": "2026/2027",
      "start_date": "2026-07-01",
      "end_date": "2027-06-30",
      "status": "Planning"
    }
  ],
  "meta": {}
}
```

### `GET /academic-years/{academic_year_id}`

Returns one tenant-scoped academic year.

Errors: `NOT_FOUND` when the id is absent or belongs to another tenant.

### `PATCH /academic-years/{academic_year_id}/status`

Request:

```json
{ "status": "Configuration" }
```

Valid lifecycle: `Planning` → `Configuration` → `Active` → `Locked` →
`Finalizing` → `Closed` → `Archived`.

Success (200): returns the updated academic year envelope.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `INVALID_STATE_TRANSITION` | 409 | Requested status is not the next legal lifecycle state. |
| `ACTIVE_YEAR_EXISTS` | 409 | Tenant already has another `Active` year. |
| `FEATURE_NOT_AVAILABLE` | 403 | Caller cannot write academic config. |
| `NOT_FOUND` | 404 | Academic year is missing or belongs to another tenant. |

## Curriculum Versions

### `POST /academic-years/{academic_year_id}/curriculum-versions`

Request:

```json
{
  "name": "Kurikulum Merdeka",
  "description": "Primary curriculum for the year"
}
```

Success (201):

```json
{
  "data": {
    "curriculum_version_id": "uuid",
    "tenant_id": "uuid",
    "academic_year_id": "uuid",
    "name": "Kurikulum Merdeka",
    "description": "Primary curriculum for the year"
  },
  "meta": {}
}
```

### `GET /academic-years/{academic_year_id}/curriculum-versions`

Returns all curriculum versions for the selected academic year.

## Subjects

### `POST /curriculum-versions/{curriculum_version_id}/subjects`

Request:

```json
{
  "name": "Matematika",
  "code": "MTK",
  "passing_grade": 75
}
```

Success (201):

```json
{
  "data": {
    "subject_id": "uuid",
    "tenant_id": "uuid",
    "curriculum_version_id": "uuid",
    "name": "Matematika",
    "code": "MTK",
    "passing_grade": 75
  },
  "meta": {}
}
```

Errors: `VALIDATION_ERROR` (400) when `passing_grade` is outside `[0, 100]`.

### `GET /curriculum-versions/{curriculum_version_id}/subjects`

Returns all subjects under the selected curriculum version.

## Grading Policy

### `PUT /academic-years/{academic_year_id}/grading-policy`

Upserts the single grading policy for the selected academic year.

Request:

```json
{
  "minimum_passing_score": 75,
  "grading_scale": "0-100"
}
```

Allowed `grading_scale` values: `0-100`, `A-E`.

Success (200):

```json
{
  "data": {
    "policy_id": "uuid",
    "tenant_id": "uuid",
    "academic_year_id": "uuid",
    "minimum_passing_score": 75,
    "grading_scale": "0-100"
  },
  "meta": {}
}
```

Errors: `VALIDATION_ERROR` (400) when the scale is not allowed or the minimum
passing score is outside `[0, 100]`.

### `GET /academic-years/{academic_year_id}/grading-policy`

Returns the current grading policy for the selected academic year.

Errors: `NOT_FOUND` (404) when no policy exists for the year.

## Class Templates

### `POST /academic-years/{academic_year_id}/class-templates`

Request:

```json
{
  "grade_level": "Kelas 7",
  "default_capacity": 32
}
```

Success (201):

```json
{
  "data": {
    "template_id": "uuid",
    "tenant_id": "uuid",
    "academic_year_id": "uuid",
    "grade_level": "Kelas 7",
    "default_capacity": 32
  },
  "meta": {}
}
```

### `GET /academic-years/{academic_year_id}/class-templates`

Returns all class templates for the selected academic year.

## Health

### `GET /healthz`

Public. Checks Postgres and RabbitMQ connectivity.

Success (200):

```json
{ "data": { "status": "ok" }, "meta": {} }
```
