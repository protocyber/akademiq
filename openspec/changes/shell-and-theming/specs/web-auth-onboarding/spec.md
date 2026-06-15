## MODIFIED Requirements

### Requirement: The app shell SHALL present user identity and logout in a top-right avatar dropdown

The authenticated app shell MUST present the signed-in user via an avatar
control in the **top-right header**. Activating it MUST open a dropdown
containing the user's name, a link to the user profile, and a logout action. The
previous bottom-left sidebar user block (name, email, logout button) MUST be
removed so identity lives in exactly one place.

#### Scenario: User opens the avatar dropdown

- **WHEN** the user clicks the top-right avatar
- **THEN** a dropdown shows their name, a link to their profile, and a logout
  action

#### Scenario: Logout from the dropdown

- **WHEN** the user selects logout in the dropdown
- **THEN** the existing logout flow runs (tokens cleared, redirect to login) and
  a loading state is shown while it completes

#### Scenario: Identity is not duplicated in the sidebar

- **WHEN** the shell renders
- **THEN** the sidebar no longer shows the user name/email/logout footer block
