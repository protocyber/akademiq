## ADDED Requirements

### Requirement: Every user SHALL have a globally-unique username

IAM MUST store a `username` on every `"user"` row. The column is `NOT NULL`,
unique across the entire system (not per-tenant), and compared
case-insensitively. A username MUST be 3–64 characters, start with a letter, and
contain only lowercase letters, digits, `-`, or `_`. A username MUST NOT contain
the `@` character.

When a user is created without an explicit username, IAM MUST generate a unique
slug (`adjective-noun-NNNN`), retrying generation until it finds one not already
in use.

#### Scenario: User created without a username gets a generated one

- **WHEN** a user is created through any path that does not supply a username
- **THEN** IAM assigns a generated, globally-unique slug that satisfies the
  username format rules and contains no `@`

#### Scenario: Username uniqueness is case-insensitive and global

- **WHEN** a username `Fitrah` exists and a second account attempts to take
  `fitrah`
- **THEN** IAM rejects the second account with a uniqueness conflict, regardless
  of which tenant(s) either user belongs to

#### Scenario: Usernames may not contain '@'

- **WHEN** a user-creation or username-change request supplies a username
  containing `@`
- **THEN** IAM rejects it with `VALIDATION_ERROR`

### Requirement: Email SHALL be optional and unique when present

IAM MUST allow a `"user"` row to have a `NULL` email. When `email` is present it
MUST be globally unique, compared case-insensitively. IAM MUST NOT synthesize a
placeholder email for users who have none.

#### Scenario: Two users without an email coexist

- **WHEN** two users are created, each without an email
- **THEN** both rows persist with `email IS NULL` and neither violates the email
  uniqueness constraint

#### Scenario: Duplicate email differing only by case is rejected

- **WHEN** a user with email `teacher@school.test` exists and another account
  attempts `Teacher@School.test`
- **THEN** IAM rejects the second with an email-uniqueness conflict

## MODIFIED Requirements

### Requirement: IAM SHALL authenticate by email or username

The `POST /auth/login` endpoint MUST accept a single `identifier` field
(replacing the former `email` field) plus `password`. IAM MUST classify the
identifier by the presence of `@`: an identifier containing `@` is looked up
against `lower(email)`; an identifier without `@` is looked up against
`lower(username)`. On success IAM issues the standard token envelope.

For an unknown identifier, IAM MUST perform a dummy password verification before
responding and MUST return the generic `INVALID_CREDENTIALS` error, so that
neither email nor username existence is observable through error content or
response timing.

#### Scenario: Login by email

- **WHEN** a user submits `identifier` containing `@` that matches an existing
  email, with the correct password
- **THEN** IAM authenticates the user and returns the token envelope

#### Scenario: Login by username for an email-less user

- **WHEN** a user without an email submits their `username` (no `@`) and the
  correct password
- **THEN** IAM authenticates the user and returns the token envelope

#### Scenario: Unknown identifier does not leak existence

- **WHEN** a login is attempted with an identifier that matches no email and no
  username
- **THEN** IAM performs a dummy password verification and returns
  `INVALID_CREDENTIALS`, indistinguishable in body and timing from a
  wrong-password response for an existing user
