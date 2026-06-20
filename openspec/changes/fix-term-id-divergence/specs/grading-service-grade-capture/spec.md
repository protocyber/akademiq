## ADDED Requirements

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
