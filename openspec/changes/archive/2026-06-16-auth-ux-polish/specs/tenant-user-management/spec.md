## ADDED Requirements

### Requirement: The edit-user view SHALL indicate email verification status

The UI MUST show a verification indicator derived from `email_verified` wherever a
user's email is displayed prominently — at minimum the edit-user form: a check
icon when the email is verified and an alert/attention icon when it is not, with
an accessible label so the state is not conveyed by color/icon alone.

#### Scenario: Verified email shows a check

- **WHEN** the edit-user form is shown for a user whose `email_verified` is true
- **THEN** a check indicator with an accessible "verified" label appears next to
  the email

#### Scenario: Unverified email shows an alert

- **WHEN** the edit-user form is shown for a user whose `email_verified` is false
- **THEN** an alert indicator with an accessible "not verified" label appears
  next to the email
