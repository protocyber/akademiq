## MODIFIED Requirements

### Requirement: Invitations SHALL grant membership to an account that may already exist

Accepting an invitation MUST grant the invited roles and tenant membership. When
the invited email already has an account, acceptance attaches the membership to
that account without requiring a password. When the invited email has **no**
account, acceptance MUST create a new account and attach membership; creating
that account MUST NOT require the invitee to choose a password at accept time.
The invitee MUST be signed in (scoped token pair) upon acceptance in both cases.

#### Scenario: Existing account accepts without a password

- **WHEN** the invited email already has an account and the invitation is accepted
- **THEN** the membership and roles are attached and a scoped session is issued,
  with no password input required

#### Scenario: New account is created without a password

- **WHEN** the invited email has no account and the invitation is accepted with
  only the token
- **THEN** a new account is created in a no-password state, membership and roles
  are granted, and a scoped session is issued

#### Scenario: Name falls back when not provided

- **WHEN** a new account is created from a button-only accept with no name input
- **THEN** the account's name is taken from the invitation record (or a
  placeholder the user can edit later), and acceptance still succeeds

## ADDED Requirements

### Requirement: The service SHALL support accounts that have not yet set a password

The service MUST allow an account to exist without a password. Password login
against such an account MUST be rejected with a distinct, actionable error code
(e.g. `PASSWORD_NOT_SET`) rather than a generic invalid-credentials response, so
the client can route the user to set a password. Non-password authentication
(e.g. OAuth) MUST be unaffected.

#### Scenario: Password login blocked until a password is set

- **WHEN** a user attempts password login on an account with no password set
- **THEN** the response carries a distinct "password not set" code and no session
  is issued

### Requirement: The service SHALL issue a single-use, time-bound set-password token

When a no-password account is created (or on request), the service MUST issue a
single-use, time-bound set-password token bound to that user. The token MUST be
rejected after it is consumed once or after it expires.

#### Scenario: Token is single-use

- **WHEN** a set-password token is used successfully and then presented again
- **THEN** the second use is rejected

#### Scenario: Token expires

- **WHEN** a set-password token is presented after its expiry
- **THEN** it is rejected

### Requirement: Users SHALL set their password via a self-service endpoint

The service MUST provide a self-service set-password endpoint that accepts either
a valid set-password token or an authenticated session belonging to a no-password
account, validates the new password (same strength rules as today, min 8 chars),
persists it, and marks the account as having a password set. After success,
password login MUST work normally.

#### Scenario: Set password with a valid token

- **WHEN** a user submits a new valid password with a valid set-password token
- **THEN** the password is set, the token is consumed, and password login
  subsequently succeeds

#### Scenario: Set password from an authenticated no-password session

- **WHEN** a signed-in no-password user submits a valid new password
- **THEN** the password is set and password login subsequently succeeds

#### Scenario: Weak password rejected

- **WHEN** a submitted password is shorter than the minimum length
- **THEN** the request is rejected with a validation error and no password is set
