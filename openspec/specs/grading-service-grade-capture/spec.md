# grading-service-grade-capture Specification

## Purpose

Defines the Grading Service grade capture contract for evaluation management, grade recording, score queries, and authorization (teaching assignment + enrollment verification).
## Requirements
### Requirement: The grading service SHALL manage evaluations scoped per homeroom, subject, and year

The service MUST provide evaluation CRUD under `/api/v1/grading/evaluations`,
tenant-scoped from the JWT. An evaluation captures
`{ homeroom_id, subject_id, academic_year_id, term_id, code, name, position }` and
defines one assessment column (e.g. "UH1", "UTS") for that class+subject+year+term.
Two different homerooms teaching the same subject MUST be able to define
different evaluation lists. `code` MUST be unique per
`(tenant_id, homeroom_id, subject_id, academic_year_id, term_id)`.

Concrete evaluations MAY be created either manually by an assigned teacher (or
tenant admin) or by materialization from a per-term evaluation template. A
template acts as a seed only: after materialization, assigned teachers MAY add
or delete concrete evaluations for their `(homeroom, subject, year, term)`
without any constraint imposed by the template.

Evaluation writes (create, update, delete) MUST require the
`grade.evaluation.manage` permission as the primary authority gate. In addition,
a caller who is not a tenant admin MUST also be assigned to the evaluation's
subject+homeroom+year. A caller lacking `grade.evaluation.manage` MUST receive
HTTP 403 `FORBIDDEN`; an authorized non-admin caller who is not assigned to the
scope MUST receive HTTP 403 `NOT_ASSIGNED`.

#### Scenario: Teacher defines an evaluation column for a class+subject

- **WHEN** an assigned teacher holding `grade.evaluation.manage` POSTs `{ homeroom_id, subject_id, academic_year_id, term_id, code: "UH1", name: "Ulangan Harian 1", position: 1 }` to `/evaluations`
- **THEN** the response is HTTP 201 with the stored evaluation

#### Scenario: Caller without grade.evaluation.manage is rejected

- **WHEN** a caller who does not hold `grade.evaluation.manage` POSTs, PATCHes, or DELETEs an evaluation
- **THEN** the response is HTTP 403 `FORBIDDEN` and nothing changes

#### Scenario: Duplicate code in the same class+subject+year+term is rejected

- **WHEN** a teacher POSTs an evaluation whose `code` already exists for that `(homeroom, subject, year, term)`
- **THEN** the response is HTTP 409 `DUPLICATE_EVALUATION_CODE` and no evaluation is created

#### Scenario: Evaluations are listed for a class+subject+year in column order

- **WHEN** a client GETs `/evaluations?homeroom_id&subject_id&academic_year_id`
- **THEN** the response lists that scope's evaluations ordered by `position`

#### Scenario: Deleting an evaluation removes its grades

- **WHEN** a teacher DELETEs an evaluation that has recorded grades
- **THEN** the evaluation and all grades referencing it are removed, and a subsequent grid read no longer returns that column

#### Scenario: Unassigned teacher cannot manage evaluations

- **WHEN** a non-admin teacher who holds `grade.evaluation.manage` but is not assigned to that subject+homeroom+year POSTs, PATCHes, or DELETEs an evaluation
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and nothing changes

#### Scenario: Teacher overrides a materialized evaluation list

- **WHEN** evaluations were materialized from a term template and an assigned teacher then deletes one and adds another
- **THEN** both changes succeed and the template is unaffected

### Requirement: The grading service SHALL let assigned teachers record and update grades under `/api/v1/grading`

The service MUST provide `POST /grades` and grade queries under
`/api/v1/grading`, all tenant-scoped from the JWT. A grade MUST capture
`{ student_id, evaluation_id, score }` with the recording teacher taken from the
JWT subject. The subject, homeroom, and year are derived from the evaluation,
not sent by the client.

#### Scenario: Assigned teacher records a grade for an evaluation

- **WHEN** a teacher assigned to the evaluation's subject in the student's homeroom for the year POSTs `{ student_id, evaluation_id, score }` for an actively-enrolled student
- **THEN** the response is HTTP 201 (or 200 on upsert) with the stored grade

#### Scenario: Score is bounded

- **WHEN** a teacher POSTs a grade with a `score` outside 0–100
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` with a `score` field error

#### Scenario: Grade grid lists every evaluation's scores for the class+subject

- **WHEN** a client GETs `/grades?homeroom_id&subject_id&academic_year_id`
- **THEN** the response returns the grades for that scope keyed so the client can index by `(student_id, evaluation_id)` across all of the scope's evaluation columns

### Requirement: A grade SHALL be unique per student and evaluation (idempotent upsert)

The service MUST store at most one grade per `(tenant_id, student_id,
evaluation_id)`. Recording a grade for an existing combination MUST update the
score rather than create a duplicate.

#### Scenario: Re-recording updates instead of duplicating

- **WHEN** a teacher POSTs a grade for a `(student, evaluation)` that already has a grade
- **THEN** the existing grade's score is updated and no second row is created

### Requirement: Grade recording SHALL be authorized by teaching assignment and enrollment

The service MUST allow a grade write only when the recording teacher is assigned
to the evaluation's subject in the student's homeroom for the year AND the
student is actively enrolled there. The subject/homeroom/year used for this
check MUST come from the referenced evaluation. The student-active-enrollment
check MUST read the grading service's own `enrolled_student` projection, and the
grade-entry roster surfaced to teachers MUST be sourced from that same
projection, so that the students shown are exactly the students for whom a grade
may be recorded.

#### Scenario: Unassigned teacher is rejected

- **WHEN** a teacher records a grade for an evaluation whose subject or class they are not assigned to
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no grade is stored

#### Scenario: Grade for a non-enrolled student is rejected

- **WHEN** a teacher records a grade for a student who is not actively enrolled in the evaluation's homeroom for the year
- **THEN** the response is HTTP 422 `STUDENT_NOT_ENROLLED`

#### Scenario: Teacher account not linked to a profile

- **WHEN** the recording user's account is not linked to any teacher profile referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ACCOUNT_NOT_LINKED`

#### Scenario: A student shown in the entry roster is always submittable

- **WHEN** a student appears in the grade-entry roster for a homeroom+year and the assigned teacher submits a grade for them
- **THEN** the grade is accepted, because the roster and the write check read the same projection

### Requirement: The grading service SHALL serve a roster from its own enrollment projection

The service MUST provide `GET /api/v1/grading/homerooms/{homeroom_id}/roster?academic_year_id=`,
tenant-scoped, returning the actively-enrolled students for that homeroom+year
from the `enrolled_student` projection — the same table the grade-write
authorization check reads. Each row MUST include `student_id`, `full_name`, and
`nis` (denormalized into the projection from enrollment/profile events) so the
roster is display-ready without a cross-service call. The endpoint MUST require
`grade.read`. The set of students it returns MUST equal exactly the set for
which a grade can be recorded for that scope.

#### Scenario: Roster returns active students for a class+year

- **WHEN** a client GETs the roster for a homeroom and academic year
- **THEN** the response lists the actively-enrolled students with their `student_id`, `full_name`, and `nis`, tenant-scoped

#### Scenario: Roster and write check share one source

- **WHEN** a student is present in the roster response for a scope
- **THEN** a grade submitted for that student in that scope passes the enrollment check (no `STUDENT_NOT_ENROLLED`)

#### Scenario: Roster read without grade.read is forbidden

- **WHEN** a caller without `grade.read` GETs the roster endpoint
- **THEN** the response is HTTP 403

### Requirement: The enrolled_student projection SHALL carry display fields

The `enrolled_student` projection MUST store `full_name` and `nis` alongside the
enrollment tuple, populated when a `student.enrolled` event is applied and
updated when a student's profile fields change (via the corresponding profile
event). This makes the projection self-sufficient for roster display so the
grade-entry UI does not depend on a cross-service roster read.

#### Scenario: Enrollment event populates display fields

- **WHEN** a `student.enrolled` event carrying `full_name` and `nis` is applied to the projection
- **THEN** the `enrolled_student` row stores those values and the roster endpoint returns them

#### Scenario: Profile update refreshes the projected name

- **WHEN** a student's `full_name` changes and the profile-update event is applied
- **THEN** the `enrolled_student` row's `full_name` is updated and subsequent roster reads return the new name

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

### Requirement: Grading read endpoints SHALL require grade.read or report.read

The grading GET endpoints SHALL enforce read permissions:

- Grade/evaluation reads — `GET /evaluations`, `GET /class-grades`, `GET /students/{id}/grades`,
  `GET /report-formulas`, `GET /subject-report-scores` — MUST require `grade.read`.
- Report-card reads — `GET /report-types`, `GET /report-cards`, `GET /report-cards/{id}` — MUST
  require `report.read`.
- The published-card portal endpoints (`GET /me/report-cards[/{student_id}]`) MUST require
  `report.read` AND pass the ownership verification defined by `secure-published-report-card`.

Callers without the required permission MUST receive HTTP 403 with code `FORBIDDEN`.

#### Scenario: Reading class grades without grade.read

- **WHEN** a caller without `grade.read` calls `GET /class-grades`
- **THEN** the response is HTTP 403

#### Scenario: A teacher reads report types

- **WHEN** a `teacher` holding `report.read` calls `GET /report-types`
- **THEN** the response is HTTP 200

### Requirement: Grading service SHALL handle `student.unenrolled` event

The grading service MUST subscribe to `student.unenrolled` events from the
academic-ops event bus. Upon receiving the event, the service MUST update the
corresponding `enrolled_student` projection row, setting `status` to
`'inactive'`. If no matching row exists, the event MUST be acknowledged
without error (idempotent).

#### Scenario: Unenroll event deactivates projection

- **WHEN** the grading service receives a `student.unenrolled` event for a student with an `active` `enrolled_student` row
- **THEN** the `enrolled_student` row is updated to `status='inactive'` and the event is acknowledged

#### Scenario: Unenroll event for non-projected student is ignored

- **WHEN** the grading service receives a `student.unenrolled` event for a student that has no `enrolled_student` row
- **THEN** the event is acknowledged without error and a warning is logged

#### Scenario: Duplicate unenroll event is idempotent

- **WHEN** the grading service receives a `student.unenrolled` event for a student whose `enrolled_student` row is already `status='inactive'`
- **THEN** the row remains unchanged and the event is acknowledged

