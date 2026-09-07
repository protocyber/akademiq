## MODIFIED Requirements

### Requirement: Global user lookup

The app SHALL present a cross-tenant user directory via TanStack Vue Query against
`GET /api/v1/platform/users`, showing each user's tenant memberships. The directory
MUST be browsable without a search term: on load the app shows a paginated listing,
and the email input filters that listing rather than gating it.

#### Scenario: Browse the directory

- **WHEN** an operator opens the users screen without entering anything
- **THEN** the app shows a paginated list of users with their tenant memberships,
  with a loading indicator while the query loads

#### Scenario: Filter by email

- **WHEN** an operator enters an email and submits the search
- **THEN** the app shows matching users with their tenant memberships, with a
  loading indicator while the query loads

#### Scenario: No matches

- **WHEN** no user matches the search
- **THEN** the app shows an empty-state message, not an error
