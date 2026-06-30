## MODIFIED Requirements

### Requirement: Web SHALL provide a set-password screen

The web app MUST provide a set-password screen that consumes a set-password token
(from the link) or works from the authenticated no-password session, validates
the new password client-side, submits it to the self-service endpoint, and on
success enables password login. On successful set-password, the client MUST
clear the scoped token pair (`access_token` / `refresh_token`) from local
storage and navigate to `/login` with a success message, because the backend
revokes the session on credential rotation. When the screen is reached **without**
a token and without an authenticated session, it MUST offer a path to request a
fresh set-password token (the resend flow) rather than dead-ending in a
"Sesi Anda sudah berakhir" loop.

#### Scenario: User sets password from the link

- **WHEN** a user opens the set-password link and submits a valid password
- **THEN** the password is saved, the scoped token pair is cleared from local
  storage, and the user is navigated to `/login` with a success message

#### Scenario: User sets password from an authenticated no-password session

- **WHEN** a signed-in no-password user submits a valid new password
- **THEN** the password is saved, the session tokens are cleared (the backend
  revoked them), and the user is navigated to `/login`

#### Scenario: Set-password reached without a token offers recovery

- **WHEN** a user reaches `/set-password` with no token in the URL and no
  authenticated session
- **THEN** the screen presents the resend-set-password affordance (input
  identifier → request a fresh link) instead of throwing an unauthenticated
  error

## ADDED Requirements

### Requirement: No-password sessions SHALL be forced to the set-password gate

A session whose `GET /me` response reports `password_set: false` MUST NOT be
allowed to reach tenant-scoped application pages (`/dashboard` and any route
guarded by `AuthGuard`). The client MUST intercept such a session after login,
invitation acceptance, or tenant entry, and redirect it to `/set-password` before
any protected surface renders. The `/set-password` route itself, `/login`,
`/tenant-select`, and the invitation-accept route MUST remain reachable for a
no-password session. The gate keys off the `password_set` flag from `/me`, not
off any login error code.

#### Scenario: No-password user is blocked from the dashboard

- **WHEN** a user whose account has no password set holds a scoped token and
  navigates to `/dashboard`
- **THEN** the client redirects them to `/set-password` before the dashboard
  renders

#### Scenario: No-password user is blocked immediately after accepting an invitation

- **WHEN** a user accepts an invitation and their new account has no password
- **THEN** the client redirects them to `/set-password` rather than into the app

#### Scenario: Set-password route remains reachable

- **WHEN** a no-password session navigates to `/set-password`, `/login`,
  `/tenant-select`, or the invitation-accept route
- **THEN** the route renders normally and is not blocked by the gate

### Requirement: Login SHALL clear stale tokens before authenticating

The login submission flow MUST clear all locally-stored tokens (`identity`,
`access`, and `refresh`) before issuing the `POST /auth/login` request, so that a
lingering scoped token from a prior session cannot satisfy an auth guard and mask
a failed credential check. This prevents the illusion that an incorrect password
authenticates, which occurs when a stale valid token causes a guard to bounce the
user into the app regardless of the login result.

#### Scenario: Stale scoped token does not mask a failed login

- **WHEN** a browser holds a valid scoped token from a prior session and the user
  submits an incorrect password at `/login`
- **THEN** the locally stored tokens are cleared before the request, the login
  fails with `INVALID_CREDENTIALS`, and the user is not admitted into the app

### Requirement: The login page SHALL offer a password-recovery affordance

The login page's "Lupa Password?" control MUST NOT be a dead link. It MUST open a
flow that lets a no-password or locked-out user request a fresh set-password
token via the resend endpoint (by identifier), or surface an admin-contact
affordance when self-service resend is unavailable. The login page MUST NOT
branch on a `PASSWORD_NOT_SET` error code (that code is no longer returned by the
backend); a no-password login attempt returns `INVALID_CREDENTIALS` and the
recovery affordance is the path forward.

#### Scenario: Locked-out user requests a fresh set-password link

- **WHEN** a user clicks "Lupa Password?" and submits their identifier
- **THEN** the client calls the resend endpoint and shows a confirmation message
  regardless of whether the account exists

#### Scenario: No-password login attempt shows no distinct error

- **WHEN** a user with a no-password account submits any password at `/login`
- **THEN** the error shown is the standard invalid-credentials message and no
  `PASSWORD_NOT_SET`-specific branch or routing occurs
