## ADDED Requirements

### Requirement: A term's `term_id` SHALL be owned by academic-config and never fabricated downstream

The grading service MUST NOT derive or invent a `term_id`. Every `term_id` used
by grading MUST originate from academic-config and reach grading through the
`academic_term.created` / `academic_term.status_changed` projection. Deriving a
`term_id` from another value (e.g. `md5(academic_year_id)`) or generating a new
UUID as a fallback MUST NOT occur.

#### Scenario: Real term id resolves after projection

- **WHEN** academic-config has an Active term and its `academic_term.created`
  event has been consumed by grading
- **THEN** a write referencing that real `term_id` resolves in grading's
  `valid_term` projection and is not rejected as "term not found"

#### Scenario: Grading never generates a term id

- **WHEN** a grading command or query handles a request without a resolvable
  projected term for the scope
- **THEN** it MUST surface a domain error rather than synthesize a `term_id`

### Requirement: Existing divergent term references SHALL be reconciled to the real term id

The system MUST provide a one-time, idempotent heal that aligns grading's
`evaluation`, `report_type`, and `valid_term` rows carrying a fabricated
`md5(academic_year_id)` term id to the real `term_id` owned by academic-config.
The heal MUST consist of (1) academic-config republishing `academic_term.created`
for all existing terms via the transactional outbox, and (2) a grading reconcile
operation that remaps rows using the corrected `valid_term` as the
`academic_year_id → real term_id` map, then removes the ghost `valid_term` rows.

#### Scenario: Republish populates the real projection rows

- **WHEN** academic-config republishes `academic_term.created` for an existing
  term
- **THEN** grading's `valid_term` gains a row keyed by the real `term_id`
  without disturbing any pre-existing ghost row

#### Scenario: Reconcile remaps dependent rows

- **WHEN** the reconcile operation runs after the republish has populated the
  real `valid_term` rows
- **THEN** `evaluation` and `report_type` rows whose `term_id` equals
  `md5(academic_year_id)` are updated to the real `term_id`, and the ghost
  `valid_term` rows are deleted

#### Scenario: Reconcile is idempotent and reports no-change

- **WHEN** the reconcile operation runs a second time with nothing left to remap
- **THEN** it changes no rows and exits non-zero to signal no-op (per CLI
  guardrails), without corrupting any data

### Requirement: The reconcile operation SHALL respect the projection-based service boundary

The grading reconcile MUST NOT query `academic_config_db` directly. The real
`term_id` MUST be obtained only from grading's own `valid_term` projection, which
is populated by consuming `academic_term.*` events.

#### Scenario: No cross-database access

- **WHEN** the reconcile operation resolves the `academic_year_id → real term_id`
  map
- **THEN** it reads only grading-local tables (the `valid_term` projection) and
  issues no query against academic-config's database
