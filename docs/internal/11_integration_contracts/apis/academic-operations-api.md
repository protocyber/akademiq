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

Creates a student. Requires `academic_ops` entitlement. Supports complete Indonesian
school biodata. Accepts an optional `initial_placement` object; when placement fails the
student profile is still created and the response includes `placement: "not_placed"`.

Request:

```json
{
  "nis": "S-001",
  "nisn": "0012345678",
  "nik": "3578010101900001",
  "full_name": "Budi Santoso",
  "gender": "male",
  "birth_date": "2012-01-31",
  "birth_place": "Surabaya",
  "address_line": "Jl. Merdeka No. 10",
  "phone_number": "081234567890",
  "religion": "islam",
  "nationality": "Indonesia",
  "child_order": 1,
  "sibling_count": 2,
  "entry_date": "2024-07-15",
  "origin_school": "SDN Sukamaju",
  "user_id": "uuid|null",
  "initial_placement": { "academic_year_id": "uuid", "homeroom_id": "uuid" }
}
```

Success (201): the created student profile (rich shape, see GET detail).

Errors:

- `409 DUPLICATE_NIS` when the tenant already has the same NIS (among non-deleted students).
- `403 FEATURE_NOT_AVAILABLE` when the tenant is not entitled to `academic_ops`.
- `400 VALIDATION_ERROR` for invalid field values (`gender`, `religion`, etc.).

### GET `/students`

Lists tenant-scoped students. Accepts `search`, `sort`, `page`, `page_size`
(see [Lists, pagination, and sorting](#lists-pagination-and-sorting)) and
returns the paginated envelope.

### GET `/students/{student_id}`

Returns one tenant-scoped student with complete biodata:

```json
{
  "data": {
    "student_id": "uuid",
    "tenant_id": "uuid",
    "user_id": "uuid|null",
    "nis": "S-001",
    "nisn": "0012345678",
    "nik": "3578010101900001",
    "full_name": "Budi Santoso",
    "gender": "male",
    "birth_date": "2012-01-31",
    "birth_place": "Surabaya",
    "address_line": "Jl. Merdeka No. 10",
    "phone_number": "081234567890",
    "photo_url": "string|null",
    "religion": "islam",
    "nationality": "Indonesia",
    "child_order": 1,
    "sibling_count": 2,
    "entry_date": "2024-07-15",
    "origin_school": "SDN Sukamaju",
    "status": "aktif",
    "archive_reason": null,
    "created_at": "...",
    "updated_at": "..."
  },
  "meta": {}
}
```

Soft-deleted students are hidden from detail endpoints (404).

### PATCH `/students/{student_id}`

Updates any of the rich student profile fields. Requires `academic_ops` entitlement.

### POST `/students/{student_id}/archive`

Archives a student. Body: `{ "reason": "lulus|pindah|keluar|meninggal|nonaktif_sementara|lainnya" }`.
Sets status to `arsip`, stores the reason, leaves enrollment history intact.

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

Creates a teacher. Requires `academic_ops` entitlement. Supports complete biodata +
employment fields.

Request:

```json
{
  "nip": "198501012010011001",
  "nik": "357801010119850001",
  "full_name": "Siti Aminah, S.Pd",
  "education_level": "s1",
  "gender": "female",
  "birth_date": "1985-01-01",
  "birth_place": "Surabaya",
  "address_line": "Jl. Pahlawan No. 5",
  "phone_number": "081234567890",
  "email": "siti.aminah@sman1.sch.id",
  "employment_status": "pns",
  "role_position": "guru_matematika",
  "start_date": "2010-07-01",
  "primary_subject_area": "matematika",
  "nuptk": "123456786123456",
  "certification_number": "cert-001",
  "user_id": "uuid|null"
}
```

Response includes `user_id` when the teacher profile has been linked to an IAM
tenant user account; otherwise `user_id` is `null`. When academic-ops has the IAM
identity projection for that linked account, response also includes
`linked_user: { "user_id": "uuid", "username": "string", "email": "string|null" }`.
If `user_id` is present but the projection has not arrived yet, `linked_user` is
`null`; clients MUST still treat the teacher profile as linked.

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

## Family profiles

All require `academic_ops` entitlement. Family profiles are reusable biodata records,
optionally linked to an IAM user. Creating/linking a family profile does **not** grant
portal access (use the guardian endpoints for that).

### POST `/family-profiles`

Creates a family profile. The response includes a `duplicate_warning` array when the
NIK, phone, or identifying details match existing profiles — creation is not blocked.

Request:

```json
{
  "full_name": "Bapak Santoso",
  "nik": "3578010101960001",
  "birth_place": "Surabaya",
  "birth_date": "1960-05-10",
  "address_line": "Jl. Merdeka No. 10",
  "phone_number": "081234567890",
  "email": "santoso@example.com",
  "occupation": "Wiraswasta",
  "income_range": "5_10_juta",
  "life_status": "hidup",
  "marital_status": "kawin",
  "nationality": "Indonesia",
  "religion": "islam",
  "education_level": "sma",
  "user_id": "uuid|null"
}
```

Response (201):

```json
{
  "data": { "family_id": "uuid", "status": "aktif", "...": "..." },
  "meta": { "duplicate_warning": [{ "family_id": "uuid", "match": "nik" }] }
}
```

### GET `/family-profiles`

Lists/searches tenant-scoped family profiles. Accepts `search`, `sort`, `page`,
`page_size` and returns the paginated envelope. Soft-deleted and archived-by-default
profiles follow the standard sort/list semantics.

### GET `/family-profiles/{family_id}`

Returns one family profile.

### PATCH `/family-profiles/{family_id}`

Updates family profile fields.

### POST `/family-profiles/{family_id}/archive`

Archives a family profile. Body: `{ "reason": "tidak_aktif|meninggal|putus_hubungan|duplikat|lainnya" }`.

### DELETE `/family-profiles/{family_id}`

Soft-deletes a family profile.

## Student-family links

### POST `/students/{student_id}/family-links`

Links a family profile to a student with relationship attributes. One family profile
can link to multiple students; one student can have multiple family profiles.

Request:

```json
{
  "family_id": "uuid",
  "relationship_type": "ayah|ibu|wali|kakek|nenek|saudara|lainnya",
  "primary_contact": true,
  "emergency_contact": true,
  "lives_with_student": true,
  "financial_responsible": true
}
```

### GET `/students/{student_id}/family-links`

Lists all family links for a student (used by the student detail Keluarga tab).

### PATCH `/students/{student_id}/family-links/{link_id}`

Updates link attributes (relationship type, flags). Body subset of the create shape.

### POST `/students/{student_id}/family-links/{link_id}/inactivate`

Marks a link inactive without archiving the family profile.

### DELETE `/students/{student_id}/family-links/{link_id}`

Removes a student-family link. Does **not** remove any guardian portal access link.

## Profile media

All require `academic_ops` entitlement.

### POST `/media`

Uploads a photo for a `teacher`, `student`, or `family` owner (multipart form).
The new photo replaces the previous one (single-active, no history retained).
The previous photo's storage object is garbage-collected on replace.

Form fields:
- `owner_type`: `teacher` | `student` | `family`
- `owner_id`: UUID of the owning entity
- `file`: image bytes (JPG/PNG/WebP, max 512 KB)

Response (201):

```json
{
  "data": { "photo_url": "/api/v1/academic-ops/media/{owner_type}/{media_id}" },
  "meta": {}
}
```

Errors: `400 VALIDATION_ERROR` (`file`, `owner_type`) for invalid type/size/owner.

### DELETE `/media`

Clears the photo for an owner: deletes the backing storage object and nulls `photo_url`.
Idempotent — an owner with no photo succeeds silently.

Query params: `owner_type`, `owner_id`.

Success (204): empty body.

### GET `/media/{owner_type}/{media_id}`

Serves the photo bytes (no auth required). If the storage backend exposes a public
URL (R2), returns a 302 redirect; otherwise streams the bytes inline with the stored
content type and a one-year cache header.
