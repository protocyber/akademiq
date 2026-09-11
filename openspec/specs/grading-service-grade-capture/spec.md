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

### Requirement: Grade entry SHALL be rejected when the academic year is not `Active`

The service MUST reject recording a new grade (`POST /grades`) when the
evaluation's `academic_year_id` resolves, via the local `valid_year`
projection, to a status other than `Active`. Existing grades remain readable
and updatable only as permitted by report-card status; this guard specifically
blocks new grade capture for years in `Draft`, `Closed`, or `Archived`.

#### Scenario: Grade entry on a Closed year is rejected

- **WHEN** a teacher POSTs a grade for an evaluation whose year's `valid_year.status` is `Closed`
- **THEN** the response is HTTP 409 with code `YEAR_NOT_ACTIVE` and no grade is stored

#### Scenario: Grade entry on an Active year succeeds

- **WHEN** a teacher POSTs a grade for an evaluation whose year's `valid_year.status` is `Active`
- **THEN** the response is HTTP 201 (or 200 on upsert) with the stored grade

### Requirement: Published report cards SHALL be archived only on transition to `Archived`

The service MUST archive published report cards for a year (transition them to
`Archived` status) only when consuming an `academic_year.status_changed` event
whose `status` is `Archived`. The service MUST NOT archive report cards on
`Closed` or any other non-`Archived` status. Archived report cards remain
readable for historical reporting.

#### Scenario: Report cards are not archived when year becomes Closed

- **WHEN** the service consumes an `academic_year.status_changed` event with `status: "Closed"`
- **THEN** no report cards for that year change status and `Published` cards remain `Published`

#### Scenario: Report cards are archived when year becomes Archived

- **WHEN** the service consumes an `academic_year.status_changed` event with `status: "Archived"`
- **THEN** all `Published` report cards for that year are transitioned to `Archived`

### Requirement: Evaluations SHALL be scoped to a term

An evaluation MUST reference both an `academic_year_id` and a `term_id` (NOT
NULL). The evaluation code MUST be unique within
`(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)`.
Creating or editing an evaluation MUST be rejected when the referenced term's
status is not `Draft` or `Active` (validated against the local `valid_term`
projection).

#### Scenario: Create evaluation in an active term

- **WHEN** a teacher POSTs an evaluation referencing a term whose status is
  `Active`
- **THEN** the response is HTTP 201 and the evaluation is stored with that
  `term_id`

#### Scenario: Create evaluation in a closed term is rejected

- **WHEN** a teacher POSTs an evaluation referencing a term whose status is
  `Closed`
- **THEN** the response is HTTP 409 `{ "error": { "code": "TERM_NOT_EDITABLE" } }`

#### Scenario: Evaluation code can repeat across terms in the same year

- **WHEN** a teacher creates an evaluation with `code: "UH1"` in Semester 1 and
  another with `code: "UH1"` in Semester 2 of the same
  `(tenant, homeroom, subject, year)`
- **THEN** both creations succeed because the `term_id` differs

### Requirement: Report types SHALL be strictly term-scoped

A report type MUST reference both an `academic_year_id` and a `term_id` (NOT
NULL). The report type code MUST be unique within
`(academic_year_id, term_id, code)`. A report type belongs to exactly one term;
annual report aggregation across multiple terms is not supported by this
requirement.

#### Scenario: Create report type for a term

- **WHEN** a tenant admin POSTs a report type referencing a term
- **THEN** the response is HTTP 201 and the report type is stored with that
  `term_id`

#### Scenario: Report type code can repeat across terms in the same year

- **WHEN** a tenant admin creates report types with `code: "Rapor"` in Semester 1
  and Semester 2 of the same year
- **THEN** both creations succeed because the `term_id` differs

### Requirement: Report formulas SHALL only reference same-term evaluations

Adding a `report_formula` row MUST be rejected when the evaluation's `term_id`
differs from the report type's `term_id`. Validating the term match MUST happen
in the application layer (there is no cross-table physical FK between
`report_type` and `evaluation` term references).

#### Scenario: Cross-term formula is rejected

- **WHEN** a tenant admin adds a formula linking a Semester-1 report type to a
  Semester-2 evaluation
- **THEN** the response is HTTP 409
  `{ "error": { "code": "EVALUATION_TERM_MISMATCH" } }`

### Requirement: Grade entry SHALL be gated on an active term

Recording a grade MUST be rejected when the referenced term's status (resolved
via the evaluation's `term_id` and the `valid_term` projection) is not `Active`.
This gate is in addition to the existing gate that requires the academic year to
be `Active`.

#### Scenario: Grade entry in an active term succeeds

- **WHEN** a teacher records a grade for an evaluation whose term and year are
  both `Active`
- **THEN** the response is HTTP 201 and the grade is stored

#### Scenario: Grade entry in a draft term is rejected

- **WHEN** a teacher records a grade for an evaluation whose term is `Draft`
  (even if the year is `Active`)
- **THEN** the response is HTTP 409 `{ "error": { "code": "TERM_NOT_ACTIVE" } }`

### Requirement: Grading SHALL maintain a valid_term projection

The service MUST consume `academic_term.created` and
`academic_term.status_changed` events and upsert a local `valid_term`
projection (mirroring `valid_year`) holding at least `term_id`, `tenant_id`,
`academic_year_id`, and `status`. The projection MUST be idempotent on event
redelivery.

#### Scenario: Projection reflects a status change

- **WHEN** an `academic_term.status_changed` event arrives
- **THEN** the `valid_term` row for that `term_id` is upserted with the new
  status and a second delivery of the same event does not duplicate or corrupt
  the row

### Requirement: Grading gates SHALL use clear, documented error codes

The service MUST return the following HTTP 409 error codes for the term-related
gates: `TERM_NOT_EDITABLE` (create/edit evaluation when the term is not
`Draft`/`Active`), `TERM_NOT_ACTIVE` (record grade when the term is not
`Active`), and `EVALUATION_TERM_MISMATCH` (report formula cross-term).

#### Scenario: Each gate returns its documented code

- **WHEN** each of the three term-related gate failures occurs (evaluation edit
  on a closed term, grade entry on a non-active term, cross-term formula add)
- **THEN** the service responds with HTTP 409 and the matching error code
  (`TERM_NOT_EDITABLE`, `TERM_NOT_ACTIVE`, or `EVALUATION_TERM_MISMATCH`)

### Requirement: Grading SHALL resolve `term_id` only from the `valid_term` projection

Grading writes (create/update evaluation, create report type, record grade) MUST
resolve and validate `term_id` from the local `valid_term` projection. When the
client omits `term_id`, grading MUST select a real projected term for the scope
(the year's default term per the agreed tie-break) instead of deriving
`md5(academic_year_id)` or generating a new UUID. When no projected term exists
for the scope, the request MUST be rejected with a domain error rather than
proceed against a fabricated id.

#### Scenario: Omitted term id resolves to a real projected term

- **WHEN** a client creates an evaluation for a year without sending `term_id`
  and that year has exactly one projected term
- **THEN** the evaluation is stored with that real `term_id`

#### Scenario: Write with a real active term id is accepted

- **WHEN** a client creates an evaluation referencing the real `term_id` of an
  Active term that exists in `valid_term`
- **THEN** the response is HTTP 201 and the evaluation is stored with that
  `term_id`

#### Scenario: No projected term yields a domain error, not a fabricated id

- **WHEN** a grading write targets a scope that has no row in `valid_term`
- **THEN** the service returns a domain error and MUST NOT synthesize a
  `term_id`

