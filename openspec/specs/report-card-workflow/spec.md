# report-card-workflow Specification

## Purpose

Defines report-card draft generation, approval, publication, parent/student
visibility, archival, and publication events in the grading service.

## Requirements

### Requirement: The service SHALL generate report-card drafts by aggregating grades under a grading policy

The grading service MUST provide `POST /report-cards/generate` accepting
`{ homeroom_id, academic_year_id }` that, for each actively-enrolled student in
the homeroom, aggregates the student's grades for the year, applies the year's
grading policy to derive per-subject pass/fail, and creates one `report_card`
in `Draft`. Generation MUST be idempotent per `(student, academic_year_id)`.

#### Scenario: Generation creates one draft per enrolled student

- **WHEN** a homeroom teacher or admin POSTs to `/report-cards/generate` for a homeroom with N actively-enrolled students
- **THEN** N report cards exist for that homeroom and year, each in status `Draft`, each summarizing the student's subject scores and pass/fail against the year's grading policy

#### Scenario: Re-generation refreshes only Draft cards

- **WHEN** generation is run again for a homeroom where some cards are still `Draft` and others have advanced past `Draft`
- **THEN** the `Draft` cards are refreshed and the advanced cards are left unchanged and reported as already in workflow

#### Scenario: Pass/fail is derived from the policy at generation time

- **WHEN** a report card is generated
- **THEN** each subject is marked passed or failed by comparing its score to the academic year's `minimum_passing_score`, not by any value stored on the grade

### Requirement: Report cards SHALL follow the role-gated approval state machine

The service MUST enforce the lifecycle
`Draft -> HomeroomReview -> PrincipalApproval -> Published -> Archived` with the
documented role gates. Each transition is a dedicated endpoint with one source
state, one target state, and a required role. Illegal transitions MUST be
rejected and every transition MUST append a `report_approval` audit row.

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
