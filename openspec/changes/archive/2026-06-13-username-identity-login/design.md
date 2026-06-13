## Context

The IAM `"user"` table currently encodes `email` as the identity:
`email VARCHAR(320) UNIQUE NOT NULL`, with `password_hash TEXT NOT NULL`. The
login command (`commands.rs`) calls a `find_by_email` repository method and
verifies the Argon2id hash. This design assumes every user has exactly one real
email. A client requirement — email-less teachers/parents who log in by username
— invalidates that assumption and forces username to become the primary,
always-present identity.

This is the foundation change; [[public-signup-tenant-tokens]] and
[[google-oauth-login]] both depend on "an account can exist without an email."

## Goals

- Username is `NOT NULL`, globally unique, case-insensitive, auto-generated when
  absent.
- Email is nullable and unique-if-present (case-insensitive).
- Login works by email **or** username from a single identifier field, with no
  ambiguity.
- The migration is safe against the existing populated database.
- No fake/synthetic email values anywhere.

## Decisions

### D1 — Honest NULL email, not a synthetic domain

`email` becomes `NULL` for users without one. Rejected alternative: synthesize
`<slug>@akademiq.test`. The `.test` TLD is RFC 6761-reserved and unroutable, so
it can never reach a real inbox — but the cost isn't deliverability, it's that
every query and every email-sending code path must *know* the address is fake.
A `NULL` is self-documenting and short-circuits delivery via
`WHERE email IS NOT NULL`. The only legitimate reason to keep a synthetic email
is an external system with a hard, unchangeable `NOT NULL` email requirement —
we own the entire IAM schema, so that reason does not apply.

### D2 — Partial unique index for nullable email

```sql
ALTER TABLE "user" ALTER COLUMN email DROP NOT NULL;
DROP INDEX  IF EXISTS user_email_key;            -- old plain UNIQUE
CREATE UNIQUE INDEX user_email_uniq
  ON "user" (lower(email)) WHERE email IS NOT NULL;
```

Postgres treats `NULL`s as distinct, so many email-less users coexist while real
addresses stay unique. `lower(email)` makes uniqueness case-insensitive, closing
the `Fitrah@x.com` vs `fitrah@x.com` duplicate-account gap.

### D3 — Username column + uniqueness

```sql
ALTER TABLE "user" ADD COLUMN username VARCHAR(64);        -- nullable first
-- ... backfill (see D4) ...
ALTER TABLE "user" ALTER COLUMN username SET NOT NULL;
CREATE UNIQUE INDEX user_username_uniq ON "user" (lower(username));
```

Global uniqueness (not per-tenant) was chosen deliberately: a user can belong to
many tenants ([[public-signup-tenant-tokens]]), so a per-tenant username would be
ambiguous at login time when the tenant isn't yet known. Login happens *before*
tenant selection in the two-token model, so the username must be globally
resolvable on its own.

### D4 — Three-step migration for the populated table

A single `ADD COLUMN username VARCHAR NOT NULL` would fail on existing rows.
The migration runs inside one transaction:

1. `ADD COLUMN username VARCHAR(64)` (nullable).
2. Backfill: for each existing row, generate a unique slug
   (`adjective-noun-NNNN`), retrying on collision. Existing users keep their
   email; the generated username is an *additional* login handle they can change
   later.
3. `ALTER COLUMN username SET NOT NULL` + create the unique index.

Backfill slug generation in SQL uses a deterministic seed from `user_id` plus a
collision-retry loop in the migration script, so the result is reproducible and
free of `Math.random`-style nondeterminism.

### D5 — `@` as the email/username discriminator

The login identifier is classified by a single rule: **contains `@` → email,
else → username**. To keep this total and unambiguous, usernames forbid `@`
(validation + a CHECK-style guard). This avoids a two-query "try email, then
username" fallback (which would leak existence via timing and double the lookup
cost) in favour of one deterministic path.

```
  identifier ──contains '@'?──┬── yes ──▶ WHERE lower(email)    = lower($1)
                              └── no  ──▶ WHERE lower(username) = lower($1)
```

### D6 — Preserve timing-safe auth

The existing login already runs a dummy Argon2 verify on user-not-found to mask
email existence. The username path MUST do the same: a missing username performs
the same dummy verification and returns the identical `INVALID_CREDENTIALS`
envelope, so neither username nor email enumeration is possible via timing or
error differences.

## Risks / Trade-offs

- **Field rename breaks API consumers** sending `{ "email": ... }` to
  `/auth/login`. Mitigated by the system being pre-GA with the web client
  updated in lockstep. Dual-accept is the fallback if an external consumer
  surfaces.
- **Backfilled usernames are opaque** to existing users until they customise
  them. Acceptable: those users continue logging in by email; the username is a
  latent capability, not a forced change.
- **Username reuse on change** could let a new user grab a freed handle that
  stale references still point at. Accepted for a school-scoped system; a
  reservation window is the documented escape hatch.

## Verified code anchors (from live source)

These are the exact symbols this change touches (verified against
`apps/backend/services/iam-service` and `libs/common-auth`):

- **Migration**: next file is `migrations/V6__*.sql` (existing: `V1__init.sql` …
  `V5__outbox.sql`). The `"user"` table is created in `V1__init.sql` with
  `email VARCHAR(320) NOT NULL` and `CONSTRAINT user_email_unique UNIQUE (email)`
  — both must be altered.
- **`domain.rs::User`** — fields `email: String` and `password_hash: String` are
  non-optional today. `email` must become `Option<String>`. (`password_hash`
  stays `String` for this change; [[google-oauth-login]] makes it optional.)
  `repo.rs::map_user()` reads `row.get("email")` and must read an `Option`.
- **`repo.rs::UserRepo::find_by_email`** (the only lookup-by-credential method)
  — add `find_by_username` and/or `find_by_identifier`.
- **`commands.rs::login()`** calls `state.user_repo.find_by_email(&validated.email)`.
- **`commands.rs::validate_login()` / `ValidatedLogin` / `LoginInput`** — today
  `validate_login` lowercases the input and **rejects any value without `@`**
  ("email must be valid"). This is the exact gate to change: an identifier
  without `@` must be accepted as a username, not rejected.
- **`http.rs::LoginBody { email, password }`** — the request DTO; rename `email`
  → `identifier`.
- **`queries.rs::get_me` → `MeProfile`** — add `username` (and, in
  [[public-signup-tenant-tokens]], `email_verified`); `email` becomes nullable in
  the response.
- **Username generation** must also be wired into the two existing user-insert
  paths: `repo.rs::insert_with_role` (used by `register_user`) and
  `repo.rs::accept_with_user` (invitation acceptance) — both currently
  `INSERT INTO "user" (user_id, email, password_hash, full_name, status)` with no
  username column.
- **Web**: `apps/web/src/lib/schemas/login.ts` (`loginSchema`, field `email` with
  `.email()`; note it also has a `remember_device` boolean).

## Migration Plan

1. Ship the IAM migration (`V6__username_identity.sql`) implementing D2–D4.
2. Change `domain.rs::User.email` to `Option<String>`; update `map_user`,
   `get_me`/`MeProfile`, and `internal_create_user`'s `user.email` read.
3. Update `repo.rs` with `find_by_identifier` (and/or `find_by_username`),
   `commands.rs::login`/`validate_login` lookup, and username generation in
   `insert_with_role` + `accept_with_user`.
4. Update the web login schema + field.
5. Update IAM docs (ERD, domain model, sequence, component, API contract).
6. No data backfill beyond the migration; existing emails are untouched.

## Open Questions

- Reuse vs. reservation window for changed usernames (default: reuse).
- Rename vs. dual-accept on `/auth/login` (default: rename).
- Slug shape: `adjective-noun-NNNN` vs opaque (default: readable slug).
