## ADDED Requirements

### Requirement: Login SHALL issue a tenant-less identity token

On successful authentication, `POST /auth/login` MUST issue an **identity token**
whose claims are `{ sub, typ: "identity", iat, exp, jti }` with no `tenant_id` and
no `role`. The identity token MUST be short-lived (default 10 minutes) and MUST
NOT have an associated refresh token. It authorizes only tenant-less endpoints
(`GET /me`, `GET /my-tenants`, `POST /tenants/{id}/enter`, invitation acceptance).

#### Scenario: Login yields an identity token

- **WHEN** a user authenticates successfully via any login method
- **THEN** IAM returns an identity token carrying `typ:"identity"` and no
  `tenant_id`/`role` claim

#### Scenario: Identity token is rejected on tenant-scoped routes

- **WHEN** an identity token is presented to an endpoint that requires tenant
  scope
- **THEN** IAM rejects the request as unauthenticated for that route

### Requirement: Users SHALL list and enter their tenants

IAM MUST expose `GET /my-tenants`, authenticated by an identity token, returning
the caller's memberships as `[{ tenant_id, tenant_name, role_code }]` (empty when
the user belongs to no tenant). IAM MUST expose `POST /tenants/{id}/enter`,
authenticated by an identity token, which verifies the caller is a member of
`{id}` via `user_tenant_role` and then issues a **tenant-scoped** access token
(`{ sub, tenant_id, role, typ:"access" }`) plus a tenant-scoped refresh token.
`/enter` is the only endpoint that mints a tenant-scoped token.

#### Scenario: Member enters a tenant

- **WHEN** a user with membership in tenant `T` calls `POST /tenants/T/enter`
  with a valid identity token
- **THEN** IAM returns a tenant-scoped token envelope with `tenant_id = T` and the
  user's role in `T`

#### Scenario: Non-member is refused

- **WHEN** a user without membership in tenant `T` calls `POST /tenants/T/enter`
- **THEN** IAM responds `403 FORBIDDEN` and issues no token

#### Scenario: Zero-tenant user lists no memberships

- **WHEN** a user who belongs to no tenant calls `GET /my-tenants`
- **THEN** IAM returns an empty array and the user remains on an identity token

### Requirement: Anyone SHALL be able to self-register an account

IAM MUST expose a public, rate-limited `POST /auth/register` that creates a
`"user"` from email + password (and an optional username, auto-generated when
absent) with **no** tenant membership, and returns an identity token. Account
existence MUST NOT require a tenant. The account is created with
`email_verified=false`; a verification email is sent when an email provider is
configured, and the account is usable before verification (verify-later).

#### Scenario: Public signup creates a tenant-less account

- **WHEN** a visitor submits a valid email + password to `POST /auth/register`
- **THEN** IAM creates a user with no `user_tenant_role` rows and returns an
  identity token

#### Scenario: Duplicate email is rejected

- **WHEN** registration is attempted with an email that already exists
  (case-insensitive)
- **THEN** IAM responds `EMAIL_ALREADY_EXISTS` (409) and creates no account

## MODIFIED Requirements

### Requirement: Refresh tokens SHALL be scoped to a tenant

A refresh token MUST be bound to `(user_id, jti, tenant_id)`. `POST /auth/refresh`
MUST re-issue a tenant-scoped access token for the refresh token's bound tenant
and MUST NOT change the tenant. Switching tenants is performed by
`POST /tenants/{id}/enter`, which mints a new tenant-scoped refresh token rather
than mutating an existing one.

#### Scenario: Refresh stays within its tenant

- **WHEN** a refresh token bound to tenant `T` is used at `POST /auth/refresh`
- **THEN** IAM issues a new access token scoped to `T` and rotates the refresh
  token within `T`

#### Scenario: Switching tenants requires re-entering

- **WHEN** a user holding a token scoped to tenant `T` wants to act in tenant `U`
- **THEN** the user must call `POST /tenants/U/enter` (with an identity token) to
  obtain a `U`-scoped token; refresh alone cannot cross from `T` to `U`

### Requirement: GET /me SHALL work without a tenant and tolerate a null email

`GET /me` MUST be reachable with an identity token (no tenant entered) and MUST
return the user's profile and memberships. The `email` field MAY be `null` for
users without an email.

#### Scenario: Me under an identity token

- **WHEN** a user calls `GET /me` with an identity token
- **THEN** IAM returns their profile and membership list without requiring a
  tenant scope

#### Scenario: Me for an email-less user

- **WHEN** a user without an email calls `GET /me`
- **THEN** the response includes `email: null` and the rest of the profile
