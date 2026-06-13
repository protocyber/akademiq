## 1. Data model & migration (`iam-service`)

- [x] 1.1 Add migration `V6__username_identity.sql`: `ADD COLUMN username VARCHAR(64)` (nullable), backfill unique `adjective-noun-NNNN` slugs for all existing rows with collision retry, then `ALTER COLUMN username SET NOT NULL`
- [x] 1.2 Drop the existing `CONSTRAINT user_email_unique UNIQUE (email)` (from `V1__init.sql`); add partial unique index `user_email_uniq ON (lower(email)) WHERE email IS NOT NULL`
- [x] 1.3 `ALTER COLUMN email DROP NOT NULL` (currently `NOT NULL` in `V1__init.sql`)
- [x] 1.4 Add unique index `user_username_uniq ON (lower(username))`
- [x] 1.5 Add a CHECK or app-level guard that `username` does not contain `@`
- [x] 1.6 Change `domain.rs::User.email` to `Option<String>`; update `repo.rs::map_user` to read an optional email; verify `get_me`/`internal_create_user` email reads compile
- [x] 1.7 Verify migration runs cleanly against a seeded (populated) database in a test container

## 2. Username generation

- [x] 2.1 Implement a username slug generator (`adjective-noun-NNNN`) in IAM with a curated word list and a collision-retry loop against the unique index
- [x] 2.2 Unit-test: generator never returns a slug containing `@`, always satisfies the format rule, and resolves collisions
- [x] 2.3 Wire generation into every user-creation path that may omit a username (internal `/internal/users`, invitation acceptance) — leave an explicit `username` override path for callers that supply one

## 3. Repository & login command

- [x] 3.1 Add `find_by_username` and/or `find_by_identifier` to `repo.rs::UserRepo` (alongside the existing `find_by_email`); `find_by_identifier` routes on `@` presence to email vs username lookup
- [x] 3.2 Update `commands.rs::login()` to call the identifier lookup instead of `find_by_email`
- [x] 3.3 Rewrite `commands.rs::validate_login()`: it currently rejects any value without `@`; instead accept a non-empty identifier and classify (an identifier without `@` is a username, not an error)
- [x] 3.4 Preserve timing-safe behaviour: the existing `verify_dummy()` on not-found must run for BOTH paths; keep the identical `INVALID_CREDENTIALS` envelope from `invalid_credentials()`
- [x] 3.5 Rename `http.rs::LoginBody.email` → `identifier` and `commands.rs::LoginInput.email` → `identifier`

## 4. Web (`web-auth-onboarding`)

- [x] 4.1 Rename the login Zod schema field `email` → `identifier`; loosen `.email()` to `.min(1)` non-empty string
- [x] 4.2 Relabel the login form field to "Email or username"; update placeholder/help text
- [x] 4.3 Update the login mutation to send `{ identifier, password }`
- [x] 4.4 Update `applyServerFieldErrors` mapping if the field key changed

## 5. Tests

- [x] 5.1 IAM integration test: login by email succeeds (existing behaviour preserved)
- [x] 5.2 IAM integration test: login by username succeeds for an email-less user
- [x] 5.3 IAM integration test: unknown identifier (email-shaped and username-shaped) both return `INVALID_CREDENTIALS` with comparable timing
- [x] 5.4 IAM integration test: two users with `email IS NULL` can coexist; a duplicate real email (differing only in case) is rejected
- [x] 5.5 Web test: login schema accepts both an email and a bare username; rejects empty

## 6. Docs

- [x] 6.1 Update IAM ERD, domain model, login sequence diagram, component diagram, and API contract to reflect username identity + nullable email (covered by the shared doc-update task across the change set)
