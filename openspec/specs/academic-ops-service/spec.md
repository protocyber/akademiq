## ADDED Requirements

### Requirement: Academic Ops service SHALL manage students, teachers, homerooms, enrollment, and teaching assignments under `/api/v1/academic-ops`

The service MUST provide tenant-scoped CRUD for students and teachers,
homeroom creation and roster listing, enrollment, and teaching assignment,
under `/api/v1/academic-ops`, following the standard API envelopes. All
resources MUST be scoped to the tenant from the JWT.

#### Scenario: Student is created with a tenant-unique NIS

- **WHEN** a tenant admin POSTs `{ nis, full_name, gender, birth_date }` to `/students`
- **THEN** the response is HTTP 201 with the new student, and a second POST with the same `nis` for that tenant returns HTTP 409 `DUPLICATE_NIS`

#### Scenario: Homeroom roster lists actively enrolled students

- **WHEN** a tenant admin GETs `/homerooms/{id}/students`
- **THEN** the response lists exactly the students whose enrollment in that homeroom for its academic year has status `active`

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

### Requirement: Enrollment SHALL emit `student.enrolled`

On successful enrollment the service MUST emit `student.enrolled` consistent
with the existing contract under
`docs/internal/11_integration_contracts/events/student-enrolled.md`.

#### Scenario: Enrollment publishes the event

- **WHEN** a student is enrolled into a homeroom for an academic year
- **THEN** a `student.enrolled` event is published to RabbitMQ with the documented payload
