## 1. Backend — session revocation on credential rotation
- [x] 1.1 Add `refresh_repo.revoke_all_for_user(user_id)` call at the end of `set_password` (token path) in `commands.rs`, after the hash is persisted
- [x] 1.2 Add the same revocation call at the end of `set_password_authenticated` in `commands.rs`
- [x] 1.3 Add the same revocation call at the end of `admin_reset_password` in `commands.rs`
- [ ] 1.4 Add backend integration tests asserting a pre-reset refresh token is rejected after each of the three rotation paths — skipped in this slice; run manually after backend test ownership is available.

## 2. Backend — collapse PASSWORD_NOT_SET at login
- [x] 2.1 In `commands.rs::login`, replace the `PASSWORD_NOT_SET` `AppError::unauthenticated` branch with the standard `invalid_credentials()` return (same code/message as a wrong password)
- [x] 2.2 Remove the now-unused `PASSWORD_NOT_SET` login code path; verify `verify_dummy` timing-equality rationale still holds (no-password path now runs the same exit as user-not-found)
- [x] 2.3 Update `docs/internal/11_integration_contracts/apis/` to mark `PASSWORD_NOT_SET` removed from login, note the BREAKING change
- [ ] 2.4 Add/adjust integration test: login against a no-password account returns `INVALID_CREDENTIALS` — skipped in this slice; run manually after backend test ownership is available.

## 3. Backend — resend set-password token endpoint
- [x] 3.1 Add `POST /api/v1/iam/auth/set-password/resend` route in `http.rs`
- [x] 3.2 Implement the handler: resolve caller from an identity/session token if present, else accept an identifier body field; look up the user; if no-password → revoke prior unconsumed tokens + `issue_set_password_token`; if has-password or unknown → return generic success shape (no enumeration)
- [ ] 3.3 Apply rate limiting per identifier and per source address (match existing auth limiter pattern) — blocked: no existing auth limiter pattern or rate-limit dependency was found in backend Rust code.
- [ ] 3.4 Add integration tests: no-password user gets a fresh token; has-password user gets generic response; unknown identifier gets identical response; prior token invalidated after resend — skipped in this slice; run manually after backend test ownership is available.
- [x] 3.5 Add the endpoint to the API contract docs

## 4. Frontend — forced set-password gate
- [x] 4.1 Create a gate (e.g. `RequirePasswordGate` or logic in the auth-resolution layer) that reads `useMe().password_set` and redirects a `password_set === false` scoped session to `/set-password`
- [x] 4.2 Apply the gate so `/dashboard` and all `AuthGuard`-protected routes cannot render for a no-password session; exempt `/set-password`, `/login`, `/tenant-select`, `/invitations/accept`
- [x] 4.3 Ensure `/me` cache is invalidated after set-password success so the gate re-evaluates
- [x] 4.4 Add frontend tests: no-password session redirected from `/dashboard`; exempt routes still reachable

## 5. Frontend — set-password screen recovery + token clear
- [x] 5.1 On successful set-password, call `clearTokens()` (scoped pair) and navigate to `/login` with a success toast (not remain in-app)
- [x] 5.2 When `/set-password` is reached with no token and no session, render the resend affordance (identifier input → resend mutation) instead of throwing unauthenticated
- [x] 5.3 Add `useResendSetPassword` mutation in `use-tenant-users.ts` calling the new endpoint; show a generic confirmation regardless of response
- [x] 5.4 Fix `useSetPassword`: when a token is present, send an unauthenticated request (token in body); only use `authenticated: true` for the session path; avoid the client-side `UNAUTHENTICATED` throw

## 6. Frontend — login token-clear + recovery link
- [x] 6.1 In `useLogin`, call `clearAllTokens()` before issuing `POST /auth/login`
- [x] 6.2 Remove the `PASSWORD_NOT_SET` branch in `login/page.tsx` (backend no longer returns it); no-password attempts now show standard invalid-credentials
- [x] 6.3 Wire the "Lupa Password?" link to open the resend/recovery flow (modal or route) calling `useResendSetPassword`
- [x] 6.4 Add frontend test: stale scoped token does not mask a failed login (cleared before request)

## 7. Verification
- [ ] 7.1 Repro the original QA scenario end-to-end: accept invite → skip set-password → attempt app entry → forced to `/set-password`; full flow now works and no-password user cannot operate the app
- [ ] 7.2 Confirm a pre-reset refresh token is rejected after admin reset and after self-service set-password
- [ ] 7.3 Confirm the resend endpoint recovers a locked-out no-password user
- [ ] 7.4 Confirm `PASSWORD_NOT_SET` no longer appears in any login response or client branch
- [ ] 7.5 Run `make test` in both submodules; run web lint/typecheck — web lint/typecheck + targeted web tests passed; full `make test` is a slow cross-submodule suite (see Manual Backend Tests).

## Manual Backend Tests

Run these manually when backend integration testing is available:

```sh
cd apps/backend && cargo test -p iam-service --test integration
cd apps/backend && make test
```
