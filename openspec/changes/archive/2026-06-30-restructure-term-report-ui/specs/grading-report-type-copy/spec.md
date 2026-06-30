## ADDED Requirements

### Requirement: Grading-service SHALL copy report types between terms

The grading-service MUST expose
`POST /api/v1/grading/report-types/copy` that copies report-type definitions
(`code`, `name`, relative `position`) from a source term to a target term within
the same academic year and tenant. The request body MUST be
`{ academic_year_id, source_term_id, target_term_id, overwrite }`. The endpoint
MUST be tenant-scoped and require an admin role. It MUST reject when
`source_term_id == target_term_id`, when the two terms do not both belong to the
caller's tenant and the given `academic_year_id`, and when `overwrite` is `true`
(until a product need adds overwrite semantics). Duplicate report-type codes
already present in the target term MUST be skipped. The inserts MUST run in a
single transaction so the copy is atomic. The response MUST return a
`{ data: { copied, skipped }, meta: {} }` envelope. Formulas MUST NOT be copied
(formulas reference term-scoped evaluations and require separate mapping).

#### Scenario: Happy-path copy

- **WHEN** an admin posts a copy request with a valid source and target term in
  the same academic year
- **THEN** report types not already present in the target are created with the
  same code/name and contiguous positions, and the response reports
  `{ copied, skipped }`

#### Scenario: Duplicate codes are skipped

- **WHEN** the source and target share a report-type code
- **THEN** that code is skipped (not overwritten) and counted in `skipped`

#### Scenario: Same source and target is rejected

- **WHEN** `source_term_id == target_term_id`
- **THEN** the endpoint rejects with a validation/conflict error and copies
  nothing

#### Scenario: Overwrite not supported yet

- **WHEN** the request sets `overwrite: true`
- **THEN** the endpoint rejects with HTTP 422 and copies nothing

#### Scenario: Cross-year term rejected

- **WHEN** the source or target term does not belong to the given
  `academic_year_id` (or the caller's tenant)
- **THEN** the endpoint rejects with a not-found/forbidden error and copies
  nothing
