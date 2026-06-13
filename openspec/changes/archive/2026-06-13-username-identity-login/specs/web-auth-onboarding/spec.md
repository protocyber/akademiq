## MODIFIED Requirements

### Requirement: Login form SHALL accept an email-or-username identifier

The web login form MUST present a single credential field labelled
"Email or username" instead of an email-only field. Its Zod schema MUST validate
the field as a non-empty string (not an email-format string), and the login
mutation MUST submit it as `identifier`. The server remains the sole authority
for deciding whether the identifier is an email or a username.

#### Scenario: Form accepts a bare username

- **WHEN** a user types a username (no `@`) into the credential field and submits
- **THEN** the client-side schema accepts it and the mutation sends
  `{ identifier, password }` to `POST /auth/login`

#### Scenario: Form accepts an email address

- **WHEN** a user types an email address into the credential field and submits
- **THEN** the client-side schema accepts it and the mutation sends it unchanged
  as `identifier`

#### Scenario: Empty identifier is rejected client-side

- **WHEN** the credential field is left blank
- **THEN** the Zod schema reports a required-field error before any request is
  sent
