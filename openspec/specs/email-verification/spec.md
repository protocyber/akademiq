## Purpose

Manage email verification, email changes, and token validation for AkademiQ users.

## Requirements

### Requirement: User can request email change
The system SHALL allow an authenticated user to request an email change by providing a new email address. The system SHALL send a verification email containing a one-time token to the new email address via the Resend API.

#### Scenario: User requests email change with valid new email
- **WHEN** the user submits a valid, unused email address via `POST /api/v1/iam/auth/request-email-change`
- **THEN** the system SHALL revoke any existing unconsumed email change tokens for the user, generate a new opaque token (32 random bytes, base64url-encoded, Argon2-hashed), insert a row into `email_change_token` with 24-hour expiry, send a verification email to the new address, and return 200

#### Scenario: User requests email change with already-registered email
- **WHEN** the user submits an email address that is already associated with another user account
- **THEN** the system SHALL return 409 `EMAIL_ALREADY_EXISTS` with message "Email sudah digunakan akun lain"

#### Scenario: User requests email change with invalid email format
- **WHEN** the user submits an email that does not contain `@` or is malformed
- **THEN** the system SHALL return 400 validation error with field error on `new_email`

#### Scenario: User requests email change with same as current email
- **WHEN** the user submits their current email address as the new email
- **THEN** the system SHALL return 400 validation error with message "Email baru harus berbeda dari email saat ini"

#### Scenario: User already has a pending email change
- **WHEN** the user requests a new email change while a previous unconsumed token exists
- **THEN** the system SHALL revoke the previous token (set `revoked_at = NOW()`) before creating the new one

### Requirement: Verification email is sent via Resend
The system SHALL send an email verification message using the existing Resend HTTP email client, with an HTML template containing a verification link.

#### Scenario: Email verification email is sent
- **WHEN** an email change is requested
- **THEN** the system SHALL send an email with subject "Verifikasi Email Baru AkademiQ" to the new email address, containing a link to `{PUBLIC_WEB_BASE_URL}/verify-email?token={raw_token}`

#### Scenario: Email provider is set to log mode
- **WHEN** `EMAIL_PROVIDER` is configured as `log` or `disabled`
- **THEN** the system SHALL log the verification link to the application log instead of sending an email, and the request SHALL still return 200

### Requirement: User can verify email change via token
The system SHALL expose `POST /api/v1/iam/auth/verify-email` that accepts a token, verifies it, applies the email change, and revokes all refresh tokens.

#### Scenario: Valid token is submitted
- **WHEN** `POST /api/v1/iam/auth/verify-email` is called with a valid, unconsumed, unrevoked, unexpired token
- **THEN** the system SHALL update the user's email to the new email address, mark the email change token as consumed, revoke ALL refresh tokens for the user across all tenants, and return 200 `{ verified: true }`

#### Scenario: Invalid or consumed token is submitted
- **WHEN** the submitted token does not match any unconsumed email change token
- **THEN** the system SHALL return 401 `INVALID_EMAIL_VERIFICATION_TOKEN` with message "Token verifikasi tidak valid atau sudah digunakan"

#### Scenario: Expired token is submitted
- **WHEN** the submitted token matches an unconsumed but expired email change token
- **THEN** the system SHALL return 410 `EMAIL_VERIFICATION_TOKEN_EXPIRED` with message "Token verifikasi sudah kedaluwarsa"

#### Scenario: Revoked token is submitted
- **WHEN** the submitted token matches a revoked email change token
- **THEN** the system SHALL return 401 `INVALID_EMAIL_VERIFICATION_TOKEN`

### Requirement: User can resend email verification
The system SHALL allow the user to request a new verification email for their pending email change. Each resend SHALL revoke the previous token and generate a new one.

#### Scenario: User resends verification with active pending change
- **WHEN** the user calls `POST /api/v1/iam/auth/resend-email-verification` and has an unconsumed, unrevoked email change token
- **THEN** the system SHALL revoke the existing token, generate a new token with fresh 24-hour expiry, send a new verification email, and return 200

#### Scenario: User resends verification with no pending change
- **WHEN** the user calls resend but has no unconsumed email change token
- **THEN** the system SHALL return 404 `NO_PENDING_EMAIL_CHANGE`

#### Scenario: User resends verification with expired pending change
- **WHEN** the user's pending email change token has expired
- **THEN** the system SHALL revoke the expired token, generate a new token with fresh 24-hour expiry, send a new verification email, and return 200

### Requirement: User can cancel pending email change
The system SHALL allow the user to cancel a pending email change by revoking the unconsumed token.

#### Scenario: User cancels active pending change
- **WHEN** the user calls `POST /api/v1/iam/auth/cancel-email-change` and has an unconsumed email change token
- **THEN** the system SHALL set `revoked_at = NOW()` on the token and return 200

#### Scenario: User cancels with no pending change
- **WHEN** the user calls cancel but has no unconsumed email change token
- **THEN** the system SHALL return 200 (idempotent, no error)

### Requirement: Email change does not affect login until verified
The user's current email SHALL remain the active login credential until the new email is successfully verified.

#### Scenario: User attempts login during pending email change
- **WHEN** the user has a pending (unverified) email change and attempts to log in
- **THEN** the system SHALL authenticate using the original (current) email, not the pending new email

#### Scenario: User attempts login with pending new email
- **WHEN** the user attempts to log in using the pending (not yet verified) new email
- **THEN** the system SHALL return "invalid credentials" (user not found with that email)

### Requirement: Verify email page handles token verification
The system SHALL expose a `/verify-email` frontend page that accepts a `token` query parameter and manages the verification flow.

#### Scenario: User lands on verify-email with valid token
- **WHEN** the user navigates to `/verify-email?token=xxx`
- **THEN** the page SHALL display a loading spinner with "Memverifikasi email..." and POST the token to `POST /api/v1/iam/auth/verify-email`

#### Scenario: Verification succeeds
- **WHEN** the backend returns `{ verified: true }`
- **THEN** the page SHALL display "Email berhasil diverifikasi!", clear all tokens (since refresh tokens were revoked), show a redirect message, and navigate to `/login` after 3 seconds

#### Scenario: Verification fails with expired token
- **WHEN** the backend returns `EMAIL_VERIFICATION_TOKEN_EXPIRED`
- **THEN** the page SHALL display "Token verifikasi sudah kedaluwarsa. Silakan minta link verifikasi baru dari halaman profil." with a link back to `/profile`

#### Scenario: Verification fails with invalid token
- **WHEN** the backend returns `INVALID_EMAIL_VERIFICATION_TOKEN`
- **THEN** the page SHALL display "Token verifikasi tidak valid." with a link back to `/profile`
