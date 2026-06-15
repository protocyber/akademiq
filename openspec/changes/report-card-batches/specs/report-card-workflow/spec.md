## ADDED Requirements

### Requirement: The service SHALL group report cards into named batches per homeroom and year

The service MUST let a tenant admin create multiple report batches per
`(homeroom_id, academic_year_id)` under `/api/v1/grading/report-batches`, each
with a `name` (e.g. "Rapor Tengah Semester", "Rapor Akhir"). Every report card
MUST belong to exactly one batch; a card is unique per `(batch_id, student_id)`.

#### Scenario: Admin creates multiple batches for one class and year

- **WHEN** a tenant admin POSTs two batches with different names for the same homeroom and year
- **THEN** both are created and listed for that homeroom+year, each able to hold its own set of cards

#### Scenario: Cards are unique per batch and student

- **WHEN** generation runs for a batch with N enrolled students
- **THEN** exactly N cards exist for that batch, one per student, independent of any other batch's cards for the same students

### Requirement: The service SHALL store per-subject weighting formulas scoped to a batch

For each `(batch, subject)` the service MUST store a `weights` map from
evaluation to percentage, settable via
`PUT /report-batches/{id}/formulas/{subject_id}`. One formula applies to the
whole class. A formula is **valid only when its weights sum to exactly 100**;
otherwise the subject is treated as not-configured.

#### Scenario: Weights summing to exactly 100 are accepted

- **WHEN** a teacher PUTs `{ weights: { UH1: 25, UTS: 75 } }` for a subject in a batch
- **THEN** the formula is stored and the subject counts as configured

#### Scenario: Weights not summing to 100 are not a valid formula

- **WHEN** a teacher PUTs weights that sum to anything other than 100
- **THEN** the response rejects the formula as invalid (HTTP 400 `INVALID_WEIGHTS`) and the subject remains unconfigured

### Requirement: The service SHALL compute frozen per-subject scores from formulas and evaluation grades

`POST /report-batches/{id}/compute` MUST, for every subject whose formula is
valid (sums to 100), compute each enrolled student's final subject score as the
weighted sum of that student's evaluation scores
(`Σ score × weight / 100`), treating a **missing evaluation score as 0**, and
MUST persist the result as a frozen `report_subject_score` row
(`computed_at` stamped). Subjects without a valid formula MUST be skipped and
reported. The response MUST report computed vs skipped subjects. Editing grades
after compute MUST NOT change stored scores until compute is re-run.

#### Scenario: Compute freezes weighted scores for all students

- **WHEN** a subject's formula is valid and compute is run for the batch
- **THEN** every enrolled student gets a frozen `final_score` equal to the weighted sum of their evaluation scores, with missing scores counted as 0

#### Scenario: Subject without a valid formula is skipped

- **WHEN** compute runs and a subject has no formula or weights ≠ 100
- **THEN** that subject is skipped, reported in the response, and no scores are written for it

#### Scenario: Re-running compute overwrites the snapshot

- **WHEN** grades change and compute is run again
- **THEN** the affected `report_subject_score` rows are overwritten with new values and `computed_at`, and a card not re-computed keeps its prior frozen scores

## MODIFIED Requirements

### Requirement: The service SHALL generate report-card drafts by aggregating grades under a grading policy

The grading service MUST provide `POST /report-cards/generate` accepting
`{ batch_id }` that, for each actively-enrolled student in the batch's homeroom
and year, creates one **empty** `report_card` in `Draft` (no scores). Per-subject
scores are filled separately by batch compute, not at generation. Generation
MUST be idempotent per `(batch_id, student_id)` and MUST refresh only cards still
in `Draft`.

#### Scenario: Generation creates one empty draft per enrolled student

- **WHEN** an admin or homeroom teacher POSTs `/report-cards/generate` with a `batch_id` for a homeroom with N actively-enrolled students
- **THEN** N report cards exist for that batch, each in status `Draft`, each with no computed subject scores yet

#### Scenario: Re-generation refreshes only Draft cards

- **WHEN** generation runs again for a batch where some cards are still `Draft` and others have advanced past `Draft`
- **THEN** the `Draft` cards are refreshed and the advanced cards are left unchanged and reported as already in workflow

#### Scenario: A card summary reflects frozen compute, not raw grade averages

- **WHEN** a card's summary is read after compute
- **THEN** it is derived from the frozen `report_subject_score` rows (per-subject final scores and pass/fail vs the year's `minimum_passing_score`), not from a flat average of single grades

### Requirement: Report cards SHALL follow the role-gated approval state machine

The service MUST enforce the lifecycle
`Draft -> HomeroomReview -> PrincipalApproval -> Published -> Archived` with the
documented role gates, **per report card**. The workflow is unchanged by
batching; cards are simply filtered by `batch_id` when listed. Each transition
is a dedicated endpoint with one source state, one target state, and a required
role; illegal transitions MUST be rejected and every transition MUST append a
`report_approval` audit row.

#### Scenario: Workflow runs per card within a batch

- **WHEN** cards in a batch are at different stages
- **THEN** each card transitions independently under its role gates, exactly as before batching, and the board for that batch shows each card in its own column

#### Scenario: Board lists cards scoped to a batch

- **WHEN** a client GETs `/report-cards?batch_id`
- **THEN** only that batch's cards are returned, grouped by status
