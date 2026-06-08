## ADDED Requirements

### Requirement: IAM service SHALL expose authentication endpoints under `/api/v1/iam`

The service MUST provide `POST /auth/login`, `POST /auth/refresh`, and
`POST /auth/logout` under the path prefix `/api/v1/iam`. All endpoints
MUST follow the success envelope `{ "data", "meta" }` and the error
envelope `{ "error": { "code", "message" } }` defined in
`13_engineering_standards/03_api_conventions.md`.

#### Scenario: Successful login returns access and refresh tokens

- **WHEN** a client POSTs valid email and password to `/api/v1/iam/auth/login`
- **THEN** the response is HTTP 200 with body `{ "data": { "access_token", "refresh_token", "expires_in" }, "meta": {} }` where `access_token` is an RS256 JWT, `expires_in` is `900`, and `refresh_token` is an opaque string

#### Scenario: Invalid credentials return a uniform error

- **WHEN** a client POSTs login with an unknown email or wrong password
- **THEN** the response is HTTP 401 with body `{ "error": { "code": "INVALID_CREDENTIALS", "message": "..." } }` and no information distinguishing "email not found" from "wrong password"

#### Scenario: Refresh exchanges a valid refresh token for a new access token

- **WHEN** a client POSTs a valid refresh token to `/api/v1/iam/auth/refresh`
- **THEN** the response is HTTP 200 with a fresh access token and a rotated refresh token, and the previous refresh token's `(user_id, jti)` row is marked revoked

#### Scenario: Logout revokes the active refresh token

- **WHEN** an authenticated client POSTs to `/api/v1/iam/auth/logout` with the current refresh token
- **THEN** the refresh token row is deleted and any subsequent refresh attempt with that token returns HTTP 401 `INVALID_REFRESH_TOKEN`

### Requirement: Passwords SHALL be hashed with Argon2id

User passwords MUST be hashed with Argon2id using parameters of at least
`m=19456` (19 MiB), `t=2`, `p=1`. The plaintext password MUST NOT be
logged, persisted, or returned in any response.

#### Scenario: New user password is hashed at write time

- **WHEN** a user record is created with a plaintext password
- **THEN** the persisted `user.password_hash` column starts with `$argon2id$` and the plaintext value never appears in logs, the database, or HTTP responses

#### Scenario: Login verifies via Argon2 verify

- **WHEN** a login request is processed
- **THEN** verification calls Argon2's constant-time verify against the stored hash, and timing differences between "user exists" and "user does not exist" paths are within 50 ms (measured in integration tests)

### Requirement: Access tokens SHALL be RS256 JWTs with tenant-scoped claims

Access tokens MUST be signed with RS256 using a private key held only by
the IAM service. The token payload MUST include `sub` (user id),
`tenant_id`, `role`, `iat`, `exp`, and `jti`. The expiry MUST be 15
minutes from issuance.

#### Scenario: Access token is verifiable by other services

- **WHEN** another service receives an access token and validates it using the IAM public key
- **THEN** the signature verifies, the `exp` claim is in the future, and the `tenant_id` and `role` claims are present and non-empty

#### Scenario: Tenant id in the body is ignored when JWT is present

- **WHEN** a request includes both an `Authorization: Bearer <jwt>` header and a `tenant_id` field in the body
- **THEN** handlers extract `tenant_id` from the JWT and ignore the body field, per `AGENTS.md`

### Requirement: Refresh tokens SHALL be stored as Argon2 hashes

The `refresh_token` table MUST store the Argon2 hash of the token, not
the plaintext. Each row MUST be keyed by `(user_id, jti)` and carry an
`expires_at` of 7 days from creation, plus `revoked_at` for explicit
revocation.

#### Scenario: Refresh table never contains plaintext

- **WHEN** a contributor inspects the `refresh_token` table after several logins
- **THEN** every `token_hash` column starts with `$argon2id$` and no row stores the original token value

#### Scenario: Expired tokens are rejected

- **WHEN** a client POSTs a refresh request with a token whose `expires_at` has passed
- **THEN** the response is HTTP 401 `EXPIRED_REFRESH_TOKEN` and no new tokens are issued

### Requirement: IAM SHALL expose an internal user-creation endpoint protected by a service secret

The endpoint `POST /api/v1/iam/internal/users` MUST be reachable only from
within the cluster network and MUST require an `X-Service-Token` header
matching the value of `IAM_INTERNAL_SERVICE_TOKEN`. The endpoint accepts
`{ email, password, tenant_id, role_code }` and returns the created
user's id.

#### Scenario: Valid internal call creates the user

- **WHEN** another service POSTs to `/internal/users` with a valid `X-Service-Token` and a unique email
- **THEN** the response is HTTP 201 `{ "data": { "user_id" }, "meta": {} }` and a `user` row plus a `user_tenant_role` row exist in `iam_db`

#### Scenario: Missing or wrong service token is rejected

- **WHEN** a client calls `/internal/users` without the `X-Service-Token` header or with an incorrect value
- **THEN** the response is HTTP 401 `UNAUTHORIZED_SERVICE_CALL` and no user is created

#### Scenario: Duplicate email returns a structured error

- **WHEN** the requested email already exists
- **THEN** the response is HTTP 409 `{ "error": { "code": "EMAIL_ALREADY_EXISTS", "message": "..." } }` and no user is created

### Requirement: IAM SHALL support a delete-user compensating endpoint

`DELETE /api/v1/iam/internal/users/{id}` MUST be available to support the
tenant-registration saga's compensating action. It MUST be idempotent
(deleting an already-deleted id returns success) and protected by the
same `X-Service-Token` header.

#### Scenario: Delete is idempotent

- **WHEN** another service DELETEs a user id twice in succession
- **THEN** both calls return HTTP 204 and the user no longer exists in `iam_db` after the first call

### Requirement: IAM SHALL seed system roles on first migration

IAM MUST seed the roles `super_admin`, `tenant_admin`, `teacher`,
`homeroom_teacher`, `student`, and `parent` into the `role` table as part
of the initial migration set. The `role.code` column SHALL be the
canonical identifier referenced by other services and MUST be unique.

#### Scenario: System roles exist after migrate

- **WHEN** a contributor runs `make migrate` against an empty `iam_db`
- **THEN** the `role` table contains exactly the six listed codes and any subsequent migrate run leaves them unchanged

### Requirement: `GET /api/v1/iam/me` SHALL return the authenticated user's profile and memberships

The endpoint MUST require a valid access token and return the user's id,
email, status, and a list of `(tenant_id, role_code)` pairs derived from
`user_tenant_role`.

#### Scenario: Authenticated user retrieves profile

- **WHEN** a client GETs `/api/v1/iam/me` with a valid access token
- **THEN** the response is HTTP 200 with `data: { user_id, email, status, memberships: [{ tenant_id, role_code }] }`

#### Scenario: Missing or invalid token is rejected

- **WHEN** a client GETs `/api/v1/iam/me` without an access token or with an expired one
- **THEN** the response is HTTP 401 `UNAUTHENTICATED`
