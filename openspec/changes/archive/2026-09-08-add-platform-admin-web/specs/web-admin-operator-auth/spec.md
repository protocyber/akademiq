## ADDED Requirements

### Requirement: Operator login

The app SHALL authenticate operators against iam-service's operator login endpoint,
obtaining a `typ:"platform"` access token and a platform refresh token. Login MUST
NOT use the tenant two-step (`/enter`) flow.

#### Scenario: Successful operator login

- **WHEN** an operator submits valid credentials
- **THEN** the app stores the platform session and routes to the admin dashboard

#### Scenario: Invalid credentials

- **WHEN** an operator submits invalid credentials
- **THEN** the app shows a centralized error message and does not store a session

### Requirement: Seamless automatic token refresh

The app SHALL automatically refresh an expired access token via the operator
refresh endpoint and retry the original request, modeled on `apps/web`. An expired
access token MUST NOT force a logout when refresh succeeds.

#### Scenario: Silent refresh on expiry

- **WHEN** a request fails because the access token is expired and a valid refresh
  token exists
- **THEN** the app refreshes the token once, retries the original request, and the
  user stays logged in

#### Scenario: Refresh failure redirects to login

- **WHEN** the refresh attempt fails
- **THEN** the app clears the session and redirects to the operator login with a
  `next` return path

#### Scenario: Single shared refresh path

- **WHEN** multiple requests hit expiry concurrently
- **THEN** refresh logic runs through one shared module (no duplicated per-call
  refresh) and concurrent requests do not trigger multiple refreshes

### Requirement: Route guards

All routes except the operator login SHALL require an authenticated platform
session and redirect unauthenticated users to login.

#### Scenario: Unauthenticated access redirected

- **WHEN** an unauthenticated user opens any protected route
- **THEN** the app redirects to the operator login with a `next` return path

#### Scenario: Authenticated user skips login page

- **WHEN** an already-authenticated operator opens the login route
- **THEN** the app redirects to the dashboard
