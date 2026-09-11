# web-admin-observability Specification

## Purpose
TBD - created by syncing change add-platform-admin-web. Update Purpose after archive.
## Requirements
### Requirement: Operator audit log view

The app SHALL present a read-only, paginated view of the operator audit log via
TanStack Vue Query against `GET /api/v1/platform/audit`. There MUST be no UI to
mutate or delete audit entries.

#### Scenario: View audit log

- **WHEN** an operator opens the audit page
- **THEN** the app lists audit entries (actor, action, target, timestamp, outcome)
  with a loading indicator while the query loads

#### Scenario: Audit entries are read-only

- **WHEN** the audit view is rendered
- **THEN** no control to edit or delete an entry is presented

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
