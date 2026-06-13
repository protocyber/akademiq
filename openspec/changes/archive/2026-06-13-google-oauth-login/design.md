## Context

The client wants "Login with Gmail." AcademiQ already has a full IAM service that
issues its own RS256 tokens, so the design goal is to add Google as an
*authentication mechanism* without ceding identity ownership. Google proves an
email; IAM still mints every token. This depends on
[[public-signup-tenant-tokens]] (Google login emits an identity token; first-time
Google users auto-provision as 0-tenant accounts) and [[username-identity-login]]
(generated username, nullable email).

## Why not Supabase

Supabase Auth is itself a complete identity provider — its own `auth.users`, its
own JWTs, its own OAuth dance. Adopting it for "just Google login" would run a
second IdP alongside IAM and force every service to reconcile two token formats,
or to trust Supabase JWTs and re-map AcademiQ's multi-tenant roles onto them. The
value Supabase offers ("don't build auth") is already spent — IAM exists. Direct
Google OAuth keeps one identity system and one token format. Supabase is rejected.

## Decisions

### D1 — Backend-completed OAuth (Authorization Code + PKCE)

The Rust IAM service completes the handshake, not the browser:

```
  Browser ─▶ GET /auth/google/start
                └─ IAM makes state+PKCE, 302 ─▶ Google consent
  Google  ─▶ GET /auth/google/callback?code&state
                ├─ IAM validates state, exchanges code w/ GOOGLE_CLIENT_SECRET
                ├─ IAM verifies Google ID token (sig via JWKS, aud, iss, exp)
                ├─ extract { google_sub, email, email_verified }
                ├─ match-or-create account (D3)
                └─ issue IAM identity token, 302 ─▶ web app
```

The `client_secret` never reaches the browser, and the browser never sees
Google's tokens — only IAM's identity token. This mirrors how IAM already issues
tokens at password login (server-side), so the OAuth path reuses the entire back
half of login: resolve account → mint identity token → into tenant selection.

### D2 — CSRF (`state`) and PKCE are mandatory

`/start` generates a random `state` and a PKCE `code_verifier`/`code_challenge`,
stores them server-side keyed by `state` with a short TTL, and includes them in
the redirect. `/callback` rejects a missing/unknown/expired `state` and sends the
`code_verifier` in the token exchange. This blocks CSRF login and authorization-
code interception.

### D3 — Match-or-create precedence and the auto-link rule

```
  1. google_sub matches an account            ─▶ log in (returning user)
  2. else email matches AND Google email_verified ─▶ link google_sub, log in
  3. else                                       ─▶ auto-provision new account
```

The **only** way a Google identity attaches to a *pre-existing* account is step 2,
gated on Google's `email_verified=true`. Because Google has proven ownership of
the address, letting it claim the matching account is safe and is the expected UX
("I signed up with my email, now I click Login with Gmail and it's the same
account"). An **unverified** Google email never reaches step 2 — it falls to step
3 or is refused — so it cannot hijack an account by mere address collision. This
is the single sharpest edge in the whole auth redesign and is isolated to one
branch.

### D4 — Auto-provision = a 0-tenant account

Step 3 creates a `"user"` with: generated username, the Google email
(`email_verified=true`), `password_hash = NULL`, `google_sub` set, and **no**
`user_tenant_role`. Returns an identity token. The user lands on the 0-tenant
empty state ([[public-signup-tenant-tokens]]) until invited into a tenant. This is
only possible because that change already decoupled account existence from
membership.

### D5 — `password_hash` nullable; passwordless accounts are valid

```sql
ALTER TABLE "user" ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE "user" ADD COLUMN google_sub VARCHAR(255);
CREATE UNIQUE INDEX user_gsub_uniq
  ON "user" (google_sub) WHERE google_sub IS NOT NULL;
```

A Google-only user has `password_hash IS NULL`. The password-login path MUST
treat a null hash as "no password set" → `INVALID_CREDENTIALS` (still running a
dummy verify to stay timing-safe), never as a crash or a bypass. A user can hold
both a password and a linked Google account.

### D6 — Verify Google's ID token properly

IAM MUST verify the ID token's signature against Google's JWKS (fetched and
cached, honouring rotation), and check `aud == GOOGLE_CLIENT_ID`,
`iss ∈ {accounts.google.com, https://accounts.google.com}`, and expiry. Trusting
unverified token contents would let a forged token mint an IAM session.

## Risks / Trade-offs

- **Auto-link is convenient but sensitive.** Safe only because it is gated on
  Google `email_verified`. If the client prefers zero implicit linking, the
  documented alternative is an explicit settings-page link step + auto-provision
  only on no-match.
- **External dependency on Google availability** for that login method;
  email/password login is unaffected when Google is down.
- **JWKS fetch/caching** adds a network dependency in the callback; cache with a
  sane TTL and fail closed (reject the login) on verification failure.
- **Secret custody**: `GOOGLE_CLIENT_SECRET` must live only in IAM's environment,
  never in the web bundle.

## Verified code anchors (from live source)

Verified against `apps/backend/services/iam-service` and `libs/common-auth`:

- **`"user"` table** (created in `V1__init.sql`) has `password_hash TEXT NOT NULL`
  and no `google_sub`. Migration file is `V8__*.sql` (after `V6` from Change A and
  `V7` from Change B).
- **`domain.rs::User.password_hash: String`** is non-optional → must become
  `Option<String>`; `repo.rs::map_user()` reads `row.get("password_hash")` and
  must read an `Option`. (Change A already turns `email` optional; this change
  does the same for `password_hash`.)
- **`commands.rs::login()`** calls
  `verify_password(&validated.password, &user.password_hash)`, passing a `&str`.
  With a nullable hash this must guard: if `password_hash` is `None`, run
  `verify_dummy()` (already imported from `common_auth::password`) and return the
  existing `invalid_credentials()` — never unwrap a `None` hash.
- **Token issuance**: a Google login produces an **identity token**, so it reuses
  the `issue_identity_token` path added in [[public-signup-tenant-tokens]] (not
  `issue_tokens`, which requires a tenant).
- **User creation**: auto-provisioning needs the tenant-less user insert added in
  [[public-signup-tenant-tokens]] (the legacy `insert_with_role` always writes a
  `user_tenant_role`). Auto-link updates an existing row to set `google_sub`.
- **New repo methods**: `find_by_google_sub`, plus an update to set `google_sub`
  on an existing user (for auto-link).

## Migration Plan

1. IAM migration `V8__*.sql`: add `google_sub` (+ partial unique index), and
   `ALTER COLUMN password_hash DROP NOT NULL`. Change `domain.rs::User.password_hash`
   to `Option<String>` and update `map_user`.
2. OAuth client module: `/start` (state+PKCE), `/callback` (code exchange + ID
   token verify via JWKS).
3. `commands.rs`: match-or-create/link (D3), auto-provision (D4); harden password
   login for null hashes (D5).
4. `common-auth`: issue an identity token on the OAuth success path.
5. Config: `GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI` in env (+ `.env.example`).
6. Web: "Login with Gmail" buttons → `/auth/google/start`; return funnels into the
   existing tenant-selection flow.
7. Docs: sequence diagram (Google path), domain model, ERD, component, API.

## Open Questions

- Auto-link by verified email (default on) vs explicit settings-page linking.
- Auto-provision on first Google login (default on) vs refuse-until-invited.
- JWKS cache TTL and behaviour on Google key rotation.
