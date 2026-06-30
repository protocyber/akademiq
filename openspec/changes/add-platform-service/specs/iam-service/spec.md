## ADDED Requirements

### Requirement: Platform-admin role

iam-service SHALL define a `platform_admin` role distinct from the existing
tenant-scoped roles. This role designates a cross-tenant platform operator and MUST
NOT be granted through tenant membership. The pre-existing `super_admin` role
(currently labeled "Platform super admin" but only granted `academic.config.*`
within a tenant) is left unchanged and is NOT the operator role.

#### Scenario: platform_admin is seeded as a system role

- **WHEN** iam-service migrations run
- **THEN** a `platform_admin` role exists and is not associated with any tenant

#### Scenario: super_admin remains tenant-scoped

- **WHEN** the role catalog is inspected
- **THEN** `super_admin` retains its existing tenant-scoped permissions and is not
  treated as the platform operator role

### Requirement: Operator login and refresh endpoints

iam-service SHALL expose endpoints to authenticate a platform operator and to
refresh a platform session, issuing `typ:"platform"` tokens as defined by the
`platform-operator-auth` capability.

#### Scenario: Operator login endpoint

- **WHEN** a `platform_admin` account authenticates at the operator login endpoint
- **THEN** iam-service returns a `typ:"platform"` access token (no `tenant_id`) and
  a platform refresh token

#### Scenario: Operator refresh endpoint

- **WHEN** a valid platform refresh token is presented
- **THEN** iam-service rotates it and returns a new `typ:"platform"` access token

### Requirement: Token-type verification in common-auth

The `common-auth` verifier used by iam-service SHALL expose and enforce the
expected token `typ`, so callers can require a specific plane. iam-service's
tenant-scoped routes MUST reject `typ:"platform"` tokens.

#### Scenario: Tenant route rejects platform token

- **WHEN** a `typ:"platform"` token is presented to an existing tenant-scoped
  iam-service route
- **THEN** the request is rejected with `401`/`403`

### Requirement: Operator creation via CLI only

iam-service SHALL NOT seed any platform-operator account through migrations.
Operator accounts are created exclusively via the `akademiq platform
create-operator` CLI command, which takes the email and password as parameters,
hashes the password with `common-auth::hash_password`, grants `platform_admin`, and
creates the account with zero tenant memberships. The command MUST NOT print the
password or password hash and MUST exit non-zero when no account is created (e.g.
the email already exists).

#### Scenario: Create operator via CLI

- **WHEN** `akademiq platform create-operator` is run with a new email and password
- **THEN** an operator account is created with `platform_admin` and no tenant
  membership, and the command prints the operator identifier but no secret

#### Scenario: No migration-seeded operator

- **WHEN** iam-service migrations run on a fresh database
- **THEN** no platform-operator account exists until one is created via the CLI

#### Scenario: Duplicate operator email is a no-op failure

- **WHEN** the CLI is run with an email that already exists
- **THEN** no account is created and the command exits non-zero

### Requirement: Force-revoke tenant refresh tokens on suspension

iam-service SHALL consume the `tenant.suspended` event and immediately revoke all
active refresh tokens scoped to that `tenant_id`. Revocation MUST be limited to the
suspended tenant (a user's sessions in other tenants are unaffected) and MUST be
idempotent so a re-delivered `tenant.suspended` event is a no-op. iam-service does
not attempt to invalidate already-issued stateless access tokens; those expire
naturally within the access-token TTL.

#### Scenario: Refresh tokens revoked on suspend

- **WHEN** a `tenant.suspended` event is consumed for `tenant_id` T
- **THEN** all active refresh tokens scoped to T are revoked, and a subsequent
  refresh attempt with one of them is rejected

#### Scenario: Other tenants unaffected

- **WHEN** a user belongs to tenant T (suspended) and tenant U (active)
- **THEN** revocation removes only the T-scoped refresh token; the U-scoped session
  remains valid

#### Scenario: Re-delivered suspend event is idempotent

- **WHEN** the same `tenant.suspended` event is delivered more than once
- **THEN** the second delivery revokes nothing further and does not error
