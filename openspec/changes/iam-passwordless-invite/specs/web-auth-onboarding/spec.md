## MODIFIED Requirements

### Requirement: The accept-invitation page SHALL be a single confirm action

The accept-invitation page MUST present a single primary action ("Terima
Undangan") rather than a form requiring name and password. Accepting calls the
invitation-accept endpoint with the token and navigates the now-signed-in user
into the app. A user whose account has no password yet MUST be guided (banner or
CTA) to a separate set-password screen.

> Web work is sequenced **after** the `iam-service` backend changes in this same
> change land (passwordless accept + set-password endpoint).

#### Scenario: One-click accept

- **WHEN** the user opens a valid invitation link and clicks "Terima Undangan"
- **THEN** the invitation is accepted, a session is established, and the user is
  taken into the app without entering a name or password

#### Scenario: Prompt to set a password

- **WHEN** an accepted user has no password set
- **THEN** the app surfaces a path to the set-password screen

### Requirement: Web SHALL provide a set-password screen

The web app MUST provide a set-password screen that consumes a set-password token
(from the link) or works from the authenticated no-password session, validates
the new password client-side, submits it to the self-service endpoint, and on
success enables password login.

#### Scenario: User sets password from the link

- **WHEN** a user opens the set-password link and submits a valid password
- **THEN** the password is saved and they are told password login now works
