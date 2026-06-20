## MODIFIED Requirements

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

## ADDED Requirements

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
