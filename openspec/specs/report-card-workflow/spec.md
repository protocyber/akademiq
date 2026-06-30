# report-card-workflow Specification

## Purpose

Defines report-card draft generation, approval, publication, parent/student
visibility, archival, and publication events in the grading service, scoped to
academic-year report types.
## Requirements
### Requirement: The service SHALL define report types scoped to an academic year

The grading service MUST let a tenant admin manage `report_type` rows under
`/api/v1/grading/report-types`, each scoped to one `academic_year_id` and
carrying a `code` (e.g. "Rapor UTS", used as the grade-entry column title) and a
`name` (e.g. "Rapor Tengah Semester"). A report type MUST be unique per
`(academic_year_id, code)`. Every report card MUST belong to exactly one report
type; a card is unique per `(report_type_id, student_id)`. Report types are NOT
scoped to a homeroom.

#### Scenario: Admin creates report types for a year

- **WHEN** a tenant admin POSTs two report types with different codes for the same academic year
- **THEN** both are created and listed for that year, available to every homeroom in the year

#### Scenario: Cards are unique per report type and student

- **WHEN** draft generation runs for a report type and homeroom with N actively-enrolled students
- **THEN** exactly N cards exist for that `(report_type, homeroom)`, one per student, independent of any other report type's cards for the same students

### Requirement: The service SHALL store per-report-type per-evaluation weighting summing to 100% per subject

For each `(report_type, evaluation)` the service MUST store a `weight` percent.
Because an evaluation is scoped to `(homeroom, subject, year, term)`, a weight is
inherently homeroom-scoped. Weights for a given subject MUST be set under the
homeroom-scoped path `PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`.
The same evaluation MAY contribute to several report types with different weights.
A subject's formula within a report type is **valid only when its evaluation
weights sum to exactly 100**; otherwise the subject is treated as not-configured.

#### Scenario: class_scope homeroom_teacher uses the designation projection

- **WHEN** a user holding the `homeroom_teacher` role is designated as walikelas of homeroom X via the `homeroom_teacher_authz` projection
- **THEN** `class_scope().homeroom_teacher` returns `true` for that user and homeroom, allowing HomeroomReview → HomeroomApprove transition

#### Scenario: Undesignated teacher cannot perform homeroom approval

- **WHEN** a user holding the `homeroom_teacher` role has a subject teaching assignment in homeroom X but is NOT the designated walikelas
- **THEN** `class_scope().homeroom_teacher` returns `false` and the HomeroomApprove transition is rejected with HTTP 403

### Requirement: The service SHALL maintain live per-subject report scores recomputed on grade save

The service MUST maintain `subject_report_score` keyed by
`(report_type_id, subject_id, student_id)`. Whenever a grade is saved, for every
report type whose `(report_type, subject)` formula is valid (sums to 100) and
includes the saved evaluation, the service MUST recompute that student's score as
`Σ score(evaluation) × weight / 100`, treating a **missing evaluation score as
0**, and upsert the result. A subject whose formula is not valid MUST have no
live score (reported as blank).

#### Scenario: Saving a grade updates affected live scores

- **WHEN** a grade is saved for an evaluation that participates in two report types with valid formulas
- **THEN** the student's `subject_report_score` is recomputed and upserted for both report types

#### Scenario: Incomplete formula yields no live score

- **WHEN** a subject's formula for a report type does not sum to 100
- **THEN** no `subject_report_score` row is produced for that `(report_type, subject)` and the grade-entry column shows blank

### Requirement: The service SHALL generate report-card drafts by aggregating grades under a grading policy

The grading service MUST provide `POST /report-cards/generate` accepting
`{ report_type_id, homeroom_id }` that, for each actively-enrolled student in the
homeroom, creates one **empty** `report_card` in `Draft` if absent and then, for
cards still in `Draft`, **freezes** a snapshot: it copies the current live
`subject_report_score` rows for that `(report_type, student)` into
`report_subject_score` (`computed_at` stamped), snapshots the report type's valid
weights into `report_card.weights_snapshot`, and derives `summary` pass/fail from
the frozen scores versus the year's `minimum_passing_score`. Generation MUST be
idempotent per `(report_type_id, student_id)` and MUST refresh only cards still
in `Draft`. Editing grades after generation MUST NOT change a card's frozen
scores until generation is re-run.

#### Scenario: Generation creates one frozen draft per enrolled student

- **WHEN** an admin or homeroom teacher POSTs `/report-cards/generate` with a `report_type_id` and `homeroom_id` for a homeroom with N actively-enrolled students
- **THEN** N report cards exist for that `(report_type, homeroom)`, each in status `Draft`, each with frozen `report_subject_score` rows copied from the live scores and a `weights_snapshot`

#### Scenario: Re-generation refreshes only Draft cards

- **WHEN** generation is run again where some cards are still `Draft` and others have advanced past `Draft`
- **THEN** the `Draft` cards are re-frozen from current live scores and the advanced cards are left unchanged and reported as already in workflow

#### Scenario: Edited grades do not change a frozen card

- **WHEN** grades change after a card was generated and the card is not re-generated
- **THEN** the card keeps its frozen `report_subject_score` and `weights_snapshot`, while the live `subject_report_score` reflects the new grades

### Requirement: Report cards SHALL follow the role-gated approval state machine

The service MUST enforce the lifecycle
`Draft -> HomeroomReview -> PrincipalApproval -> Published -> Archived` with the
documented role gates, **per report card**. The workflow is unchanged by report
types; cards are simply filtered by `report_type_id` (and homeroom) when listed.
Each transition is a dedicated endpoint with one source state, one target state,
and a required role. Illegal transitions MUST be rejected and every transition
MUST append a `report_approval` audit row.

#### Scenario: Full approval path to publication

- **WHEN** a teacher submits a Draft card, the homeroom teacher approves it, and the principal approves it
- **THEN** the card moves Draft -> HomeroomReview -> PrincipalApproval -> Published, each step records an approval row, and on publication a `report_card.approved` event is emitted

#### Scenario: Homeroom teacher returns a card for correction

- **WHEN** a homeroom teacher returns a card in HomeroomReview
- **THEN** the card returns to `Draft` and an approval row records the return

#### Scenario: Principal rejects a card

- **WHEN** a principal rejects a card in PrincipalApproval
- **THEN** the card returns to `HomeroomReview` and an approval row records the rejection

#### Scenario: Wrong role is rejected

- **WHEN** a user whose role is not permitted for a transition attempts it (e.g. a subject teacher tries to principal-approve)
- **THEN** the response is HTTP 403 `WRONG_APPROVER_ROLE` and the status is unchanged

#### Scenario: Illegal transition is rejected

- **WHEN** a transition is attempted from a state it is not valid for (e.g. principal-approve on a Draft card)
- **THEN** the response is HTTP 409 `INVALID_STATE_TRANSITION` and the status is unchanged

#### Scenario: Workflow runs per card within a report type

- **WHEN** cards in a report type are at different stages
- **THEN** each card transitions independently under its role gates, exactly as before, and the board shows each card under its own status tab

#### Scenario: Board lists cards scoped to a report type and homeroom

- **WHEN** a client GETs `/report-cards?report_type_id&homeroom_id`
- **THEN** only that report type's cards for that homeroom are returned, grouped by status

### Requirement: Published report cards SHALL be visible to the student and parent; in-progress cards SHALL NOT

The service MUST expose `GET /students/{id}/report-card?academic_year_id=` that
returns a report card to the student and their parent only when its status is
`Published` or `Archived`. A pre-publish card MUST NOT be revealed to
student/parent callers.

#### Scenario: Parent sees a published card

- **WHEN** a parent GETs their child's report card for a year whose card is `Published`
- **THEN** the response is HTTP 200 with the published report card (read-only)

#### Scenario: Parent cannot see an in-progress card

- **WHEN** a parent GETs their child's report card for a year whose card is still in `Draft`, `HomeroomReview`, or `PrincipalApproval`
- **THEN** the response is HTTP 404 (existence not revealed)

### Requirement: Closing an academic year SHALL archive its published report cards

The service MUST consume the academic-year `Closed`/`Archived` signal and
transition that year's `Published` report cards to `Archived` (read-only),
without affecting cards still in the workflow.

#### Scenario: Year close archives published cards

- **WHEN** an academic year transitions to `Closed`
- **THEN** every `Published` report card for that year becomes `Archived` and is read-only, and cards not yet `Published` are left unchanged

### Requirement: The service SHALL emit `report_card.approved` on publication

On principal approval the service MUST emit `report_card.approved` consistent
with `docs/internal/11_integration_contracts/events/report-card-approved.md`.

#### Scenario: Publication emits the event

- **WHEN** a principal approves a report card and it becomes `Published`
- **THEN** a `report_card.approved` event carrying `{ tenant_id, student_id, academic_year_id, report_card_id }` is published to RabbitMQ

### Requirement: Formula weight writes SHALL require evaluation-management permission and assignment scope

The service MUST authorize concrete formula weight writes under
`PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`
the same way it authorizes evaluation CRUD. A write is allowed only when **both**
hold:

1. The caller holds the `grade.evaluation.manage` permission; otherwise the
   response is HTTP 403 `FORBIDDEN`.
2. The caller is a `tenant_admin`, **or** the caller is the teacher assigned to
   that `(subject, homeroom, academic_year)` via a teaching assignment; otherwise
   the response is HTTP 403 `NOT_ASSIGNED`.

A valid tenant token plus grading feature entitlement alone MUST NOT be
sufficient to change weights, because weights determine final report-card scores.

#### Scenario: Caller without grade.evaluation.manage is rejected

- **WHEN** a caller whose permissions do not include `grade.evaluation.manage` PUTs weights to the homeroom-scoped formula path
- **THEN** the response is HTTP 403 `FORBIDDEN` and no weights are changed

#### Scenario: Unassigned teacher is rejected

- **WHEN** a `teacher` who holds `grade.evaluation.manage` but is not assigned to the path's `(subject, homeroom, academic_year)` scope PUTs weights
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no weights are changed

#### Scenario: Assigned teacher succeeds

- **WHEN** a `teacher` who holds `grade.evaluation.manage` and is assigned to the path's `(subject, homeroom, academic_year)` scope PUTs valid weights (summing to 100)
- **THEN** the response is HTTP 204 and the weights are stored

#### Scenario: Tenant admin succeeds

- **WHEN** a `tenant_admin` PUTs valid weights (summing to 100) to the homeroom-scoped formula path
- **THEN** the response is HTTP 204 and the weights are stored

