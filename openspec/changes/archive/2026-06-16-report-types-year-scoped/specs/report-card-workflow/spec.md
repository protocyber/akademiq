# report-card-workflow (delta — report-types-year-scoped)

## ADDED Requirements

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

For each `(report_type, evaluation)` the service MUST store a `weight` percent,
settable under `/report-types/{id}/formulas`. Because an evaluation is scoped to
`(homeroom, subject, year)`, a weight inherits that subject. The same evaluation
MAY contribute to several report types with different weights. A subject's
formula within a report type is **valid only when its evaluation weights sum to
exactly 100**; otherwise the subject is treated as not-configured and rejected.

#### Scenario: Weights summing to exactly 100 are accepted

- **WHEN** a teacher sets `{ UH1: 25, UTS: 75 }` for a subject within a report type
- **THEN** the weights are stored and the subject counts as configured for that report type

#### Scenario: Weights not summing to 100 are rejected

- **WHEN** a teacher sets weights for a `(report_type, subject)` that sum to anything other than 100
- **THEN** the response is HTTP 400 `INVALID_WEIGHTS` and the subject remains unconfigured

#### Scenario: One evaluation contributes to multiple report types

- **WHEN** evaluation UH1 is given weight 25 in report type A and weight 10 in report type B
- **THEN** both weights are stored independently and each report type computes UH1's contribution with its own weight

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

## MODIFIED Requirements

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

#### Scenario: Board lists cards scoped to a report type and homeroom

- **WHEN** a client GETs `/report-cards?report_type_id&homeroom_id`
- **THEN** only that report type's cards for that homeroom are returned, grouped by status

#### Scenario: Workflow runs per card within a report type

- **WHEN** cards in a report type are at different stages
- **THEN** each card transitions independently under its role gates, exactly as before, and the board shows each card under its own status tab

## REMOVED Requirements

### Requirement: The service SHALL compute frozen per-subject scores from formulas and evaluation grades

**Reason**: The explicit `[Hitung Nilai]` compute step is replaced by live
`subject_report_score` recomputation on grade save plus a snapshot taken at
`[Generate Draft]`. There is no longer a standalone compute action.

**Migration**: Remove `POST /report-batches/{id}/compute` and all
`/report-batches` routes. Per-subject scores are now produced live (see "maintain
live per-subject report scores") and frozen by generation (see the modified
generate requirement).
