# Academic Operations Service API

Base path: `/api/v1/academic-ops`

All responses use the standard success envelope:

```json
{ "data": {}, "meta": {} }
```

Validation errors use the standard validation envelope. Import validation uses
HTTP 422 with row-level errors.

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

Lists tenant-scoped students ordered by name.

### GET `/students/{student_id}`

Returns one tenant-scoped student.

### PATCH `/students/{student_id}`

Updates `nis`, `full_name`, `gender`, and/or `birth_date`. Requires
`academic_ops` entitlement.

## Teachers

### POST `/teachers`

Creates a teacher. Requires `academic_ops` entitlement.

Request:

```json
{ "nip": "T-001", "full_name": "Grace Hopper" }
```

Errors:

- `409 DUPLICATE_NIP` when the tenant already has the same NIP.

### GET `/teachers`

Lists tenant-scoped teachers ordered by name.

### GET `/teachers/{teacher_id}`

Returns one tenant-scoped teacher.

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

Lists tenant-scoped homerooms.

### GET `/homerooms/{homeroom_id}/students`

Lists active roster students for a homeroom and academic year.

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

Errors:

- `409 DUPLICATE_ASSIGNMENT` when the same tuple already exists.

### GET `/homerooms/{homeroom_id}/teaching-assignments`

Lists teaching assignments for a homeroom.

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
