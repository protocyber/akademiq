# academic-ops-service Specification

## Purpose

Defines tenant-scoped academic operations for students, teachers, homerooms, enrollment, teaching assignments, spreadsheet import, and academic-ops event publication under `/api/v1/academic-ops`.
## Requirements
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

The academic-ops service SHALL accept photo uploads for students, teachers, and
family profiles through `POST /api/v1/academic-ops/media`, store the bytes via
the shared `common-media` library, and set the owning entity's `photo_url` to the
new `media://` URI. It MUST expose
`GET /api/v1/academic-ops/media/{owner_type}/{media_id}` to serve the stored bytes
with their recorded content type (no DB lookup required — the storage key is
`{owner_type}/{media_id}`). This is a single-active model: replacing a photo
replaces the stored URI, no history is retained.

The response from the upload endpoint SHALL include a resolved HTTP serve path
(not a raw `media://` URI) so the web app can render the photo directly.

#### Scenario: Upload a student photo

- **WHEN** an admin uploads a valid image for a student
- **THEN** `student.photo_url` is set to the new `media://` URI and the previous object is garbage-collected

#### Scenario: Serve a stored photo

- **WHEN** a client requests an existing academic-ops media id with the owner_type path segment
- **THEN** the service responds 200 with the stored content type and the file bytes

#### Scenario: Stored reference is a usable URL

- **WHEN** a photo is uploaded
- **THEN** the response `photo_url` resolves to the `/api/v1/academic-ops/media/{owner_type}/{media_id}` serve path

### Requirement: Photo SHALL support explicit clearing per owner

academic-ops-service SHALL expose
`DELETE /api/v1/academic-ops/media?owner_type=&owner_id=` that deletes the
current storage object and nulls the owning entity's `photo_url`. The operation
is tenant-scoped (resolved from the JWT, never client-supplied) and idempotent:
an owner with no photo completes without error.

#### Scenario: Clearing removes the object and nulls photo_url

- **WHEN** an owner's photo is cleared
- **THEN** the storage object is deleted and `photo_url` is set to NULL on the owning entity

#### Scenario: Clearing an owner with no photo succeeds

- **WHEN** clear targets an owner with no photo
- **THEN** the operation completes without error

### Requirement: Photo upload SHALL garbage-collect the previous active photo

The academic-ops-service SHALL garbage-collect the previous active photo when a new photo is uploaded for an owner that already has one, by deleting the previous object from storage before setting the new `photo_url`. This applies to student, teacher, and family owner types.

#### Scenario: Replacing a student photo removes the old object

- **WHEN** a student with an existing photo uploads a new one
- **THEN** the previous photo object is deleted and `photo_url` points to the new one

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

### Requirement: Academic Ops service SHALL manage students, teachers, homerooms, enrollment, teaching assignments, and family profiles under `/api/v1/academic-ops`

The service MUST provide tenant-scoped CRUD for students, teachers, family profiles,
student-family links, homeroom creation and roster listing, enrollment, and teaching
assignment, under `/api/v1/academic-ops`, following the standard API envelopes. All
resources MUST be scoped to the tenant from the JWT.

Student profiles MUST support complete administrative biodata including NIS, NISN,
NIK, full name, gender, birth date, birth place, address, phone number, photo
reference, religion, nationality, child order, sibling count, entry date, origin
school, status, archive reason, and optional linked IAM user id. Teacher profiles
MUST support NIP, NIK, full name, education level, gender, birth date, birth place,
address, phone number, photo reference, email, employment status, role/position,
start date, end date, primary subject area, NUPTK, certification number, status,
archive reason, and optional linked IAM user id.

Student and teacher profile contact fields MUST be administrative data and MUST NOT
be automatically synchronized with linked IAM user email or phone fields. Student
master data MUST NOT store current class as authoritative state; class placement
MUST remain represented by enrollment records.

List endpoints for students, teachers, family profiles, homerooms, and teaching
assignments MUST accept `search`, `sort`, `page`, and `page_size` query parameters
and MUST return a `{ data, meta: { page, page_size, total } }` envelope. `sort`
MUST be validated against a per-resource whitelist and an unknown value MUST be
rejected with HTTP 400 `INVALID_SORT`. `search` MUST match the resource's name
field and relevant identifiers case-insensitively.

#### Scenario: Student is created with complete biodata and optional placement

- **WHEN** a tenant admin POSTs valid student biodata and optional initial `{ academic_year_id, homeroom_id }` placement data to `/students`
- **THEN** the response is HTTP 201 with the new student profile, and placement is attempted through enrollment rather than stored as a current class field on the student

#### Scenario: Initial placement failure keeps student profile

- **WHEN** student biodata is valid but the optional initial enrollment fails
- **THEN** the student profile remains created and the response or subsequent UI state identifies the student as not yet placed in a class

#### Scenario: Student is created with a tenant-unique NIS

- **WHEN** a tenant admin POSTs student biodata with a `nis` already used by another non-deleted student in the same tenant
- **THEN** the response is HTTP 409 with code `DUPLICATE_NIS`

#### Scenario: Teacher profile can exist without login account

- **WHEN** a tenant admin creates a teacher profile without a linked IAM user id
- **THEN** the profile is stored and no IAM user account is created

#### Scenario: Profile and IAM contact data may differ

- **WHEN** a student, teacher, or family profile is linked to an IAM user
- **THEN** profile email and phone data remain independent from the IAM user's login email and account data

#### Scenario: Homeroom roster lists actively enrolled students

- **WHEN** a tenant admin GETs `/homerooms/{id}/students`
- **THEN** the response lists exactly the students whose enrollment in that homeroom for its academic year has status `active`

#### Scenario: Student list returns a paginated envelope

- **WHEN** a tenant admin GETs `/students?search=budi&sort=-nis&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-ops list endpoint with `sort=` outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

### Requirement: Students, teachers, family profiles, homerooms, and teaching assignments SHALL support archive/soft-delete behavior, and teachers SHALL support edit

The service MUST expose update, archive/nonactive, and soft-delete behavior for
students, teachers, and family profiles, and delete behavior for homerooms and
teaching assignments, all tenant-scoped from the JWT. Soft-deleted records MUST be
hidden from default lists. Restore UI is out of scope for this change.

Student, teacher, and family profile lifecycle state MUST distinguish active use
from archived/nonactive records. Teacher status values MUST include `aktif`,
`nonaktif`, and `arsip`, with archive reasons `nonaktif_sementara`, `resign`,
`mutasi`, `pensiun`, `meninggal`, and `lainnya`. Student status values MUST include
`aktif`, `nonaktif`, and `arsip`, with archive reasons `nonaktif_sementara`,
`lulus`, `pindah`, `keluar`, `meninggal`, and `lainnya`.

Bulk destructive operations MUST be all-or-nothing: they MUST pre-validate every id
and, on the first violation, reject the entire request with no changes.

- Student: destructive delete MUST be rejected with HTTP 409 `STUDENT_ENROLLED` when the student has an `active` enrollment.
- Teacher: updating MUST support the richer teacher profile fields. Destructive delete MUST be rejected with HTTP 409 `TEACHER_ASSIGNED` when a teaching assignment references the teacher. Deleting or archiving a teacher MUST NOT delete any linked login user.
- Homeroom: destructive delete MUST be rejected with HTTP 409 `HOMEROOM_NOT_EMPTY` when it has active enrollments.
- Teaching assignment: delete MUST always succeed for an existing tenant-owned assignment.

#### Scenario: Editing a teacher updates it in place

- **WHEN** a tenant admin PATCHes `/teachers/{id}` with valid profile fields
- **THEN** the response is HTTP 200 with the updated teacher and a subsequent list reflects the new values

#### Scenario: Archiving a teacher records reason

- **WHEN** a tenant admin archives a teacher with reason `resign`
- **THEN** the teacher status becomes `arsip`, the reason is stored, and any linked IAM user remains unchanged

#### Scenario: Archiving a student records academic reason

- **WHEN** a tenant admin archives a student with reason `lulus`
- **THEN** the student status becomes `arsip`, the reason is stored, and enrollment history remains intact

#### Scenario: Deleting an enrolled student is rejected

- **WHEN** a tenant admin destructively deletes a student who has an `active` enrollment
- **THEN** the response is HTTP 409 `STUDENT_ENROLLED` and the student is unchanged

#### Scenario: Deleting an assigned teacher is rejected and the login is untouched

- **WHEN** a tenant admin destructively deletes a teacher referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ASSIGNED`, the teacher is unchanged, and any linked login user is unaffected

#### Scenario: Deleting a non-empty homeroom is rejected

- **WHEN** a tenant admin DELETEs a homeroom that still has active enrollments
- **THEN** the response is HTTP 409 `HOMEROOM_NOT_EMPTY` and the homeroom and its roster are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of student ids where one has an active enrollment
- **THEN** the response rejects the whole request with HTTP 409 `STUDENT_ENROLLED` and none of the students in the set are deleted

### Requirement: Gender validation SHALL accept only male and female

The `validate_student_fields` and `validate_gender` functions in academic-ops-service MUST accept only `"male"` and `"female"`. Any other value (including `"other"`) MUST be rejected with `VALIDATION_ERROR`.

#### Scenario: Student with male or female succeeds

- **WHEN** a student is created/updated with `gender = "male"` or `"female"`
- **THEN** the operation succeeds

#### Scenario: Student with other gender fails

- **WHEN** a student is created/updated with `gender = "other"` (or any
  non-male/female value)
- **THEN** the response is `VALIDATION_ERROR` with field `gender` indicating
  only male/female are accepted

### Requirement: The student table SHALL enforce gender CHECK constraint

The `student` table MUST have a CHECK constraint
`gender IN ('male', 'female')`. The migration MUST fail if any existing row
has a gender value outside this set, directing the operator to remediate
before retrying.

#### Scenario: Migration succeeds when no other-gender rows exist

- **WHEN** the migration runs and no student has `gender = 'other'`
- **THEN** the CHECK constraint is tightened to `IN ('male', 'female')`

#### Scenario: Migration fails when other-gender rows exist

- **WHEN** the migration runs and at least one student has `gender = 'other'`
- **THEN** the migration fails with a clear error message; no data is
  silently changed

### Requirement: The teacher table SHALL enforce gender CHECK constraint

The `teacher` table MUST have a CHECK constraint
`gender IN ('male', 'female')` on the `gender` column (which is nullable).
The constraint MUST allow NULL (gender is optional for teachers) but MUST
reject non-male/female values.

#### Scenario: Teacher with null gender succeeds

- **WHEN** a teacher is created/updated with no gender specified
- **THEN** the operation succeeds (NULL is allowed)

#### Scenario: Teacher with other gender fails

- **WHEN** a teacher is created/updated with `gender = "other"`
- **THEN** the response is `VALIDATION_ERROR`

