## ADDED Requirements

### Requirement: No bundled backend

The web-admin app SHALL NOT ship server-side route handlers that emulate backend
APIs. All data MUST come from the real services over the configured base URLs, so the
app's behaviour does not depend on which origin it is served from.

#### Scenario: App served from any origin behaves identically

- **WHEN** an operator opens the app on the local dev origin or through the reverse
  proxy
- **THEN** both load data from the same real backend services and show the same
  results

#### Scenario: Backend is unreachable

- **WHEN** the configured backend cannot be reached
- **THEN** the app surfaces the request failure through the standard error path
  instead of falling back to locally generated data

#### Scenario: Authentication is always delegated

- **WHEN** an operator submits the login form
- **THEN** the credentials are verified by iam-service, and no in-app code path can
  accept credentials the backend would reject
