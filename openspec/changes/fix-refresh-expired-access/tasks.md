# Tasks — fix: refresh/logout must not require a live access token

## 1. Repo lookup by jti (`iam-service`)

- [x] 1.1 Migration: add `CREATE UNIQUE INDEX refresh_token_jti_uidx ON refresh_token (jti)` (PK `(user_id, jti)` unchanged)
- [x] 1.2 Add `RefreshTokenRepo::find_by_jti(jti) -> Option<RefreshToken>` returning the full row (incl. `user_id`, `tenant_id`)

## 2. Refresh resolves owner from the refresh token (`iam-service`)

- [x] 2.1 `commands.rs::refresh`: take `refresh_token` only; parse `jti` via `parse_refresh`, load row via `find_by_jti`, derive `user_id` from the row (drop the `user_id` parameter sourced from `AuthContext`)
- [x] 2.2 Keep the existing checks unchanged: revoked → 401, expired → 401, `verify_password(token, row.token_hash)` mismatch → 401
- [x] 2.3 `http.rs::refresh_handler`: remove the `AuthContext` extractor; read body `{ refresh_token }` only (access token header, if present, is ignored)

## 3. Logout (`iam-service`)

- [x] 3.1 `commands.rs::logout` + `http.rs::logout_handler`: resolve via refresh token (same as refresh); do not require a live access token
- [x] 3.2 Revoke by `jti` from the refresh token; `204` even when the access token is expired

## 4. Tests (`iam-service`)

- [x] 4.1 Keep `refresh_rotates_within_bound_tenant_and_revokes_old_token` green (sends a valid access token — must still pass)
- [x] 4.2 New: refresh succeeds with an **expired/omitted** access token + valid refresh token → new pair, old row revoked
- [x] 4.3 New: refresh with unknown/revoked/expired refresh token → 401
- [x] 4.4 New: logout succeeds (`204`) with an expired access token + valid refresh token

## 5. Verify

- [x] 5.1 `cd apps/backend && make test` (or `cargo test -p iam-service`) — all green
- [ ] 5.2 Manual/e2e: idle past 15 min, resume activity → request silently refreshes, no forced logout (web on-401 path unchanged)
