## Purpose

Manage user passwords, password changes, set password flow for passwordless users, and session/token revocation.

## Requirements

### Requirement: Password section adapts to user type
The profile page SHALL render different password UI based on whether the user has a password set (`password_set` field from `/me`).

#### Scenario: User with password views password section (Type A or C)
- **WHEN** the user has `password_set: true` in their MeProfile
- **THEN** the system SHALL display the "Ganti Password" form with fields: Password Lama, Password Baru, Konfirmasi Password

#### Scenario: User without password views password section (Type B, Google-only)
- **WHEN** the user has `password_set: false` in their MeProfile
- **THEN** the system SHALL display an informational message "Akun Anda belum memiliki password. Saat ini Anda hanya bisa login dengan Google." and a "Buat Password" form with fields: Password Baru, Konfirmasi Password (no current password field)

#### Scenario: Hybrid user (Type C) views password section
- **WHEN** the user has both `password_set: true` and `google_sub` present
- **THEN** the system SHALL display the "Ganti Password" form with an additional info message "Anda juga bisa login dengan Google"

### Requirement: User with password can change their password
The system SHALL expose `POST /api/v1/iam/auth/change-password` that verifies the current password, validates the new password, updates the hash, and revokes all refresh tokens.

#### Scenario: Successful password change
- **WHEN** the user submits a valid current password and a valid new password (min 8 chars) via `POST /api/v1/iam/auth/change-password`
- **THEN** the system SHALL verify the current password using Argon2, hash the new password with Argon2id, update the user's `password_hash`, revoke ALL refresh tokens for the user across all tenants, and return 200

#### Scenario: Current password is incorrect
- **WHEN** the submitted current password does not match the stored hash
- **THEN** the system SHALL return 400 with field error on `current_password`: "Password lama salah"

#### Scenario: New password is too short
- **WHEN** the submitted new password is fewer than 8 characters
- **THEN** the system SHALL return 400 with field error on `new_password`: "Password minimal 8 karakter"

#### Scenario: User without password attempts change-password
- **WHEN** a user with `password_hash = NULL` calls `POST /api/v1/iam/auth/change-password`
- **THEN** the system SHALL return 401 `PASSWORD_NOT_SET` with message "Akun Anda belum memiliki password. Gunakan set-password untuk membuat password."

#### Scenario: Password change revokes all sessions
- **WHEN** a password change succeeds for a user with active refresh tokens in multiple tenants
- **THEN** the system SHALL set `revoked_at = NOW()` on ALL refresh tokens where `user_id` matches, regardless of `tenant_id`

### Requirement: Frontend handles post-password-change logout
After a successful password change, the frontend SHALL clear all tokens and redirect the user to the login page.

#### Scenario: Password change succeeds on frontend
- **WHEN** the `useChangePassword` mutation succeeds
- **THEN** the frontend SHALL display a success toast "Password berhasil diganti", clear all stored tokens (identity, access, refresh), and redirect to `/login`

### Requirement: Passwordless user can create a password via set-password
The system SHALL reuse the existing `POST /api/v1/iam/auth/set-password` endpoint (session-based path) for Google-only users to create their first password.

#### Scenario: Google-only user creates password
- **WHEN** a user with `password_set: false` submits a valid password (min 8 chars) via the "Buat Password" form
- **THEN** the system SHALL call `POST /api/v1/iam/auth/set-password` with `{ password }` (no token), authenticated with access token, and the password SHALL be set

#### Scenario: Password creation succeeds on frontend
- **WHEN** the `useSetPassword` mutation succeeds for a passwordless user
- **THEN** the frontend SHALL display a success toast "Password berhasil dibuat", invalidate the `/me` query (so `password_set` updates to `true`), and update the UI to show the "Ganti Password" form

### Requirement: Password validation is minimum 8 characters
Both change-password and set-password SHALL enforce a minimum password length of 8 characters with no additional complexity requirements.

#### Scenario: Password meets minimum length
- **WHEN** the user submits a password of 8 or more characters
- **THEN** the system SHALL accept the password

#### Scenario: Password is below minimum length
- **WHEN** the user submits a password of fewer than 8 characters
- **THEN** the system SHALL reject with error "Password minimal 8 karakter"

#### Scenario: Confirmation password does not match
- **WHEN** the confirmation password field does not match the new password field
- **THEN** the frontend SHALL display a client-side error "Konfirmasi password tidak cocok" and SHALL NOT submit the request

### Requirement: Password section warns about session revocation
The password section SHALL display a warning that changing the password will log the user out of all devices.

#### Scenario: User views password section with existing password
- **WHEN** the "Ganti Password" form is displayed
- **THEN** a warning message SHALL be shown: "Setelah ganti password, Anda akan logout dari semua perangkat dan harus login ulang."
