## ADDED Requirements

### Requirement: The report board SHALL render all rows without client-side pagination

The `/grading/report-cards` screens MUST render every row returned for the
selected scope without client-side pagination. The screen MUST NOT slice the
result set into fixed-size pages or render previous/next page controls. No
`page_size` query parameter is required because the backend already returns the
full result set for the scope.

#### Scenario: All report-card rows are shown at once

- **WHEN** the user opens a per-class report board whose status tab has more rows than the previous page size
- **THEN** all rows for that tab are rendered and no pagination control is shown
