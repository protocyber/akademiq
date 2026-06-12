## 1. Data model & migration (`iam-service`)

- [ ] 1.1 Migration `V8__*.sql`: `ALTER TABLE "user" ALTER COLUMN password_hash DROP NOT NULL` (currently `NOT NULL` in `V1__init.sql`)
- [ ] 1.2 Migration: `ADD COLUMN google_sub VARCHAR(255)` + partial unique index `WHERE google_sub IS NOT NULL`
- [ ] 1.3 Change `domain.rs::User.password_hash` to `Option<String>`; update `repo.rs::map_user`; add `find_by_google_sub` and a set-`google_sub`-on-existing-user method to `UserRepo`
- [ ] 1.4 Verify migration against a populated test database

## 2. OAuth client & verification

- [ ] 2.1 Add config `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` (+ `.env.example`, secret only in IAM env)
- [ ] 2.2 Implement `state` + PKCE generation and short-TTL server-side storage keyed by `state`
- [ ] 2.3 Implement the authorization-code exchange against Google's token endpoint (server-side, with the client secret and PKCE verifier)
- [ ] 2.4 Implement Google ID-token verification: JWKS fetch + cache (honour key rotation), check signature, `aud`, `iss`, expiry; fail closed
- [ ] 2.5 Extract `{ google_sub, email, email_verified }` from the verified ID token

## 3. Endpoints (`iam-service`)

- [ ] 3.1 `GET /auth/google/start` (public): make state+PKCE, 302 to Google consent
- [ ] 3.2 `GET /auth/google/callback` (public): validate state, exchange code, verify ID token, resolve account, issue identity token, 302 back to web app
- [ ] 3.3 Map OAuth failures to clear errors (invalid/expired state, exchange failure, verification failure)

## 4. Match-or-create / linking (`commands.rs`)

- [ ] 4.1 Resolve by `google_sub` first → log in returning user
- [ ] 4.2 Else, if Google `email_verified` AND email matches an existing account → store `google_sub`, log in (auto-link)
- [ ] 4.3 Else → auto-provision: generated username, Google email (`email_verified=true`), `password_hash = NULL`, `google_sub` set, no tenant membership
- [ ] 4.4 Never auto-link on an unverified Google email
- [ ] 4.5 Harden `commands.rs::login()`: when `user.password_hash` is `None`, call `verify_dummy()` and return `invalid_credentials()` — never unwrap a null hash or pass it to `verify_password`

## 5. Web (`web-auth-onboarding`)

- [ ] 5.1 Add a "Login with Gmail" button on login and signup that navigates to `GET /auth/google/start`
- [ ] 5.2 On return, consume the identity token and funnel into the existing tenant-selection flow (0 / 1 / N)
- [ ] 5.3 Surface OAuth errors returned via the callback redirect

## 6. Tests

- [ ] 6.1 Returning Google user (matching `google_sub`) logs in
- [ ] 6.2 Verified Google email matching an existing password account auto-links and logs into the same account
- [ ] 6.3 Unverified Google email does NOT link to an existing account
- [ ] 6.4 First-time Google user is auto-provisioned as a 0-tenant account with null password
- [ ] 6.5 ID-token verification rejects a forged/`aud`-mismatched/expired token
- [ ] 6.6 `state`/PKCE: callback rejects missing/unknown/expired state
- [ ] 6.7 Password login against a Google-only (null-hash) account returns `INVALID_CREDENTIALS`, timing-safe
- [ ] 6.8 e2e: Login with Gmail → identity token → 0-tenant state → invited → enter → app

## 7. Docs

- [ ] 7.1 Update login sequence diagram (Google path), IAM domain model, ERD (`google_sub`, nullable `password_hash`), component diagram, and API contract (covered by the shared doc-update task)
