## 1. Token model (`common-auth`)

- [x] 1.1 Add a separate identity-claims type (e.g. `IdentityClaims { sub, typ:"identity", iat, exp, jti }`); keep the existing tenant-mandatory `Claims { sub, tenant_id, role, ... }` strict and add `typ:"access"` to it
- [x] 1.2 Add `issue_identity(user_id, ttl)` alongside the existing `issue(user_id, tenant_id, role, ttl)` (which must NOT be reused for identity tokens since `tenant_id` is mandatory)
- [x] 1.3 Add an identity-token extractor/verification; ensure tenant-less routes accept identity tokens and tenant-scoped routes reject them (and vice versa)
- [x] 1.4 Unit-test: an identity token is rejected on a tenant-scoped extractor and vice versa

## 2. Data model & migration (`iam-service`)

- [x] 2.1 Migration `V7__*.sql`: `ALTER TABLE refresh_token ADD COLUMN tenant_id UUID NOT NULL` (table from `V1__init.sql`, PK `(user_id, jti)`)
- [x] 2.2 Migration: `ALTER TABLE "user" ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT false`
- [x] 2.3 Extend `RefreshTokenRepo::insert/find/revoke` to carry `tenant_id` (keep PK `(user_id, jti)`)
- [ ] 2.4 Verify migration against a populated test database; existing refresh rows are invalidated cleanly (re-login)

## 3. Login & tenant selection (`iam-service`)

- [x] 3.1 Add a tenant-less issuance path (e.g. `issue_identity_token`) that does NOT call `resolve_membership`; modify `commands.rs::login()` to return an identity token via it
- [x] 3.2 Add `GET /my-tenants` (identity-token auth) backed by `UserRepo::list_memberships` joined with tenant names; empty for 0-tenant users
- [x] 3.3 Add `POST /tenants/{id}/enter` (identity-token auth): verify membership via `user_tenant_role`, then mint a tenant-scoped token using the existing `issue_tokens`/`resolve_membership` path scoped to `{id}`; `403` if not a member
- [x] 3.4 Modify `commands.rs::refresh()` to rotate within the refresh token's bound `tenant_id` (it currently re-derives tenant via `issue_tokens`→`resolve_membership`, which breaks for multi-tenant users)
- [x] 3.5 Add an identity-token envelope in `http.rs` (the existing `token_envelope` emits `meta.tenant_id/role` and is for tenant-scoped tokens only)
- [x] 3.6 Ensure `queries.rs::get_me` works under an identity token and tolerates `email = null`; add `username` + `email_verified` to `MeProfile`

## 4. Public signup (`iam-service`)

- [x] 4.1 Add a NEW public signup command — do NOT reuse `register_user` (that name is the existing internal tenant-scoped creator). Use e.g. `public_register(SignupInput)` + route `POST /auth/register`: create user (email + password + optional/auto username) with **no** tenant membership; return identity token
- [x] 4.2 Add a tenant-less user insert (the existing `insert_with_role` always writes a `user_tenant_role`; signup needs a user-only insert)
- [x] 4.3 Set `email_verified=false`; send verification email when `EMAIL_PROVIDER` configured (verify-later policy)
- [ ] 4.4 Add rate limiting to `/auth/register`
- [x] 4.5 Reject duplicate email (case-insensitive) with `EMAIL_ALREADY_EXISTS`

## 5. Web (`web-auth-onboarding`)

- [x] 5.1 Signup page → `POST /auth/register`; Zod schema (email, password, optional username)
- [x] 5.2 After any login, call `GET /my-tenants`; implement the 0 / 1 / N branching
- [x] 5.3 Single-tenant fast path: auto-call `/enter` and proceed into the app
- [x] 5.4 Tenant picker for N memberships; "switch school" re-calls `/enter`
- [x] 5.5 0-tenant empty state ("You're not part of any school yet")
- [x] 5.6 Update auth guards/routing: identity-token-only (no tenant entered) reaches tenant-less routes only; tenant-scoped pages require a scoped token
- [x] 5.7 Store/sense both token types; refresh uses the scoped token's tenant

## 6. Tests

- [x] 6.1 Login returns an identity token (no tenant/role claims)
- [x] 6.2 `/my-tenants` returns 0, 1, and N memberships correctly
- [x] 6.3 `/enter` issues a scoped token for a member; `403` for a non-member
- [x] 6.4 Refresh rotates within the bound tenant; cannot cross tenants
- [x] 6.5 `/auth/register` creates a usable 0-tenant account and returns an identity token
- [x] 6.6 A tenant-scoped route rejects an identity token
- [x] 6.7 e2e: register → (0-tenant state) → get invited → accept → enter → app

## 7. Docs

- [x] 7.1 Update login sequence diagram, IAM domain model, ERD (`refresh_token`), component diagram, and API contract (covered by the shared doc-update task)
