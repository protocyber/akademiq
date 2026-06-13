## ADDED Requirements

### Requirement: IAM SHALL support Login with Google via backend-completed OAuth

IAM MUST expose `GET /auth/google/start` and `GET /auth/google/callback` to
authenticate a user with their Google account using the OAuth 2.0 Authorization
Code flow with PKCE, completed server-side. `/start` MUST generate a CSRF `state`
and a PKCE challenge, persist them server-side, and redirect to Google's consent
screen. `/callback` MUST validate `state`, exchange the authorization code for
tokens using the server-held client secret, verify the Google ID token
(signature via Google's JWKS, `aud`, `iss`, expiry), and — on success — issue an
IAM **identity token** and redirect to the web app. The Google client secret and
Google's tokens MUST NOT be exposed to the browser.

#### Scenario: Successful Google login issues an IAM identity token

- **WHEN** a user completes Google consent and `/callback` verifies the ID token
- **THEN** IAM resolves the account and issues its own identity token, never
  exposing Google's tokens or the client secret to the browser

#### Scenario: Forged or invalid ID token is rejected

- **WHEN** `/callback` receives an ID token failing signature, `aud`, `iss`, or
  expiry checks
- **THEN** IAM rejects the login and issues no token

#### Scenario: Missing or invalid state is rejected

- **WHEN** `/callback` is invoked with a missing, unknown, or expired `state`
- **THEN** IAM rejects the request without exchanging the code

### Requirement: Google identities SHALL match, link, or auto-provision an account

On a verified Google login, IAM MUST resolve the account in this precedence:
(1) an account whose `google_sub` matches logs in; (2) otherwise, if Google
reports `email_verified=true` and the email matches an existing account, IAM MUST
store `google_sub` on that account and log in (auto-link); (3) otherwise IAM MUST
auto-provision a new account with a generated username, the Google email marked
verified, a `NULL` password, `google_sub` set, and no tenant membership. IAM MUST
NOT auto-link to an existing account on an unverified Google email.

#### Scenario: Returning Google user matches by google_sub

- **WHEN** a user whose account already carries a matching `google_sub` logs in
  with Google
- **THEN** IAM logs them into that account

#### Scenario: Verified email auto-links to an existing account

- **WHEN** a Google login reports a verified email matching an existing
  password-based account that has no `google_sub`
- **THEN** IAM stores `google_sub` on that account and logs the user into it

#### Scenario: Unverified email does not claim an existing account

- **WHEN** a Google login reports an unverified email that matches an existing
  account
- **THEN** IAM does not link to that account and instead auto-provisions or
  refuses per policy

#### Scenario: First-time Google user is auto-provisioned without a tenant

- **WHEN** a verified Google login matches no `google_sub` and no existing email
- **THEN** IAM creates a new account (generated username, verified email, null
  password, `google_sub` set) with no tenant membership and issues an identity
  token

## MODIFIED Requirements

### Requirement: Password storage SHALL allow passwordless accounts

`user.password_hash` MUST be nullable so that Google-only accounts (and other
passwordless accounts) are valid. The password-login path MUST treat a `NULL`
`password_hash` as "no password set", returning `INVALID_CREDENTIALS` after a
dummy verification to remain timing-safe, and MUST never crash or bypass
authentication for such accounts. An account MAY have both a password and a linked
Google identity.

#### Scenario: Password login against a Google-only account fails safely

- **WHEN** someone attempts password login for an account whose `password_hash` is
  `NULL`
- **THEN** IAM performs a dummy verification and returns `INVALID_CREDENTIALS`,
  with timing indistinguishable from a wrong-password attempt

#### Scenario: Account with both methods can use either

- **WHEN** an account has both a `password_hash` and a `google_sub`
- **THEN** the user can authenticate by password or by Google, and both resolve to
  the same account
