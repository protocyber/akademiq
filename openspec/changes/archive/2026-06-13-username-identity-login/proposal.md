## Why

Today IAM treats **email as the sole login identity**: `user.email` is
`UNIQUE NOT NULL`, the login command looks users up by email, and every account
is assumed to have a real, deliverable address. A client requirement breaks that
assumption: some users (older teachers and parents) have **no email at all** and
must still be able to sign in. Those users are created by a tenant admin through
an invitation and need to log in with a **username + password**.

This change makes **username the universal identity** every user is guaranteed
to have, and demotes **email to an optional, unique-if-present contact and login
method**. It is the foundation for the two changes that follow
([[public-signup-tenant-tokens]] and [[google-oauth-login]]): both assume an
account can exist without an email, so the email-nullable + username-identity
migration lands here first.

We explicitly reject the "dummy `@akademiq.test` email" workaround: a synthetic
address is fake data in a real column that every email-sending path must learn
to special-case, and that future code will forget about and treat as real. An
honest `NULL` says exactly what is true — "this user has no email" — and
naturally short-circuits delivery (`WHERE email IS NOT NULL`).

## What Changes

### Data model (`iam-service`)

- **MODIFIED** `"user"` table:
  - **NEW** `username VARCHAR(64) NOT NULL` — globally unique, case-insensitive,
    auto-generated if not supplied. The one identity every user has.
  - `email VARCHAR(320)` — drop `NOT NULL`; becomes nullable.
  - Replace the plain `UNIQUE(email)` constraint with a **partial unique index**
    on `lower(email) WHERE email IS NOT NULL`, so multiple email-less users
    coexist (their `NULL`s don't collide) while real addresses stay globally
    unique and case-insensitive.
  - Add a unique index on `lower(username)` (global, case-insensitive).
- A migration backfills a generated `username` for every existing row before the
  `NOT NULL` constraint is applied, so the change is safe on a populated DB.

### Username rules

- **Auto-generation**: when a user is created without an explicit username
  (Google login, or an admin/registrant who leaves it blank), IAM generates a
  unique slug of the form `adjective-noun-NNNN` (e.g. `brave-otter-4821`).
  Generation retries on collision until a free slug is found.
- **Forbidden `@`**: usernames MUST NOT contain `@`. This keeps the login
  identifier unambiguous — an identifier containing `@` is always an email, one
  without is always a username (see login lookup below).
- **Format**: 3–64 chars, lowercase letters/digits/`-`/`_`, must start with a
  letter. Case-insensitive uniqueness.
- **Changeable**: a user MAY change their username later (settings, out of scope
  for this change's UI but the field is mutable). On change, the previous
  username is **freed for reuse** — acceptable for a school system; documented
  as a deliberate choice. *(Open decision — see below.)*

### Login (`iam-service`)

- **MODIFIED** `POST /auth/login`: the request field changes from `email` to a
  generic **`identifier`** (string). The lookup discriminates on `@`:
  - identifier **contains `@`** → look up by `lower(email)` (email path).
  - identifier **has no `@`** → look up by `lower(username)` (username path).
- Email-less users authenticate exclusively through the username path.
- Timing-safe behaviour is preserved: an unknown identifier still performs a
  dummy Argon2 verification so username/email existence cannot be probed via
  response timing, and the error stays the generic `INVALID_CREDENTIALS`.

### Web (`web-auth-onboarding`)

- **MODIFIED** login form: the single credential field is relabelled
  **"Email or username"** and its Zod schema loosens from `z.string().email()`
  to a non-empty string. The server remains the source of truth for the
  email-vs-username decision.

## Capabilities

### Modified Capabilities

- `iam-service`: the user data model gains a mandatory, globally-unique
  `username`; `email` becomes optional (unique-if-present); the login command
  authenticates by email **or** username, discriminated by the presence of `@`.
- `web-auth-onboarding`: the login screen accepts an email-or-username
  identifier instead of an email-only field.

## Impact

- **Migration risk (medium)**: adding `username NOT NULL` to a populated table
  requires a backfill before the constraint is enforced. The migration runs in
  three steps — add nullable column, backfill unique slugs, then enforce
  `NOT NULL` + unique index — inside one transaction.
- **Affected code**: IAM `repo.rs` (`find_by_email` → add `find_by_username`
  / `find_by_identifier`), `commands.rs` (login lookup), user-creation paths
  (username generation), the `login.ts` Zod schema and login page field.
- **Docs**: IAM ERD, domain model, login sequence diagram, component diagram,
  and the IAM API contract all describe email-as-identity and must be updated
  (handled alongside this change set — see the doc-update task).
- **Backward compatibility**: existing API consumers sending `{ "email": ... }`
  to `/auth/login` will break when the field is renamed to `identifier`. Since
  the system is pre-GA and the web client is updated in lockstep, we rename
  rather than dual-accept. *(Open decision — see below.)*

## Open Decisions (defaults chosen, confirm before build)

1. **Username reuse on change** — default: **freed for reuse** immediately.
   Alternative: reserve a recently-released username for N days to avoid a new
   user impersonating an old handle. Chosen default favours simplicity.
2. **`/auth/login` field rename vs. dual-accept** — default: **rename**
   `email` → `identifier` (clean break, pre-GA). Alternative: accept both
   `identifier` and legacy `email` for one release.
3. **Auto-generated username shape** — default: `adjective-noun-NNNN`.
   Alternative: opaque `u_<base32>`.
