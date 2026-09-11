## ADDED Requirements

### Requirement: Global user lookup

The app SHALL let an operator search for a user across all tenants by email via
TanStack Vue Query against `GET /api/v1/platform/users`, showing the user's tenant
memberships.

#### Scenario: Search by email

- **WHEN** an operator enters an email and submits the search
- **THEN** the app shows matching users with their tenant memberships, with a
  loading indicator while the query loads

#### Scenario: No matches

- **WHEN** no user matches the search
- **THEN** the app shows an empty-state message, not an error

### Requirement: User detail

The app SHALL show a user detail view listing the tenants a user belongs to and
their roles per tenant.

#### Scenario: Open user detail

- **WHEN** an operator selects a user from results
- **THEN** the app shows the user's identity fields and per-tenant membership list
