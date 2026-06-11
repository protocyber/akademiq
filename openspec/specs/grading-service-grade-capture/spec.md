## ADDED Requirements

### Requirement: The grading service SHALL let assigned teachers record and update grades under `/api/v1/grading`

The service MUST provide `POST /grades`, `PATCH /grades/{id}`, and grade
queries under `/api/v1/grading`, all tenant-scoped from the JWT. A grade MUST
capture `{ student_id, subject_id, academic_year_id, score }` with the
recording teacher taken from the JWT subject.

#### Scenario: Assigned teacher records a grade

- **WHEN** a teacher who is assigned to teach a subject in a homeroom POSTs a grade for an actively-enrolled student in that homeroom for the year
- **THEN** the response is HTTP 201 with the stored grade

#### Scenario: Score is bounded

- **WHEN** a teacher POSTs a grade with a `score` outside the allowed range
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` with a `score` field error

### Requirement: Grade recording SHALL be authorized by teaching assignment and enrollment

The service MUST consume `teacher.assigned` and `student.enrolled` into local
projections and MUST allow a grade write only when the recording teacher is
assigned to that subject in the student's homeroom for the year AND the student
is actively enrolled there.

#### Scenario: Unassigned teacher is rejected

- **WHEN** a teacher records a grade for a subject or class they are not assigned to
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no grade is stored

#### Scenario: Grade for a non-enrolled student is rejected

- **WHEN** a teacher records a grade for a student who is not actively enrolled in the relevant homeroom for the year
- **THEN** the response is HTTP 422 `STUDENT_NOT_ENROLLED`

#### Scenario: Teacher account not linked to a profile

- **WHEN** the recording user's account is not linked to any teacher profile referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ACCOUNT_NOT_LINKED`

### Requirement: A grade SHALL be unique per student, subject, and year (idempotent upsert)

The service MUST store at most one grade per
`(tenant_id, student_id, subject_id, academic_year_id)`. Recording a grade for
an existing combination MUST update the score rather than create a duplicate.

#### Scenario: Re-recording updates instead of duplicating

- **WHEN** a teacher POSTs a grade for a `(student, subject, year)` that already has a grade
- **THEN** the existing grade's score is updated and exactly one grade row exists for that combination

### Requirement: The service SHALL expose a per-student grade query for report-card aggregation

The service MUST provide `GET /students/{id}/grades?academic_year_id=`
returning every subject grade for a student in a year, so the report-card
workflow can aggregate them.

#### Scenario: Student grades are retrievable for a year

- **WHEN** a client GETs `/students/{id}/grades?academic_year_id=...`
- **THEN** the response lists one entry per graded subject with `{ subject_id, score }` for that student and year, tenant-scoped

### Requirement: Grade writes SHALL be gated by feature entitlement and active subscription

The service MUST place grade write endpoints behind the `grading` feature
entitlement and require an active subscription (via the
`subscription.activated` projection).

#### Scenario: Non-entitled tenant cannot record grades

- **WHEN** a tenant whose plan does not entitle `grading` POSTs a grade
- **THEN** the response is HTTP 403 `FEATURE_NOT_AVAILABLE`
