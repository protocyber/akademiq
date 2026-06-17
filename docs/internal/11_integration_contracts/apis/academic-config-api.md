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
    "status": "Draft"
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

Returns academic years for the caller's tenant as a server-driven, paginated
list. Query parameters:

| Param | Default | Notes |
|-------|---------|-------|
| `search` | (none) | Case-insensitive substring on `name`. |
| `sort` | `name` | Whitelist: `name`, `-name`, `start_date`, `-start_date`, `status`, `-status`. An unknown value is rejected with `INVALID_SORT`. |
| `page` | `1` | 1-based. |
| `page_size` | `25` | Clamped to `[1, 100]`. |

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
      "status": "Draft"
    }
  ],
  "meta": { "page": 1, "page_size": 25, "total": 3 }
}
```

Errors: `INVALID_SORT` (400) when `sort` is outside the whitelist.

### `GET /academic-years/{academic_year_id}`

Returns one tenant-scoped academic year.

Errors: `NOT_FOUND` when the id is absent or belongs to another tenant.

### `DELETE /academic-years/{academic_year_id}`

Deletes a single academic year. Rejects `Active` years and years referenced
by homerooms or teaching assignments (projected from `homeroom.created` /
`teacher.assigned` events).

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `ACTIVE_YEAR_IMMUTABLE` | 409 | The year's status is `Active`. |
| `YEAR_IN_USE` | 409 | A homeroom or teaching assignment references the year. |
| `NOT_FOUND` | 404 | Academic year is missing or belongs to another tenant. |

Success: `204 No Content`.

### `POST /academic-years/bulk/delete`

Bulk delete academic years, all-or-nothing. Any guard violation in the set
rejects the whole request with no deletions.

Request:

```json
{ "ids": ["uuid", "uuid"] }
```

Errors: `ACTIVE_YEAR_IMMUTABLE` / `YEAR_IN_USE` (409), `NOT_FOUND` (404).
Success: `204 No Content`.

### `PATCH /academic-years/{academic_year_id}/status`

Request:

```json
{
  "status": "Active",
  "reason": "Alasan transisi ke aktif yang sah"
}
```

Valid lifecycle transitions:
- `Draft` ↔ `Active`
- `Active` ↔ `Closed`
- `Closed` → `Archived`

Any transition out of `Archived` is illegal. Every transition requires a non-empty `reason` parameter of at least 10 characters for audit tracking.

Success (200): returns the updated academic year envelope.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `INVALID_STATE_TRANSITION` | 409 | Requested status is not a legal lifecycle state transition. |
| `ACTIVE_YEAR_EXISTS` | 409 | Tenant already has another `Active` year. |
| `TERM_STILL_ACTIVE` | 409 | Year cannot transition to `Closed` while a child term is `Active`. |
| `VALIDATION_ERROR` | 400 | The `reason` is missing, empty, or less than 10 characters. |
| `FEATURE_NOT_AVAILABLE` | 403 | Caller cannot write academic config. |
| `NOT_FOUND` | 404 | Academic year is missing or belongs to another tenant. |

## Academic Terms

Terms are child periods within an academic year (e.g. "Semester 1", "Semester 2"). A default term (`"Semester 1"`) is auto-created when a year is created. All term endpoints are gated on `academic.config.read` (GETs) and `academic.config.write` (writes).

### `POST /academic-years/{academic_year_id}/terms`

Request:

```json
{
  "name": "Semester 2",
  "start_date": "2027-01-01",
  "end_date": "2027-06-30"
}
```

Success (201):

```json
{
  "data": {
    "term_id": "uuid",
    "academic_year_id": "uuid",
    "tenant_id": "uuid",
    "name": "Semester 2",
    "start_date": "2027-01-01",
    "end_date": "2027-06-30",
    "status": "Draft"
  },
  "meta": {}
}
```

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `TERM_OVERLAP` | 409 | Date range overlaps with an existing term in the year. |
| `TERM_NAME_EXISTS` | 409 | A term with the same name already exists in the year. |
| `VALIDATION_ERROR` | 400 | Field validation failed (name, dates). |
| `NOT_FOUND` | 404 | Parent academic year not found. |

Creates an `academic_term.created` outbox event on success.

### `GET /academic-years/{academic_year_id}/terms`

Returns terms for the selected academic year as a paginated list.

Query parameters: `sort` (`start_date`, `-start_date`, `name`, `-name`), `page`, `page_size`.

```json
{
  "data": [
    {
      "term_id": "uuid",
      "academic_year_id": "uuid",
      "tenant_id": "uuid",
      "name": "Semester 1",
      "start_date": "2026-07-01",
      "end_date": "2026-12-31",
      "status": "Active"
    }
  ],
  "meta": { "page": 1, "page_size": 25, "total": 2 }
}
```

### `GET /academic-terms/{term_id}`

Returns one tenant-scoped academic term.

Errors: `NOT_FOUND` (404).

### `PATCH /academic-terms/{term_id}`

Updates `name`, `start_date`, and `end_date`. Rejected when the term is `Archived`.

```json
{
  "name": "Semester 1",
  "start_date": "2026-07-01",
  "end_date": "2026-12-31"
}
```

Success (200): the updated term envelope.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `TERM_OVERLAP` | 409 | Updated range overlaps with another term in the year. |
| `TERM_NAME_EXISTS` | 409 | Name already used by another term in the year. |
| `VALIDATION_ERROR` | 400 | Field validation failed. |
| `NOT_FOUND` | 404 | Term not found. |

### `DELETE /academic-terms/{term_id}`

Deletes a term. Rejected when the term is `Active` or `Archived`.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `TERM_NOT_DELETABLE` | 409 | Term status is `Active` or `Archived`. |
| `NOT_FOUND` | 404 | Term not found. |

Success: `204 No Content`.

### `PATCH /academic-terms/{term_id}/status`

Request:

```json
{
  "status": "Active",
  "reason": "Semester dimulai resmi hari ini"
}
```

Valid lifecycle transitions: `Draft` ↔ `Active`, `Active` ↔ `Closed`, `Closed` → `Archived`. Every transition requires a `reason` of at least 10 characters.

Success (200): the updated term envelope.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `INVALID_STATE_TRANSITION` | 409 | Transition is not legal. |
| `ACTIVE_TERM_EXISTS` | 409 | Another term in the year is already `Active`. |
| `VALIDATION_ERROR` | 400 | `reason` is missing or less than 10 characters. |
| `NOT_FOUND` | 404 | Term not found. |

Creates an `academic_term.status_changed` outbox event on success.

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

Returns curriculum versions for the selected academic year as a paginated
list. Query parameters: `search` (substring on `name`), `sort` (`name`,
`-name`, `created_at`, `-created_at`), `page`, `page_size`. Unknown `sort` →
`INVALID_SORT`.

```json
{
  "data": [{ "curriculum_version_id": "uuid", "...": "..." }],
  "meta": { "page": 1, "page_size": 25, "total": 2 }
}
```

### `PATCH /curriculum-versions/{curriculum_version_id}`

Updates `name` and `description`.

```json
{ "name": "K13", "description": "Revisi 2026" }
```

Success (200): the updated version envelope.
Errors: `VALIDATION_ERROR` (400), `NOT_FOUND` (404).

### `DELETE /curriculum-versions/{curriculum_version_id}`

Deletes a curriculum version. Rejects versions that still have subjects.

Errors: `CURRICULUM_IN_USE` (409), `NOT_FOUND` (404). Success: `204`.

### `POST /curriculum-versions/bulk/delete`

All-or-nothing bulk delete. Request: `{ "ids": ["uuid"] }`.
Errors: `CURRICULUM_IN_USE` (409), `NOT_FOUND` (404). Success: `204`.

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

Returns subjects under the selected curriculum version as a paginated list.
Query parameters: `search` (substring on `name` or `code`), `sort` (`name`,
`-name`, `code`, `-code`, `passing_grade`, `-passing_grade`), `page`,
`page_size`. Unknown `sort` → `INVALID_SORT`.

```json
{
  "data": [{ "subject_id": "uuid", "...": "..." }],
  "meta": { "page": 1, "page_size": 25, "total": 5 }
}
```

### `PATCH /subjects/{subject_id}`

Updates `name`, `code`, and `passing_grade`.

```json
{ "name": "Matematika", "code": "MTK", "passing_grade": 70 }
```

Success (200): the updated subject envelope.
Errors: `VALIDATION_ERROR` (400), `NOT_FOUND` (404).

### `DELETE /subjects/{subject_id}`

Deletes a subject. Rejects subjects referenced by a teaching assignment
(projected from `teacher.assigned`).

Errors: `SUBJECT_IN_USE` (409), `NOT_FOUND` (404). Success: `204`.

### `POST /subjects/bulk/delete`

All-or-nothing bulk delete. Request: `{ "ids": ["uuid"] }`.
Errors: `SUBJECT_IN_USE` (409), `NOT_FOUND` (404). Success: `204`.

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

Returns class templates for the selected academic year as a paginated list.
Query parameters: `search` (substring on `grade_level`), `sort`
(`grade_level`, `-grade_level`, `default_capacity`,
`-default_capacity`), `page`, `page_size`. Unknown `sort` → `INVALID_SORT`.

```json
{
  "data": [{ "template_id": "uuid", "...": "..." }],
  "meta": { "page": 1, "page_size": 25, "total": 3 }
}
```

### `PATCH /class-templates/{template_id}`

Updates `grade_level` and `default_capacity`.

```json
{ "grade_level": "XI", "default_capacity": 32 }
```

Success (200): the updated template envelope.
Errors: `VALIDATION_ERROR` (400), `NOT_FOUND` (404).

### `DELETE /class-templates/{template_id}`

Deletes a class template. Templates are advisory, so delete always succeeds
when the template exists and belongs to the tenant.

Errors: `NOT_FOUND` (404). Success: `204`.

### `POST /class-templates/bulk/delete`

All-or-nothing bulk delete. Request: `{ "ids": ["uuid"] }`.
Errors: `NOT_FOUND` (404). Success: `204`.

## Health

### `GET /healthz`

Public. Checks Postgres and RabbitMQ connectivity.

Success (200):

```json
{ "data": { "status": "ok" }, "meta": {} }
```
