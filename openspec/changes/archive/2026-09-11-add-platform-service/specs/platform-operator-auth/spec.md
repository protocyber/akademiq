## ADDED Requirements

### Requirement: Platform-operator account

The system SHALL support a platform-operator account that belongs to **no tenant**.
An operator account is an IAM user holding the `platform_admin` role and is not a
member of any tenant. Operator accounts MUST be distinguishable from tenant users
so that operator login and tenant login cannot be confused.

#### Scenario: Operator account has no tenant membership

- **WHEN** a platform-operator account is created
- **THEN** it holds the `platform_admin` role and has zero tenant memberships

#### Scenario: Operator account password security

- **WHEN** an operator password is stored
- **THEN** it is hashed with Argon2 via the existing `common-auth::hash_password`,
  never stored or logged in plaintext

### Requirement: Platform-operator login issues a platform token

The iam-service SHALL provide an operator login that, on valid credentials for a
`platform_admin` account, issues a **platform token** (`typ:"platform"`, no
`tenant_id`, with cross-tenant scope claims) and a matching platform refresh token,
reusing the existing RS256 signing and refresh-rotation machinery.

#### Scenario: Successful operator login

- **WHEN** a valid platform-operator submits credentials to the operator login
  endpoint
- **THEN** iam-service returns a `typ:"platform"` access token (no `tenant_id`) and
  a refresh token scoped to the operator, not to any tenant

#### Scenario: Non-operator cannot obtain a platform token

- **WHEN** a tenant user without `platform_admin` attempts operator login
- **THEN** iam-service rejects the request and issues no platform token

#### Scenario: Platform token refresh

- **WHEN** a platform refresh token is presented to the operator refresh endpoint
- **THEN** iam-service issues a new `typ:"platform"` access token and rotates the
  refresh token, without requiring tenant entry

### Requirement: Token-type isolation across services

`common-auth` SHALL validate the `typ` claim of every token, and services SHALL
reject tokens whose `typ` is not valid for that plane. Tenant-scoped services
(`iam`, `billing`, `academic-config`, `academic-ops`, `grading`) MUST reject
`typ:"platform"` tokens; platform-service MUST reject `typ:"access"`,
`typ:"identity"`, and `typ:"refresh"` tokens on its protected routes. Signature
validity alone MUST NOT grant access.

#### Scenario: Platform token rejected by tenant service

- **WHEN** a `typ:"platform"` token is presented to any `/api/v1/{iam|billing|academic-config|academic-ops|grading}` protected route
- **THEN** the service returns `401`/`403` and does not perform the operation, even
  though the signature is valid

#### Scenario: Tenant access token rejected by platform-service

- **WHEN** a `typ:"access"` token (tenant-scoped) is presented to a protected
  `/api/v1/platform` route
- **THEN** platform-service returns `401`/`403` and does not perform the operation

#### Scenario: Platform token accepted by platform-service

- **WHEN** a valid `typ:"platform"` token with `platform_admin` scope is presented
  to a protected `/api/v1/platform` route
- **THEN** platform-service authorizes the request

### Requirement: Platform token carries no tenant identity

A platform token MUST NOT contain a `tenant_id` claim, and platform-service MUST
NOT trust any client-supplied `tenant_id`; the target tenant for a command is taken
from the request path/body and validated against the projection.

#### Scenario: No tenant_id in platform token

- **WHEN** a platform token is decoded
- **THEN** it has `typ:"platform"` and no `tenant_id` claim
