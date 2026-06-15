## 0. Prerequisite

- [ ] 0.1 Confirm the existing-account accept path (`accept_for_existing_user`) is already passwordless and must remain unchanged
- [ ] 0.2 Confirm OAuth/identity login paths do not depend on a non-null `password_hash`

## 1. Backend — schema (iam-service)

- [ ] 1.1 Migration: make `user.password_hash` nullable (Decision A); backfill not required
- [ ] 1.2 Migration: create set-password token store (`user_id`, hashed token, `expires_at`, `consumed_at`) with the needed unique/index
- [ ] 1.3 Update IAM ERD docs in `docs/internal/10_data_design/`

## 2. Backend — passwordless accept (iam-service)

- [ ] 2.1 Add `accept_without_password` repo path mirroring `accept_with_user` minus the hash (insert user with NULL `password_hash`)
- [ ] 2.2 Relax `validate_accept_invitation` so `password`/`full_name` are optional on the new-account path; keep length check when a password IS provided
- [ ] 2.3 Resolve `full_name` fallback (invitation record → placeholder) when not provided
- [ ] 2.4 Issue a set-password token on passwordless account creation
- [ ] 2.5 Keep `issue_scoped_tokens` so the invitee is signed in immediately

## 3. Backend — password-not-set guard (iam-service)

- [ ] 3.1 Reject password login on a NULL-hash account with `PASSWORD_NOT_SET` (distinct, actionable code)
- [ ] 3.2 Ensure generic invalid-credentials messaging is not used for this case

## 4. Backend — set-password flow (iam-service)

- [ ] 4.1 Add `POST /api/v1/iam/auth/set-password` accepting `{ password, token? }`
- [ ] 4.2 Accept proof via single-use set-password token OR an authenticated no-password session
- [ ] 4.3 Validate password strength (min 8), `hash_password`, persist, mark password set, consume token
- [ ] 4.4 Reject consumed/expired tokens

## 5. Backend — tests & docs (iam-service)

- [ ] 5.1 Test: button-only accept creates a passwordless account + grants roles + issues session
- [ ] 5.2 Test: existing-account accept path unchanged
- [ ] 5.3 Test: password login blocked with `PASSWORD_NOT_SET` until a password is set
- [ ] 5.4 Test: set-password happy path (token and session), single-use, expiry, weak-password rejection
- [ ] 5.5 Update auth/invitation contracts in `docs/internal/11_integration_contracts/`
- [ ] 5.6 Run `make test` for iam-service

## 6. Web — button-only accept + set-password (apps/web) — AFTER backend

- [ ] 6.1 Replace the accept-invitation form with a single "Terima Undangan" button calling accept with just the token
- [ ] 6.2 Add a banner/CTA routing a no-password user to the set-password screen
- [ ] 6.3 Add a set-password screen consuming the token (or session), validating client-side, calling the endpoint
- [ ] 6.4 Handle `PASSWORD_NOT_SET` on the login page by routing to set-password
- [ ] 6.5 `pnpm lint` + `pnpm build` (or typecheck) pass; manually verify the end-to-end flow
