## ADDED Requirements

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
