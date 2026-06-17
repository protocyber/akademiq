# grading-service-grade-capture Specification

## Purpose

Defines the Grading Service grade capture contract for evaluation management, grade recording, score queries, and authorization (teaching assignment + enrollment verification).
## Requirements
### Requirement: The grading service SHALL manage evaluations scoped per homeroom, subject, and year

The service MUST provide evaluation CRUD under `/api/v1/grading/evaluations`,
tenant-scoped from the JWT. An evaluation captures
`{ homeroom_id, subject_id, academic_year_id, code, name, position }` and
defines one assessment column (e.g. "UH1", "UTS") for that class+subject+year.
Two different homerooms teaching the same subject MUST be able to define
different evaluation lists. `code` MUST be unique per
`(tenant_id, homeroom_id, subject_id, academic_year_id)`.

Evaluation writes MUST require the same authorization as recording a grade for
that subject+homeroom+year (assigned teacher or tenant admin).

#### Scenario: Teacher defines an evaluation column for a class+subject

- **WHEN** an assigned teacher POSTs `{ homeroom_id, subject_id, academic_year_id, code: "UH1", name: "Ulangan Harian 1", position: 1 }` to `/evaluations`
- **THEN** the response is HTTP 201 with the stored evaluation

#### Scenario: Duplicate code in the same class+subject+year is rejected

- **WHEN** a teacher POSTs an evaluation whose `code` already exists for that `(homeroom, subject, year)`
- **THEN** the response is HTTP 409 `DUPLICATE_EVALUATION_CODE` and no evaluation is created

#### Scenario: Evaluations are listed for a class+subject+year in column order

- **WHEN** a client GETs `/evaluations?homeroom_id&subject_id&academic_year_id`
- **THEN** the response lists that scope's evaluations ordered by `position`

#### Scenario: Deleting an evaluation removes its grades

- **WHEN** a teacher DELETEs an evaluation that has recorded grades
- **THEN** the evaluation and all grades referencing it are removed, and a subsequent grid read no longer returns that column

#### Scenario: Unassigned teacher cannot manage evaluations

- **WHEN** a teacher who is not assigned to that subject+homeroom+year POSTs, PATCHes, or DELETEs an evaluation
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and nothing changes

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
check MUST come from the referenced evaluation.

#### Scenario: Unassigned teacher is rejected

- **WHEN** a teacher records a grade for an evaluation whose subject or class they are not assigned to
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no grade is stored

#### Scenario: Grade for a non-enrolled student is rejected

- **WHEN** a teacher records a grade for a student who is not actively enrolled in the evaluation's homeroom for the year
- **THEN** the response is HTTP 422 `STUDENT_NOT_ENROLLED`

#### Scenario: Teacher account not linked to a profile

- **WHEN** the recording user's account is not linked to any teacher profile referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ACCOUNT_NOT_LINKED`

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

