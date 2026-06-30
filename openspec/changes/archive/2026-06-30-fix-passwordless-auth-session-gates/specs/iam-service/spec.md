## MODIFIED Requirements

### Requirement: The service SHALL support accounts that have not yet set a password

The service MUST allow an account to exist without a password. Password login
against such an account MUST be rejected with the standard invalid-credentials
error (`INVALID_CREDENTIALS`) — the same code and message returned for a wrong
password — so that the response does **not** reveal whether the account exists
in a no-password state. Non-password authentication (e.g. OAuth) MUST be
unaffected. The distinct `PASSWORD_NOT_SET` code is removed from the login path;
detection of a no-password account for routing purposes is the client's
responsibility, driven by the `password_set` flag on `GET /me`.

#### Scenario: Password login against a no-password account returns invalid credentials

- **WHEN** a user attempts password login on an account with no password set
- **THEN** the response carries the `INVALID_CREDENTIALS` code (not a distinct
  no-password code) and no session is issued

#### Scenario: OAuth login is unaffected by password state

- **WHEN** a no-password account authenticates via OAuth
- **THEN** the login succeeds and is not blocked by the absence of a password

## ADDED Requirements

### Requirement: Credential rotation SHALL revoke all active sessions

`admin_reset_password`, the token-based `set_password`, and the session-based
`set_password_authenticated` MUST revoke **all** of the target user's refresh
tokens after persisting the new password hash, by calling the same
`revoke_all_for_user` mechanism used by `change_password`. This guarantees that
any refresh token minted before the credential change can no longer rotate into
a new access token. For the session-based set-password path, the caller's own
refresh token is also revoked, requiring re-authentication after the password is
set.

#### Scenario: Admin reset invalidates prior sessions

- **WHEN** an admin resets a user's password and that user holds a valid refresh
  token from before the reset
- **THEN** the next `POST /auth/refresh` with that refresh token is rejected as
  revoked, and no new access token is issued

#### Scenario: Self-service set-password invalidates the calling session

- **WHEN** a signed-in no-password user sets a password via the authenticated
  set-password path
- **THEN** all of that user's refresh tokens (including the one backing the
  current session) are revoked, and the client must re-authenticate to continue

#### Scenario: Token-based set-password invalidates prior sessions

- **WHEN** a user sets a password using a single-use set-password token and that
  user also holds a refresh token from a prior session
- **THEN** the prior refresh token is revoked and can no longer mint access
  tokens

### Requirement: Users SHALL be able to request a fresh set-password token

The service MUST provide `POST /api/v1/iam/auth/set-password/resend` to support
recovery for no-password accounts. The endpoint accepts either (a) an
authenticated identity/session request, resolving the caller directly, or (b) an
unauthenticated request carrying an account identifier (email or username). It
MUST look up the account; if the account has no password, it MUST revoke any
prior unconsumed set-password tokens for that user and issue a fresh single-use,
time-bound token (reusing `issue_set_password_token`). If the account already
has a password, or no account matches, the endpoint MUST return the same generic
success-like response to avoid account enumeration. The endpoint MUST be
rate-limited per identifier and per source address.

#### Scenario: No-password user requests and receives a fresh token

- **WHEN** a request identifies a no-password account (by session or by
  identifier)
- **THEN** any prior unconsumed set-password tokens for that user are revoked, a
  new single-use token is issued, and the response indicates success

#### Scenario: Account with a password does not receive a token

- **WHEN** a request identifies an account that already has a password set
- **THEN** no set-password token is issued, and the response is the same generic
  shape as a successful request (no enumeration leak)

#### Scenario: Unknown identifier does not leak existence

- **WHEN** a request carries an identifier that matches no account
- **THEN** the response is identical to the success shape and no token is issued

#### Scenario: Prior token is invalidated on resend

- **WHEN** a no-password user requests a resend and then attempts to use the
  previously-issued (now-superseded) set-password token
- **THEN** the superseded token is rejected as invalid or already used
