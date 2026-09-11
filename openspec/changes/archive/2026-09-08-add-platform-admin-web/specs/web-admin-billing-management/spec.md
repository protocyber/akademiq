## ADDED Requirements

### Requirement: Plan-catalog management

The app SHALL let an operator view, create, update, and deactivate subscription
plans and their feature matrix, using centralized Zod schemas, Nuxt UI `<UForm>`,
and `useMutation` against the platform plan-catalog endpoints.

#### Scenario: View plan catalog

- **WHEN** an operator opens the billing/plans page
- **THEN** the app lists plans with code, prices, and feature flags, showing a
  loading indicator while the query loads

#### Scenario: Create plan with validation

- **WHEN** an operator submits a new plan form
- **THEN** client-side Zod validation runs first, and server `VALIDATION_ERROR`
  field errors are mapped back onto the corresponding form fields

#### Scenario: Duplicate plan code

- **WHEN** the server rejects a duplicate plan `code`
- **THEN** the app shows a centralized conflict message and does not clear the form

### Requirement: Per-tenant subscription override

The app SHALL let an operator change a specific tenant's subscription plan via a
mutation against the platform subscription-override endpoint.

#### Scenario: Override a tenant plan

- **WHEN** an operator assigns a different plan to a tenant and confirms
- **THEN** the app calls the override mutation, shows inline loading, and on success
  refreshes the tenant's subscription view with a success toast

#### Scenario: Unknown plan rejected

- **WHEN** the override targets a plan the server reports as unknown
- **THEN** the app shows a centralized error message and changes nothing in the UI
