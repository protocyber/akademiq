## Why

The passwordless-invite and password-reset flows have three interlocking security and usability holes that together undermine the authentication guarantee. (1) An invited user who never sets a password can operate the full app indefinitely on the scoped token minted at invitation acceptance — password is not a gate. (2) Administrative password reset and self-service set-password do **not** revoke existing refresh tokens, so a prior session keeps minting fresh access tokens right through a reset. (3) Once a no-password user's single-use set-password token is lost or expired, there is **no recovery path** — they cannot log in (PASSWORD_NOT_SET) and cannot obtain a new token, producing a permanent lockout that manifests as a "Sesi Anda sudah berakhir" loop. These were surfaced during QA as "user can log in with any random password" (a symptom of routing, not crypto) and "user is thrown out after setting a password."

## What Changes

- **Forced set-password gate for no-password users.** An account with no password hash MUST NOT be granted operational access beyond a constrained set-password flow. The scoped token minted at invitation acceptance (and the `/me` view's `password_set: false`) is the signal; the client MUST intercept it and force the set-password screen, blocking app entry until a password is set. *(Frontend guard.)*
- **Session revocation on credential rotation.** `admin_reset_password`, `set_password` (token path), and `set_password_authenticated` (session path) MUST revoke all of the user's refresh tokens after persisting the new hash. This matches the existing `change_password` and `verify_email` behavior, closing the window where an old refresh token outlives a reset. *(Backend.)*
- **Resend set-password token endpoint.** A new authenticated-or-identity endpoint `POST /api/v1/iam/auth/set-password/resend` re-issues a fresh single-use set-password token for a no-password account, invalidating any prior unconsumed token. This is the recovery path for locked-out no-password users. *(Backend + frontend.)*
- **Anti-enumeration: collapse PASSWORD_NOT_SET into the standard invalid-credentials error.** `POST /auth/login` MUST return the same `INVALID_CREDENTIALS` code for a no-password account as for a wrong password, eliminating the distinct code that reveals whether an email has an account with no password. The forced-gate logic keys off `/me`'s `password_set: false`, not off a login error code. **BREAKING** for clients that branch on `PASSWORD_NOT_SET`. *(Backend.)*
- **Clear stale scoped tokens on the set-password and login paths.** On successful set-password, the client MUST clear the scoped token pair and navigate to `/login` (not remain in-app on a pre-set-password session). `useLogin` MUST clear stale tokens before attempting a new login so a failed credential check cannot be masked by a lingering prior session. *(Frontend.)*
- **"Lupa Password?" link wired to recovery.** The login page's dead `Lupa Password?` link (`href="#"`) MUST surface the resend-set-password / reset path for no-password accounts, or an admin-contact affordance. *(Frontend.)*

## Capabilities

### New Capabilities
<!-- None — all changes extend existing capabilities. -->

### Modified Capabilities
- `iam-service`: session revocation on reset/set-password; resend set-password-token endpoint; collapse PASSWORD_NOT_SET into INVALID_CREDENTIALS at login
- `web-auth-onboarding`: forced set-password gate for no-password sessions; clear stale tokens on set-password success and before login; wire the recovery/resend path and the "Lupa Password?" affordance

## Impact

- **Backend (`apps/backend/services/iam-service`)**: `commands.rs` (`admin_reset_password`, `set_password`, `set_password_authenticated` gain refresh-token revocation; new resend handler; `login` changes its no-password error code); `http.rs` (new route + handler); `repo.rs` (refresh-token `revoke_all_for_user` already exists, used by `change_password`). Migrations: none expected (set-password-token table already supports the revoke-all pattern).
- **Frontend (`apps/web`)**: `client.ts` (token-clear semantics), `use-tenant-users.ts` (`useSetPassword` auth mode + new resend mutation), `use-login.ts` (pre-login token clear), `auth-guard.tsx` / a new forced-set-password gate (keyed on `password_set`), `login/page.tsx` (drop `PASSWORD_NOT_SET` branch; wire recovery link), `set-password/page.tsx` (clear tokens + navigate to `/login` on success).
- **API contract**: new endpoint; **BREAKING** change to the login error code for no-password accounts (any client branching on `PASSWORD_NOT_SET` must update). Update `docs/internal/11_integration_contracts/apis/`.
- **Events**: no new event types; reset and set-password may emit audit-relevant events but are not required by the event contract.
- **Tests**: backend integration tests for revocation + resend + login code collapse; frontend tests for the forced gate and token-clear paths.
