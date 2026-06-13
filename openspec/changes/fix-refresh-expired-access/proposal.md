## Why

A user who is idle longer than the 15-minute access-token TTL and then resumes
activity is **force-logged-out**, even though their refresh token is still valid
for 7 days. This contradicts the intended behavior: the session should renew
silently and the user should stay signed in until the **refresh token** itself
expires or is revoked.

### Root cause

`POST /api/v1/iam/auth/refresh` uses the `AuthContext` extractor
(`iam-service/src/http.rs:227`), which decodes the **access token** from the
`Authorization` header with `validate_exp = true` (`common-auth/src/jwt.rs`).
So the endpoint whose entire purpose is to replace an expired access token
**rejects the request because the access token is expired** — a circular
dependency:

```
idle > 15 min, user clicks something
  1. request → 401 EXPIRED_ACCESS_TOKEN
  2. web on-401 interceptor calls tryRefresh()         (client.ts — already correct)
  3. POST /auth/refresh
       Authorization: Bearer <EXPIRED access token>    ← same dead token
       body: { refresh_token: <still valid 7 days> }
  4. AuthContext::verify(access) → Expired → 401        ← BUG: refresh refused
  5. client clears tokens → redirect /login            → forced logout
```

The access token is used **only** to supply `user_id` to
`refresh_repo.find(user_id, jti)` (`commands.rs:233`, `repo.rs:445`). It adds no
security: `refresh()` already independently (a) looks the row up by `jti`,
(b) rejects revoked, (c) rejects expired, and (d) verifies the bcrypt hash of the
presented refresh token against `token_hash` (`commands.rs:248–273`). Ownership
and anti-guessing are fully enforced by the hash + `jti`; requiring a live access
token only breaks refresh exactly when it is needed.

`logout` (`http.rs:236`) has the same shape (`AuthContext` + refresh token) and
the same latent defect — a user with an expired access token cannot cleanly log
out / revoke their refresh token.

## What Changes

- **`POST /auth/refresh` MUST NOT require a live access token.** The refresh
  token is a self-contained credential: the handler resolves the owner from the
  refresh token itself and rotates. The access token is no longer read for
  identity.
  - Refresh tokens are formatted `"{jti}.{secret}"` (`commands.rs:163`), so `jti`
    is already inside the token. Add a `RefreshTokenRepo::find_by_jti(jti)`
    lookup; `jti` is a globally-random UUID v4, so a unique index makes it a
    sound standalone key. **The PK `(user_id, jti)` does not change** — only an
    additional lookup path + unique index on `jti` are added.
  - `refresh()` derives `user_id` from the found row, then proceeds with the
    existing revoke-expired / verify-hash / rotate logic unchanged.
- **`POST /auth/logout` MUST apply the same rule** — revoke the refresh token
  regardless of whether the access token has expired.
- **Backward compatible**: clients MAY still send the (now-ignored for identity)
  access token; existing requests that send a valid access token continue to
  succeed. The request body (`{ refresh_token }`) is unchanged.
- **No web changes required**: the existing on-401 interceptor
  (`web/src/lib/api/client.ts`) already retries via `/auth/refresh`; once the
  endpoint stops rejecting expired-access requests, the silent-renew path
  completes end-to-end.

## Capabilities

### Modified Capabilities

- `iam-service`: `/auth/refresh` and `/auth/logout` no longer require a live
  access token; refresh-token rotation and revocation depend solely on the
  refresh token credential.

## Impact

- **Schema**: add a unique index on `refresh_token(jti)`; PK unchanged. No data
  migration of existing rows.
- **Code**: `repo.rs` (`find_by_jti`), `commands.rs::refresh` and `::logout`
  (resolve owner from refresh token), `http.rs` (drop the `AuthContext`
  requirement on `refresh_handler`/`logout_handler`; read `user_id` from the
  resolved row instead).
- **Security posture is unchanged or improved**: ownership is still proven by the
  bcrypt hash check; the change removes a dependency that provided no security
  guarantee. A revoked/expired refresh token is still rejected.
- **Tests**: existing `refresh_rotates_within_bound_tenant_and_revokes_old_token`
  (sends a valid access token) MUST still pass; add a test that refresh succeeds
  with an **expired/absent** access token and a valid refresh token, and a test
  that logout works with an expired access token.

## Open Decisions

1. **Keep accepting the access token in the request (ignored) vs. drop it
   entirely.** Default: **accept-but-ignore** for the access token header to keep
   the web client unchanged; identity is taken from the refresh token. The body
   stays `{ refresh_token }`.
2. **Interaction with [[rbac-custom-roles-multirole]]**: that change alters the
   access-token *claims* shape; this change *stops reading the access token at
   refresh*, so the two are independent and can land in either order.
