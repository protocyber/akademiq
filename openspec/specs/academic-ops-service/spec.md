# academic-ops-service Specification

## Purpose

Defines tenant-scoped academic operations for students, teachers, homerooms, enrollment, teaching assignments, spreadsheet import, and academic-ops event publication under `/api/v1/academic-ops`.
## Requirements
### Requirement: Academic Ops service SHALL manage students, teachers, homerooms, enrollment, and teaching assignments under `/api/v1/academic-ops`

The service MUST provide tenant-scoped CRUD for students and teachers,
homeroom creation and roster listing, enrollment, and teaching assignment,
under `/api/v1/academic-ops`, following the standard API envelopes. All
resources MUST be scoped to the tenant from the JWT.

List endpoints for students, teachers, homerooms, and teaching assignments MUST
accept `search`, `sort`, `page`, and `page_size` query parameters and MUST
return a `{ data, meta: { page, page_size, total } }` envelope. `sort` MUST be
validated against a per-resource whitelist and an unknown value MUST be rejected
with HTTP 400 `INVALID_SORT`. `search` MUST match the resource's name field
(and NIS/NIP where present) case-insensitively.

#### Scenario: Student is created with a tenant-unique NIS

- **WHEN** a tenant admin POSTs `{ nis, full_name, gender, birth_date }` to `/students`
- **THEN** the response is HTTP 201 with the new student, and a second POST with the same `nis` for that tenant returns HTTP 409 `DUPLICATE_NIS`

#### Scenario: Homeroom roster lists actively enrolled students

- **WHEN** a tenant admin GETs `/homerooms/{id}/students`
- **THEN** the response lists exactly the students whose enrollment in that homeroom for its academic year has status `active`

#### Scenario: Student list returns a paginated envelope

- **WHEN** a tenant admin GETs `/students?search=budi&sort=-nis&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-ops list endpoint with `sort=` outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

### Requirement: Students, teachers, homerooms, and teaching assignments SHALL support delete, and teachers SHALL support edit

The service MUST expose teacher update (PATCH) and delete (single + bulk)
endpoints for students, teachers, homerooms, and teaching assignments, all
tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing: it MUST
pre-validate every id and, on the first violation, reject the entire request
with no deletions.

- Student: `DELETE /students/{id}` MUST be rejected with HTTP 409
  `STUDENT_ENROLLED` when the student has an `active` enrollment.
- Teacher: `PATCH /teachers/{id}` MUST update NIP and full name; `DELETE` MUST be
  rejected with HTTP 409 `TEACHER_ASSIGNED` when a teaching assignment references
  the teacher. Deleting a teacher MUST NOT delete any linked login user.
- Homeroom: `DELETE /homerooms/{id}` MUST be rejected with HTTP 409
  `HOMEROOM_NOT_EMPTY` when it has active enrollments.
- Teaching assignment: `DELETE /teaching-assignments/{id}` MUST always succeed
  for an existing tenant-owned assignment.

#### Scenario: Editing a teacher updates it in place

- **WHEN** a tenant admin PATCHes `/teachers/{id}` with a new `{ nip, full_name }`
- **THEN** the response is HTTP 200 with the updated teacher and a subsequent list reflects the new values

#### Scenario: Deleting an enrolled student is rejected

- **WHEN** a tenant admin DELETEs a student who has an `active` enrollment
- **THEN** the response is HTTP 409 `STUDENT_ENROLLED` and the student is unchanged

#### Scenario: Deleting an assigned teacher is rejected and the login is untouched

- **WHEN** a tenant admin DELETEs a teacher referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ASSIGNED`, the teacher is unchanged, and any linked login user is unaffected

#### Scenario: Deleting a non-empty homeroom is rejected

- **WHEN** a tenant admin DELETEs a homeroom that still has active enrollments
- **THEN** the response is HTTP 409 `HOMEROOM_NOT_EMPTY` and the homeroom and its roster are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of student ids where one has an active enrollment
- **THEN** the response rejects the whole request with HTTP 409 `STUDENT_ENROLLED` and none of the students in the set are deleted

### Requirement: A student SHALL have at most one active enrollment per academic year

The service MUST enforce that a student is actively enrolled in only one
homeroom for a given academic year. Transferring a student between homerooms in
the same year MUST mark the prior enrollment non-active and create a new active
one atomically.

#### Scenario: Second active enrollment in the same year is rejected

- **WHEN** a student already has an `active` enrollment for an academic year and another `POST /enrollments` is made for the same student and year
- **THEN** the response is HTTP 409 `ALREADY_ENROLLED` and only one active enrollment exists

#### Scenario: Transfer keeps a single active enrollment

- **WHEN** a tenant admin transfers an enrolled student to a different homeroom in the same year
- **THEN** the prior enrollment becomes `transferred`, a new `active` enrollment is created, and the student still has exactly one active enrollment for that year

### Requirement: Homeroom creation SHALL require a known active academic year and active subscription

The service MUST consume `academic_year.created` and `subscription.activated`
and gate homeroom creation behind a known active academic year, the
`academic_ops` feature entitlement, and an active subscription.

#### Scenario: Homeroom for an unknown year is rejected

- **WHEN** a tenant admin POSTs a homeroom whose `academic_year_id` the service has not received via `academic_year.created`
- **THEN** the response is HTTP 422 `UNKNOWN_ACADEMIC_YEAR`

#### Scenario: Non-entitled tenant cannot write operational data

- **WHEN** a tenant whose plan does not entitle `academic_ops` POSTs to any write endpoint
- **THEN** the response is HTTP 403 `FEATURE_NOT_AVAILABLE`

### Requirement: Teaching assignment SHALL link a teacher, subject, homeroom, and year and emit `teacher.assigned`

The service MUST expose `POST /teaching-assignments` accepting
`{ teacher_id, subject_id, homeroom_id, academic_year_id }`, reject duplicate
tuples, and emit a `teacher.assigned` event so downstream services can
authorize who may grade which subject in which class.

#### Scenario: Assignment emits the authorization tuple

- **WHEN** a teaching assignment is created successfully
- **THEN** a `teacher.assigned` event carrying `{ tenant_id, teacher_id, subject_id, homeroom_id, academic_year_id }` is published to RabbitMQ

#### Scenario: Duplicate assignment is rejected

- **WHEN** an identical `(teacher_id, subject_id, homeroom_id, academic_year_id)` assignment already exists
- **THEN** the response is HTTP 409 `DUPLICATE_ASSIGNMENT`

### Requirement: Excel import SHALL validate every row and roll back on any failure

The service MUST provide `POST /imports/students` and `POST /imports/teachers`
that parse an uploaded spreadsheet, validate all rows server-side, and either
import the whole batch or import nothing while returning a row-level error
report.

#### Scenario: A single bad row aborts the whole import

- **WHEN** a spreadsheet with one invalid row is uploaded
- **THEN** the response is HTTP 422 `IMPORT_VALIDATION_FAILED` with a per-row error report, and no rows from that file are persisted

#### Scenario: A fully valid sheet imports every row

- **WHEN** a spreadsheet whose rows all pass validation is uploaded
- **THEN** the response is HTTP 201 with an imported-count summary and every row is persisted in a single transaction

### Requirement: The importer SHALL translate Indonesian gender labels

`parse_students` and `parse_teachers` in `imports.rs` MUST translate common
Indonesian gender labels to their English backend values before passing to
validation. The mapping MUST include at minimum: `laki-laki`/`laki laki`/
`pria`/`l` → `male`; `perempuan`/`wanita`/`p` → `female`. Values that are
already `male`/`female` MUST pass through unchanged. Unknown values MUST pass
through to validation, which rejects them.

#### Scenario: Indonesian gender label in student import

- **WHEN** a student import file has `gender = "Laki-laki"` in a row
- **THEN** the importer translates it to `"male"` and the row is accepted

#### Scenario: English gender value passes through

- **WHEN** a student import file has `gender = "male"` in a row
- **THEN** the value is accepted as-is without translation

#### Scenario: Unknown gender value rejected

- **WHEN** a student import file has `gender = "xyz"` in a row
- **THEN** the translation does not match and validation rejects it with `VALIDATION_ERROR`

### Requirement: The template endpoint SHALL return column metadata

`GET /api/v1/academic-ops/imports/template` MUST return the column list with
Indonesian labels, required/optional flags, and format hints for both student
and teacher templates. This enables the frontend to render dynamic guidance if
needed.

#### Scenario: Template metadata response

- **WHEN** a client calls `GET /imports/template`
- **THEN** the response includes for each column: `field` (English key), `label` (Indonesian), `required` (boolean), and `format` (e.g. "date", "integer", "text")

### Requirement: Enrollment SHALL emit `student.enrolled`

On successful enrollment the service MUST emit `student.enrolled` consistent
with the existing contract under
`docs/internal/11_integration_contracts/events/student-enrolled.md`.

This includes both manual enrollment via `POST /enrollments` and initial
placement during student creation via `POST /students` with
`initial_placement`. Both paths MUST emit the same event within the same
database transaction as the enrollment INSERT.

#### Scenario: Enrollment publishes the event

- **WHEN** a student is enrolled into a homeroom for an academic year via `POST /enrollments`
- **THEN** a `student.enrolled` event is published to RabbitMQ with the documented payload

#### Scenario: Initial placement publishes the event

- **WHEN** a student is created with `initial_placement` and the placement succeeds
- **THEN** a `student.enrolled` event is published to RabbitMQ with the documented payload, in the same transaction as the enrollment INSERT

### Requirement: Academic Ops SHALL store and serve student and teacher photos

The academic-ops service SHALL accept photo uploads for students and teachers
through `POST /api/v1/academic-ops/media`, store the bytes via the shared
`common-media` library, record a `media_asset` row, and reflect the new active
asset onto the owning entity's `photo_media_id` in the same transaction. It MUST
expose `GET /api/v1/academic-ops/media/:media_id` to serve the stored bytes with
their recorded content type. Stored references MUST use the shared library's URL
scheme and MUST NOT be debug-formatted paths.

#### Scenario: Upload a student photo

- **WHEN** an admin uploads a valid image for a student
- **THEN** the photo is stored, `student.photo_media_id` is set to the new asset, and the previous active asset for that student is deactivated

#### Scenario: Serve a stored photo

- **WHEN** a client requests an existing academic-ops media id
- **THEN** the service responds 200 with the stored content type and the file bytes

#### Scenario: Stored reference is a usable URL

- **WHEN** a photo is stored
- **THEN** the recorded `file_url` is a valid media URI (not `file://"…"` debug output) that resolves to the serve endpoint

### Requirement: Media SHALL support bulk hard deletion per owner

academic-ops-service SHALL expose
`DELETE /api/v1/academic-ops/media?owner_type=&owner_id=` that removes
**all** media asset rows (active and inactive history) for the given owner
within the tenant, deletes every matching storage object (key reconstructed
as `{owner_type}/{media_id}`), and nulls the owning entity's
`photo_media_id`. The operation is tenant-scoped (resolved from the JWT,
never client-supplied) and hard: rows and bytes are permanently removed.

#### Scenario: Bulk delete removes active and history for an owner

- **WHEN** an owner's media is bulk-deleted
- **THEN** all of that owner's `media_asset` rows are removed, every
  matching storage object is deleted, and `photo_media_id` is set to NULL
  on the owning entity

#### Scenario: Bulk delete of an owner with no media succeeds

- **WHEN** bulk delete targets an owner with no media assets
- **THEN** the operation completes without error and no storage object is
  touched

### Requirement: Photo upload SHALL garbage-collect the previous active photo

The academic-ops-service SHALL garbage-collect the previous active photo when a new photo is uploaded for an owner that already has an active photo, by deleting the previous active object from storage within the same transaction that activates the new one. This applies to student, teacher, and family owner types.

#### Scenario: Replacing a student photo removes the old object

- **WHEN** a student with an existing active photo uploads a new one
- **THEN** the previous photo object is deleted and the new object becomes
  active

### Requirement: Unenrollment SHALL emit `student.unenrolled`

On successful unenrollment the service MUST emit `student.unenrolled` with
payload `{ tenant_id, student_id, homeroom_id, academic_year_id }` within
the same database transaction as the enrollment status update. The event
MUST only be emitted when the unenroll operation actually affects a row
(i.e., an active enrollment existed).

#### Scenario: Unenrollment publishes the event

- **WHEN** a student is unenrolled from a homeroom via `DELETE /enrollments/{id}`
- **THEN** a `student.unenrolled` event is published to RabbitMQ with payload `{ tenant_id, student_id, homeroom_id, academic_year_id }`

#### Scenario: Unenroll of non-existent enrollment does not emit event

- **WHEN** an unenroll request targets an enrollment_id that does not exist or is already inactive
- **THEN** no event is emitted and the response is HTTP 404 `NOT_FOUND`

