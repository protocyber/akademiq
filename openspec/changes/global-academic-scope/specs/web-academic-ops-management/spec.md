## ADDED Requirements

### Requirement: Academic-ops screens SHALL use the global academic scope for year filtering

Academic-ops management screens SHALL read the academic year from the global academic
scope instead of a page-local or URL-param year picker. This applies to screens that
filter by academic year, such as teaching assignments and homerooms.

#### Scenario: Teaching assignments reflect the header scope

- **WHEN** the user opens the teaching-assignments screen with a year selected in the header
- **THEN** the list is filtered by that year and no page-level year selector is shown
