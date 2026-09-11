## ADDED Requirements

### Requirement: Tenant directory

The app SHALL present a paginated, searchable list of all tenants via TanStack Vue
Query against `GET /api/v1/platform/tenants`, using the DataTable layout
convention.

#### Scenario: View tenant list

- **WHEN** an operator opens the tenants page
- **THEN** the app displays tenants with school name, status, current plan, and
  registered date, with a loading indicator while the query loads

### Requirement: Tenant detail

The app SHALL show a tenant detail view (profile, current subscription, module
entitlements, usage stats) from `GET /api/v1/platform/tenants/{id}`.

#### Scenario: Open tenant detail

- **WHEN** an operator selects a tenant
- **THEN** the app shows that tenant's profile, subscription, modules, and usage

#### Scenario: Unknown tenant

- **WHEN** the requested tenant does not exist
- **THEN** the app shows a not-found state, not a crash

### Requirement: Suspend and reactivate tenant

The app SHALL let an operator suspend and reactivate a tenant via `useMutation`
against the platform command endpoints, with a confirmation step for the
destructive suspend action.

#### Scenario: Suspend with confirmation

- **WHEN** an operator confirms suspending a tenant
- **THEN** the app calls the suspend mutation, shows inline loading on the action
  control, and on success surfaces a success toast and refreshes the tenant view

#### Scenario: Suspend failure

- **WHEN** the suspend mutation fails
- **THEN** the app shows a centralized error message and leaves the tenant state
  unchanged in the UI
