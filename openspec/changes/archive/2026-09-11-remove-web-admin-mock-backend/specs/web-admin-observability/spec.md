## MODIFIED Requirements

### Requirement: Usage / overview dashboard

The app SHALL present an overview dashboard summarizing system usage (tenant counts
by status, aggregate student/teacher totals) sourced from
`GET /api/v1/platform/overview`. The figures MUST come from that endpoint only; the
app MUST NOT substitute placeholder or locally generated totals when data is absent.

#### Scenario: View overview dashboard

- **WHEN** an operator opens the dashboard
- **THEN** the app shows aggregate usage figures from the platform endpoint, with
  loading indicators per data-backed widget until each query resolves

#### Scenario: Genuine zero is shown as zero

- **WHEN** the platform endpoint reports zero students or teachers
- **THEN** the dashboard displays zero rather than a fabricated or placeholder figure

#### Scenario: Overview request fails

- **WHEN** the overview request fails
- **THEN** the dashboard surfaces the error through the centralized error path
  instead of rendering invented totals
