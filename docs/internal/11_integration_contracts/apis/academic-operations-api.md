# Academic Operations Service API

Base path: `/api/v1/academic-ops`

All responses use the standard success envelope:

```json
{ "data": {}, "meta": {} }
```

Validation errors use the standard validation envelope. Import validation uses
HTTP 422 with row-level errors.

## Lists, pagination, and sorting

The list endpoints for students, teachers, homerooms, and teaching assignments
(`GET /students`, `GET /teachers`, `GET /homerooms`, `GET /teaching-assignments`)
all accept the same query parameters and return a paginated envelope:

| Parameter   | Meaning                                                                   |
| ----------- | ------------------------------------------------------------------------- |
| `search`    | Case-insensitive substring match on the resource's name field (and NIS/NIP). |
| `sort`      | A whitelisted sort key for the resource; prefix `-` for descending.        |
| `page`      | 1-based page number (default `1`).                                        |
| `page_size` | Rows per page, clamped to `1..100` (default `25`).                        |

Per-resource `sort` whitelists:

- Students: `name`, `nis`, `birth_date` (e.g. `-nis`).
- Teachers: `name`, `nip`.
- Homerooms: `name`, `grade_level`.
- Teaching assignments: `created`, `teacher`, `homeroom` (default `-created`).

An unknown `sort` value is rejected with `400 INVALID_SORT`. Teaching assignments
additionally accept `academic_year_id` and `homeroom_id` filters.

The response envelope is:

```json
{
  "data": [],
  "meta": { "page": 1, "page_size": 25, "total": 0 }
}
```

`total` reflects the full filtered count, independent of the requested page.

## Health

### GET `/healthz`

Returns service, database, and RabbitMQ health.

## Students

### POST `/students`

Creates a student. Requires `academic_ops` entitlement.

Request:

```json
{ "nis": "S-001", "full_name": "Ada Lovelace", "gender": "female", "birth_date": "2012-01-31" }
```

Errors:

- `409 DUPLICATE_NIS` when the tenant already has the same NIS.
- `403 FEATURE_NOT_AVAILABLE` when the tenant is not entitled to `academic_ops`.

### GET `/students`

Lists tenant-scoped students. Accepts `search`, `sort`, `page`, `page_size`
(see [Lists, pagination, and sorting](#lists-pagination-and-sorting)) and
returns the paginated envelope.

### GET `/students/{student_id}`

Returns one tenant-scoped student.

### PATCH `/students/{student_id}`

Updates `nis`, `full_name`, `gender`, and/or `birth_date`. Requires
`academic_ops` entitlement.

### DELETE `/students/{student_id}`

Deletes one tenant-scoped student. Requires `academic_ops` entitlement.

Errors:

- `409 STUDENT_ENROLLED` when the student has an `active` enrollment (any academic year); the student is left unchanged.
- `404 NOT_FOUND` when the student does not exist in the tenant.

### POST `/students/bulk-delete`

Bulk-deletes students in one all-or-nothing request. Every id is pre-validated
(existence + `STUDENT_ENROLLED` guard); the first violation rejects the whole
request with no deletions. Requires `academic_ops` entitlement.

Request:

```json
{ "student_ids": ["uuid", "uuid"] }
```

Errors: `409 STUDENT_ENROLLED` (whole request rejected), `404 NOT_FOUND` on an
unknown id. Returns `204 No Content` on success.

## Teachers

### POST `/teachers`

Creates a teacher. Requires `academic_ops` entitlement.

Request:

```json
{ "nip": "T-001", "full_name": "Grace Hopper" }
```

Response includes `user_id` when the teacher profile has been linked to an IAM
tenant user account; otherwise `user_id` is `null`.

Errors:

- `409 DUPLICATE_NIP` when the tenant already has the same NIP.

### GET `/teachers`

Lists tenant-scoped teachers. Accepts `search`, `sort`, `page`, `page_size`
(see [Lists, pagination, and sorting](#lists-pagination-and-sorting)) and
returns the paginated envelope.

### GET `/teachers/{teacher_id}`

Returns one tenant-scoped teacher.

### PATCH `/teachers/{teacher_id}`

Updates `nip` and `full_name` (both required). Requires `academic_ops`
entitlement.

Request:

```json
{ "nip": "T-001", "full_name": "Grace Hopper" }
```

Errors:

- `409 DUPLICATE_NIP` when the tenant already has the same NIP.
- `404 NOT_FOUND` when the teacher profile does not exist in the tenant.

### DELETE `/teachers/{teacher_id}`

Deletes one tenant-scoped teacher profile. The linked IAM login user (a row in
the IAM service database) is **not** removed. Requires `academic_ops`
entitlement.

Errors:

- `409 TEACHER_ASSIGNED` when a teaching assignment references the teacher; the teacher is left unchanged.
- `404 NOT_FOUND` when the teacher profile does not exist in the tenant.

### POST `/teachers/bulk-delete`

Bulk-deletes teachers in one all-or-nothing request (pre-validates existence +
`TEACHER_ASSIGNED`; linked login users are untouched). Requires `academic_ops`
entitlement.

Request:

```json
{ "teacher_ids": ["uuid", "uuid"] }
```

Errors: `409 TEACHER_ASSIGNED` (whole request rejected), `404 NOT_FOUND` on an
unknown id. Returns `204 No Content` on success.

### PATCH `/teachers/{teacher_id}/account`

Links a teacher profile to an IAM tenant user account. Requires `academic_ops`
entitlement. This link is included in future `teacher.assigned` events as
`teacher_user_id`, allowing the grading service to authorize grade entry from
the teacher's JWT subject.

Request:

```json
{ "user_id": "uuid" }
```

Errors:

- `404 NOT_FOUND` when the teacher profile does not exist in the tenant.
- `409 TEACHER_USER_ALREADY_LINKED` when the user account is already linked to another teacher profile in the tenant.

## Homerooms

### POST `/homerooms`

Creates a homeroom for a known active academic year. Requires `academic_ops`
entitlement and an active subscription projection.

Request:

```json
{ "name": "7A", "grade_level": "7", "capacity": 32, "academic_year_id": "uuid" }
```

Errors:

- `400 UNKNOWN_ACADEMIC_YEAR` when the year is missing from the local projection or is not active.
- `403 SUBSCRIPTION_INACTIVE` when the tenant subscription projection is inactive.

### GET `/homerooms`

Lists tenant-scoped homerooms. Accepts `search`, `sort`, `page`, `page_size`
(see [Lists, pagination, and sorting](#lists-pagination-and-sorting)) and
returns the paginated envelope.

### GET `/homerooms/{homeroom_id}/students`

Lists active roster students for a homeroom and academic year.

### DELETE `/homerooms/{homeroom_id}`

Deletes one tenant-scoped homeroom. Requires `academic_ops` entitlement.

Errors:

- `409 HOMEROOM_NOT_EMPTY` when the homeroom still has `active` enrollments; the homeroom and roster are left unchanged.
- `404 NOT_FOUND` when the homeroom does not exist in the tenant.

### POST `/homerooms/bulk-delete`

Bulk-deletes homerooms in one all-or-nothing request (pre-validates existence +
`HOMEROOM_NOT_EMPTY`). Requires `academic_ops` entitlement.

Request:

```json
{ "homeroom_ids": ["uuid", "uuid"] }
```

Errors: `409 HOMEROOM_NOT_EMPTY` (whole request rejected), `404 NOT_FOUND` on an
unknown id. Returns `204 No Content` on success.

## Enrollment

### POST `/enrollments`

Enrolls a student into a homeroom. Requires `academic_ops` entitlement.

Request:

```json
{ "student_id": "uuid", "homeroom_id": "uuid", "transfer": false }
```

Set `transfer: true` to atomically mark any existing active enrollment in the
same academic year as `transferred` and create a new active enrollment.

Errors:

- `409 ALREADY_ENROLLED` when `transfer` is false and the student already has an active enrollment for the year.

### DELETE `/enrollments/{enrollment_id}`

Marks an enrollment as `unenrolled`. Requires `academic_ops` entitlement.

## Teaching Assignments

### POST `/teaching-assignments`

Creates a teacher/subject/homeroom/year assignment and emits
`teacher.assigned`. Requires `academic_ops` entitlement.

Request:

```json
{ "teacher_id": "uuid", "subject_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" }
```

The emitted event includes `teacher_user_id` when the teacher profile has been
linked to an IAM user account. If it is `null`, grading rejects writes for that
assignment with `TEACHER_ACCOUNT_NOT_LINKED` until the profile is linked and a
new assignment event is emitted.

Errors:

- `409 DUPLICATE_ASSIGNMENT` when the same tuple already exists.

### GET `/teaching-assignments`

Lists tenant-scoped teaching assignments. Accepts `search` (matches the
teacher's name), `sort`, `page`, `page_size`, plus the filters `academic_year_id`
and `homeroom_id` (see [Lists, pagination, and sorting](#lists-pagination-and-sorting)),
and returns the paginated envelope.

### DELETE `/teaching-assignments/{assignment_id}`

Deletes one tenant-scoped teaching assignment. Always succeeds for an existing
tenant-owned assignment (no referential guard). Requires `academic_ops`
entitlement. Returns `204 No Content`; `404 NOT_FOUND` if the assignment is
unknown.

### POST `/teaching-assignments/bulk-delete`

Bulk-deletes teaching assignments (always allowed for tenant-owned rows).
Requires `academic_ops` entitlement.

Request:

```json
{ "assignment_ids": ["uuid", "uuid"] }
```

Returns `204 No Content` on success.

### GET `/homerooms/{homeroom_id}/teaching-assignments`

Lists teaching assignments for a homeroom (homeroom-scoped variant).

## Imports

### POST `/imports/students`

Accepts multipart field `file`, parses the first spreadsheet sheet, validates
all rows, and inserts all students in one transaction.

Required columns: `nis`, `full_name`, `gender`, `birth_date`.

### POST `/imports/teachers`

Accepts multipart field `file`, parses the first spreadsheet sheet, validates
all rows, and inserts all teachers in one transaction.

Required columns: `nip`, `full_name`.

### GET `/imports/template`

Returns the documented import column names for student and teacher templates.

Import validation failure:

```json
{
  "error": { "code": "IMPORT_VALIDATION_FAILED", "message": "import validation failed" },
  "rows": [{ "row": 2, "errors": { "nis": ["duplicate in file"] } }]
}
```
