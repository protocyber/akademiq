## ADDED Requirements

### Requirement: IAM GET endpoints SHALL require read permissions

The IAM tenant-scoped GET endpoints SHALL enforce read permissions:

- `GET /api/v1/iam/tenants/me/users` (list tenant users) MUST require `user.read`.
- `GET /api/v1/iam/tenants/me/permissions` MUST be callable by any authenticated
  tenant member (it is how the client learns its own permissions); it MUST NOT require
  a read permission.
- `GET /api/v1/iam/tenants/me/roles` (list roles) and `GET .../roles/{id}` MUST require
  `role.read`.

Callers without the required permission MUST receive HTTP 403 with code `FORBIDDEN`.
`tenant_id` MUST continue to be resolved from the JWT.

#### Scenario: Listing users without user.read is forbidden

- **WHEN** a caller without `user.read` calls `GET /tenants/me/users`
- **THEN** the response is HTTP 403

#### Scenario: Listing roles with role.read succeeds

- **WHEN** a caller holding `role.read` calls `GET /tenants/me/roles`
- **THEN** the response is HTTP 200 with the role list
