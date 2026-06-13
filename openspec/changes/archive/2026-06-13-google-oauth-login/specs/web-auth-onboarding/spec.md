## ADDED Requirements

### Requirement: Web SHALL offer Login with Gmail

The login and signup screens MUST present a "Login with Gmail" action that
navigates the browser to `GET /auth/google/start`. After Google consent and the
backend callback, the client receives an IAM identity token and MUST funnel into
the standard tenant-selection flow (zero / one / many memberships) exactly as
email/password login does. OAuth errors surfaced via the callback redirect MUST be
shown to the user.

#### Scenario: User logs in with Gmail

- **WHEN** a user clicks "Login with Gmail" and completes Google consent
- **THEN** the client receives an identity token and proceeds to tenant selection
  (single-tenant fast path, picker, or 0-tenant empty state as applicable)

#### Scenario: First-time Gmail user with no tenant

- **WHEN** a first-time Google user is auto-provisioned with no tenant membership
- **THEN** the client shows the "You're not part of any school yet" empty state

#### Scenario: OAuth error is shown

- **WHEN** the Google callback returns an error to the web app
- **THEN** the client displays a clear message and returns the user to the login
  screen
