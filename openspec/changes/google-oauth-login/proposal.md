## Why

Users want a "Login with Gmail" button. The client originally suggested Supabase,
but AcademiQ already runs a complete identity provider (the Rust IAM service:
Argon2id, RS256 JWT, refresh-token rotation). Supabase's value is "auth so you
don't build it" — but it is already built, so adding Supabase would mean running a
**second** identity provider and reconciling two token formats. Instead we
implement **Google OAuth directly in IAM**: IAM remains the single source of
truth and the sole token issuer; Google is just the mechanism that proves an email.

This builds on [[public-signup-tenant-tokens]]: a Google login is simply another
way to obtain an **identity token**. Because account existence is already
decoupled from tenants, a first-time Google user can be auto-provisioned with no
tenant — exactly like a public signup — and gain memberships later via invitation.
It also builds on [[username-identity-login]]: Google users get an auto-generated
username and a `NULL` password.

## What Changes

### Data model (`iam-service`)

- **MODIFIED** `"user"`:
  - **NEW** `google_sub VARCHAR(255)` — Google's stable subject id, unique when
    present (partial unique index `WHERE google_sub IS NOT NULL`).
  - `password_hash` becomes **nullable** — a Google-only user has no password.
    (Combined with [[username-identity-login]] making `email` nullable, a row may
    authenticate by password, by Google, or both.)

### Google OAuth flow (`iam-service`, backend-completed)

- **NEW `GET /auth/google/start`** — public. Generates a `state` (CSRF) value and
  a PKCE pair, stores them server-side keyed by `state`, and `302`-redirects to
  Google's consent screen.
- **NEW `GET /auth/google/callback`** — public. Validates `state`, exchanges the
  authorization `code` for tokens using `GOOGLE_CLIENT_SECRET` **server-side**,
  verifies the Google **ID token** (signature, `aud`, `iss`, expiry), and extracts
  `{ google_sub, email, email_verified }`. The browser never sees Google's tokens
  or the client secret. On success IAM issues an **identity token** (same as any
  login) and redirects back to the web app.

### Match-or-create + account linking (`iam-service`)

The callback resolves the Google identity to an account in this precedence:

1. **By `google_sub`** — a returning Google user → log in.
2. **By verified email** — Google reports a verified email matching an existing
   account → **auto-link**: store `google_sub` on that account and log in. Because
   Google has *proven* ownership of the email, this is safe and means a user who
   first registered with email+password can later "Login with Gmail" into the
   **same** account (Google becomes an added login method).
3. **No match** — **auto-provision** a new account: generated username, the Google
   email (with `email_verified=true`), `password_hash = NULL`, `google_sub` set,
   and **no tenant membership**. Returns an identity token; the user lands on the
   0-tenant empty state until invited.

IAM MUST only auto-link on a Google-`email_verified=true` claim. An unverified
Google email MUST NOT silently claim an existing account.

### Web (`web-auth-onboarding`)

- **NEW "Login with Gmail" button** on the login (and signup) screen that navigates
  to `GET /auth/google/start`. On return, the client holds an identity token and
  enters the standard tenant-selection flow from
  [[public-signup-tenant-tokens]] (0 / 1 / N branching).

### Configuration

- **NEW env**: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`.
  The client secret lives only in the IAM service; it is never exposed to the
  browser.

## Capabilities

### Modified Capabilities

- `iam-service`: adds Google OAuth start/callback endpoints, the `google_sub`
  column with auto-link-by-verified-email and auto-provisioning, and makes
  `password_hash` nullable so passwordless (Google-only) accounts are valid.
- `web-auth-onboarding`: adds the "Login with Gmail" entry point that funnels into
  the existing identity-token → tenant-selection flow.

## Impact

- **No second identity provider.** Supabase is explicitly not adopted; IAM stays
  the only token issuer, so roles, multi-tenancy, refresh rotation, and RS256 are
  untouched. Google plugs in only at the "prove an email" step.
- **New external dependency**: Google OAuth endpoints + an ID-token verification
  path (JWKS fetch/caching for Google's signing keys).
- **Security-sensitive surfaces**: `state`/PKCE handling (CSRF + code interception),
  server-side secret custody, and the verified-email auto-link rule (the one place
  a Google identity can attach to an existing account).
- **Affected code**: IAM migration (`google_sub`, `password_hash` nullable),
  `commands.rs` (match-or-create/link), new OAuth handlers in `http.rs`, an
  OAuth/JWKS client module, `common-auth` (issue identity token for OAuth path);
  web login/signup buttons.
- **Docs**: login sequence diagram (add Google path), IAM domain model, ERD
  (`google_sub`, nullable `password_hash`), component diagram (token provider now
  includes external OIDC), API contract.

## Open Decisions (defaults chosen, confirm before build)

1. **Auto-link by verified email** — default: **enabled** (Google-verified email
   silently links to an existing account). Alternative: require an explicit
   "link your Google account" step from settings; auto-provision only when no
   match.
2. **Browser-completed vs backend-completed OAuth** — default: **backend-completed**
   (client secret stays server-side, mirrors how IAM already issues tokens).
3. **Auto-provision on first Google login** — default: **enabled** (creates a
   0-tenant account). Alternative: refuse unknown Google emails and require an
   invitation/registration first.
