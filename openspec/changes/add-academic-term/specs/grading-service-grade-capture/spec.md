## MODIFIED Requirements

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

## ADDED Requirements

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
