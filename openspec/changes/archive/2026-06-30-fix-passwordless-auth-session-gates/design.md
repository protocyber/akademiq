## Context

AkademiQ supports passwordless invitation: accepting an invitation creates an account with a `NULL` password hash and issues a tenant-scoped token pair immediately, plus a single-use set-password token shown once. The intent is "signed in now, set a password later." Three gaps in this design surfaced during QA:

1. **No gate forces the "later."** The scoped token from `accept_invitation` is a fully valid access token. The client learns `password_set: false` from `/me` but only *suggests* (banner/CTA) visiting `/set-password`. A no-password user can use the entire app until they happen to log out — at which point they hit a dead end.
2. **Credential rotation doesn't kill sessions.** `admin_reset_password`, `set_password`, and `set_password_authenticated` persist a new hash but never revoke refresh tokens. Only `change_password` and `verify_email` call `revoke_all_for_user`. An attacker (or shared device) holding a prior refresh token survives a reset.
3. **No recovery path for no-password lockout.** The set-password token is single-use and shown once. Lost or expired → the user cannot log in (`PASSWORD_NOT_SET`) and cannot get a new token. They loop between `/login` and `/set-password` seeing "Sesi Anda sudah berakhir."

The QA report "login with any random password succeeds" is a **symptom of the routing**, not a crypto flaw: Argon2 verification is correct. A no-password login returns `PASSWORD_NOT_SET`, the client routes to `/set-password` (appearing to "get in"), and the dead-end there throws `UNAUTHENTICATED`. Fixing the routing — not the verifier — is the work.

## Goals / Non-Goals

**Goals:**
- Make "has a password" a real gate: a no-password account cannot reach tenant-scoped app surfaces.
- Make password reset / set-password actually invalidate prior sessions (revoke refresh tokens).
- Provide a working recovery path for no-password users (resend set-password token).
- Eliminate the `PASSWORD_NOT_SET` enumeration vector at login.
- Clear stale client-side tokens so a prior session can't mask a failed login or survive past set-password.

**Non-Goals:**
- Full email-based "forgot password" SMTP flow (out of scope; resend uses the existing in-app/identity path or admin delivery).
- Changing Argon2 parameters or the token formats.
- Re-architecting the identity/scoped token split.
- Touching OAuth (Google) login — it is unaffected by password state.
- Cluster B/C/D bugs from the same QA list (separate changes).

## Decisions

### Decision 1: Gate on the client, using `password_set` from `/me`
**Choice:** The forced set-password gate is a **frontend guard**, keyed on `useMe().password_set === false`, enforced for any session that holds a scoped token. A no-password scoped session is redirected to `/set-password` before reaching `/dashboard` or any `AuthGuard` page.

**Rationale:** The backend cannot cheaply distinguish "legitimate no-password invitee who just accepted and is on their way to /set-password" from "no-password user trying to use the app" without breaking the one-click accept UX. The scoped token *is* how the user reaches `/set-password`. The `/me` response already carries `password_set`; the client is the right place to enforce "you may not proceed past set-password."

**Alternatives considered:**
- *Backend denies all scoped requests for no-password users except set-password.* Cleaner security boundary but requires a request-time password-state check on every tenant-scoped call (perf + a new failure mode mid-session) and breaks the accept→set-password handoff. Rejected.
- *Issue a special "provisional" token at accept that only `/set-password` accepts.* Heaviest change; requires a new token type and routing. Rejected for this scope.

### Decision 2: Revoke refresh tokens in all three credential-rotation paths
**Choice:** `admin_reset_password`, `set_password` (token path), and `set_password_authenticated` (session path) each call `refresh_repo.revoke_all_for_user(user_id)` after persisting the hash, mirroring `change_password`.

**Rationale:** `revoke_all_for_user` already exists and is proven by `change_password`/`verify_email`. Consistency is the win: any credential change invalidates outstanding sessions. For `set_password_authenticated`, the calling session's own refresh token is also revoked — the client must re-authenticate after setting a password (see Decision 4).

### Decision 3: New endpoint `POST /api/v1/iam/auth/set-password/resend`
**Choice:** A new endpoint re-issues a set-password token for a no-password account. It accepts either an identity token (the user logged in via OAuth and has no password) or an unauthenticated request carrying the account email/identifier. It revokes prior unconsumed set-password tokens for the user before issuing a new one. Rate-limited. Refuses (with a generic response, not an enumeration leak) if the account already has a password or doesn't exist.

**Rationale:** This is the missing recovery path. Reusing the existing `issue_set_password_token` helper and the existing `set_password_token` table keeps it small. Accepting an identifier (not requiring a live session) is necessary because the locked-out user has no session.

**Alternatives considered:**
- *Admin-only re-issue from the users page.* Useful as a secondary path but insufficient alone (requires admin availability). Included as a frontend affordance but not the primary recovery path.
- *Full forgot-password email flow.* Larger scope; deferred (Non-Goal).

### Decision 4: Collapse `PASSWORD_NOT_SET` into `INVALID_CREDENTIALS` at login
**Choice:** `login()` returns the standard `INVALID_CREDENTIALS` for a no-password account instead of the distinct `PASSWORD_NOT_SET`. The client no longer branches on `PASSWORD_NOT_SET` for routing; the forced gate (Decision 1) covers no-password detection via `/me`.

**Rationale:** A distinct error code for "this email exists but has no password" is an account-enumeration vector. The forced gate already handles the legitimate no-password case through `password_set`, so the login-time distinct code is no longer needed for routing.

**BREAKING:** Any client branching on `PASSWORD_NOT_SET` must update. The web client's `login.tsx` branch is removed in this change.

### Decision 5: Clear client tokens on set-password success and pre-login
**Choice:**
- On successful set-password, the client clears the scoped token pair (`clearTokens`) and navigates to `/login` with a success toast — the backend revoked the session anyway (Decision 2), so the token is dead regardless.
- `useLogin` calls `clearAllTokens()` before issuing the login request, so a lingering prior session cannot satisfy `PublicOnly`/`AuthGuard` and mask a failed credential check.

**Rationale:** The QA "any password logs in" illusion was caused by `PublicOnly` bouncing to `/dashboard` on token presence alone. Clearing before login removes the mask; the forced gate (Decision 1) makes a no-password scoped session non-operational regardless.

## Risks / Trade-offs

- **[Forced gate false-negative if `/me` is stale]** → The gate depends on `/me`'s `password_set`. The query is already central to auth state; keep its cache invalidated on set-password success. Worst case is a one-render-delay; acceptable.
- **[Resend endpoint abuse / spam]** → Rate-limit the endpoint (reuse the existing rate-limit middleware pattern) and return a generic success-like response regardless of whether the account exists, to avoid enumeration.
- **[BREAKING login error code]** → Document in the API contract and the release notes; only the web client is known to branch on it. A search for `PASSWORD_NOT_SET` across consumers confirms the blast radius.
- **[Revoke on set-password_authenticated kills the current session]** → Intended (forces re-auth with the new password), but the UX must set expectations: "password saved, please log in." This matches `change_password` behavior today.
- **[No-password user mid-flow after accept]** → The gate must permit `/set-password` itself and the accept-invitation handoff; the guard exempts exactly those routes.

## Migration Plan

1. **Backend first:** add revocation to the three rotation handlers (safe, additive); add the resend endpoint (additive); change login's no-password error code (breaking — coordinate with frontend deploy). Backend can ship revocation + resend ahead of the frontend without breakage.
2. **Frontend:** add the forced gate, token-clear, and resend UI; remove the `PASSWORD_NOT_SET` login branch. Deploy after the backend login-code change is live (or in the same release).
3. **No data migration** required — `password_set` is derived from `password_hash IS NOT NULL`, and the set-password-token table already supports the revoke pattern.
4. **Rollback:** backend revocation and resend are independently revertible. The login-code change is the one coordination point; reverting it requires reverting the frontend branch removal too.

## Open Questions

- Should the resend endpoint also be exposed to admins on the users page (re-issue + copy link), in addition to the self-service path? (Leaning yes as a secondary affordance; confirm during implementation.)
- Rate-limit budget for the resend endpoint — match existing auth rate limits or a stricter per-identifier limit? (Confirm against the existing limiter config during implementation.)
