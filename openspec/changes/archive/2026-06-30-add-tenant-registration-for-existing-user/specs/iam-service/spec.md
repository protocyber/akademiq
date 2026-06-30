## ADDED Requirements

### Requirement: The service SHALL provide an internal endpoint to attach a tenant membership to an existing user

IAM MUST expose `POST /api/v1/iam/internal/users/:id/tenant-membership`
protected by `X-Service-Token`. The endpoint accepts `{ tenant_id,
role_code }` and inserts a `user_tenant_role` row linking the existing user
to the tenant with the specified role. The endpoint MUST validate that the
user exists and the role_code is valid.

#### Scenario: Attach membership to existing user

- **WHEN** billing calls `POST /iam/internal/users/:id/tenant-membership`
  with `{ tenant_id, role_code: "tenant_admin" }` and a valid service token
- **THEN** IAM inserts a `user_tenant_role` row and returns success

#### Scenario: User not found

- **WHEN** the `:id` does not correspond to an existing user
- **THEN** the response is HTTP 404 with code `USER_NOT_FOUND`

#### Scenario: Duplicate membership

- **WHEN** the user already has a membership in the specified tenant
- **THEN** the response is HTTP 409 with code `MEMBERSHIP_ALREADY_EXISTS`

#### Scenario: Missing or invalid service token

- **WHEN** the `X-Service-Token` header is missing or invalid
- **THEN** the response is HTTP 401
