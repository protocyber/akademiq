## ADDED Requirements

### Requirement: The report board SHALL use the global academic scope

The `/grading/report-cards` board SHALL obtain the academic year from the global academic
scope instead of rendering its own year selector. It SHALL list that year's report types
without a page-level year picker.

#### Scenario: Report board reflects the header scope

- **WHEN** the user opens `/grading/report-cards` with a year selected in the header
- **THEN** the board lists that year's report types and shows no page-level year selector
