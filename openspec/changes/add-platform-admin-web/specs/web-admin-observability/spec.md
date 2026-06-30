## ADDED Requirements

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

The app SHALL present an overview dashboard summarizing system usage (e.g. tenant
counts by status, per-tenant student/teacher totals) sourced from platform read
endpoints.

#### Scenario: View overview dashboard

- **WHEN** an operator opens the dashboard
- **THEN** the app shows aggregate usage figures with loading indicators per
  data-backed widget until each query resolves
