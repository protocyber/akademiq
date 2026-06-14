## ADDED Requirements

### Requirement: Tenant admins SHALL create a tenant user directly with a chosen username

The service MUST provide `POST /api/v1/iam/tenants/me/users`, restricted to
callers with `user.invite`, that creates a user and grants one or more
assignable roles within a single transaction. The request MUST accept
`username`, `full_name`, one or more `roles`, an optional `email`, and an
optional `password`. `username` MUST be required, MUST NOT contain `@`, and MUST
be globally unique across the system, case-insensitively. `email`, when present,
MUST be unique-if-present case-insensitively. The `tenant_id` MUST be resolved
from the caller's access token and MUST NOT be read from the request body. On
success the service MUST emit `tenant_user.created`. All values MUST bind as SQL
parameters (no string interpolation).

#### Scenario: Admin creates a user with a unique username

- **WHEN** an admin with `user.invite` POSTs `{ username, full_name, roles: ["teacher"] }` to `/tenants/me/users`
- **THEN** the response is HTTP 201 with the created user, the user holds the `teacher` role in the tenant, and a `tenant_user.created` event is published

#### Scenario: Duplicate username is rejected globally

- **WHEN** an admin POSTs a `username` that already exists anywhere in the system (case-insensitive)
- **THEN** the response is HTTP 409 with code `USERNAME_TAKEN` and no user is created

#### Scenario: Username containing '@' is rejected

- **WHEN** an admin POSTs a `username` containing `@`
- **THEN** the response is HTTP 422 `VALIDATION_ERROR` with a field error on `username`

#### Scenario: Non-privileged caller cannot create a user

- **WHEN** a caller without `user.invite` POSTs to `/tenants/me/users`
- **THEN** the response is HTTP 403

### Requirement: Tenant admins SHALL update a tenant user's identity fields

The service MUST provide `PATCH /api/v1/iam/tenants/me/users/{id}`, restricted to
callers with the `user.update` permission (a new permission distinct from
`user.invite`, because a changed `username` rewrites the global login key), that
updates a tenant user's `username`, `email`, and/or `full_name`. The target user
MUST be a member of the caller's tenant (resolved from the access token). A
changed `username` MUST remain globally unique case-insensitively and MUST NOT
contain `@`; a changed `email` MUST remain unique-if-present case-insensitively.
The operation MUST emit `tenant_user.updated` and MUST return HTTP 404 when the
user is not a member of the tenant.

#### Scenario: Admin updates a user's full name

- **WHEN** an admin PATCHes `{ full_name: "Budi Santoso" }` for a member user
- **THEN** the response is HTTP 200 with the updated user and a `tenant_user.updated` event is published

#### Scenario: Update to a taken username is rejected

- **WHEN** an admin PATCHes a `username` already used by another user
- **THEN** the response is HTTP 409 `USERNAME_TAKEN` and the user is unchanged

#### Scenario: Updating a non-member user is rejected

- **WHEN** an admin PATCHes a user who has no role in the caller's tenant
- **THEN** the response is HTTP 404

#### Scenario: Caller without user.update cannot edit identity

- **WHEN** a caller lacking the `user.update` permission PATCHes a member user's identity fields
- **THEN** the response is HTTP 403

### Requirement: Tenant admins SHALL remove a user from the tenant explicitly

The service MUST provide an explicit off-boarding operation,
`DELETE /api/v1/iam/tenants/me/users/{id}`, restricted to callers with the
`user.disable` permission, that removes ALL of the user's roles in the caller's
tenant in a single transaction and un-enrolls them from that tenant. This exists
because tenant membership is expressed solely through `user_tenant_role` rows and
removing a user's last role is refused (see the role-assignment requirement). The
operation MUST honor the last-admin guard (it MUST be refused with `LAST_ADMIN`
when it would remove the tenant's only `user.role.assign` holder), MUST resolve
`tenant_id` from the access token, MUST return HTTP 404 when the user is not a
member, and MUST emit `tenant_user.removed`. It MUST NOT delete the global user
record.

#### Scenario: Admin removes a user from the tenant

- **WHEN** an admin with `user.disable` DELETEs a member user who is not the last administrator
- **THEN** all of that user's roles in the tenant are removed, the user no longer appears in `GET /tenants/me/users`, the global user record still exists, and a `tenant_user.removed` event is published

#### Scenario: Removing the last administrator from the tenant is refused

- **WHEN** an admin attempts to remove the tenant's only holder of `user.role.assign`
- **THEN** the response is HTTP 409 `LAST_ADMIN` and the user retains their roles

#### Scenario: Removing a non-member user is rejected

- **WHEN** an admin DELETEs a user who has no role in the caller's tenant
- **THEN** the response is HTTP 404

## MODIFIED Requirements

### Requirement: Tenant admins SHALL assign one or more roles per user

Role assignment MUST manage a set of roles per user. The service MUST provide
add and remove operations (e.g. `POST /tenants/me/users/{id}/roles/{roleId}` and
`DELETE /tenants/me/users/{id}/roles/{roleId}`), gated on the `user.role.assign`
permission. The assignable set MUST include the tenant's built-in assignable
roles and its custom roles. Removing a role MUST be refused when it would leave
the user with zero roles in the tenant, because tenant membership is expressed
solely through `user_tenant_role` rows and dropping the last role would silently
un-enroll the user. Adding a role MUST emit `tenant_user.role_assigned` and
removing a role MUST emit `tenant_user.role_removed`; these names are existing and
MUST NOT be renamed. The single-role *replace* operation
(`change_user_role` → `tenant_user.role_changed`) is a separate path and MUST NOT
be used to implement multi-role add/remove or bulk role changes, since it bypasses
the last-role/last-admin guards. Role changes MUST NOT require the user to log
out; updated roles MUST be reflected the next time an access token is issued via
refresh-token rotation.

#### Scenario: Admin adds a role to a user

- **WHEN** an admin with `user.role.assign` adds a role to a user
- **THEN** the user holds that role in addition to any existing roles, and HTTP
  204 is returned

#### Scenario: Admin removes one of several roles

- **WHEN** an admin removes one role from a user holding multiple roles
- **THEN** the user retains the remaining roles

#### Scenario: Removing a user's last role is refused

- **WHEN** an admin removes the only role a user holds in the tenant
- **THEN** the response is HTTP 409 `LAST_ROLE`, the role is retained, and the
  user remains a member of the tenant

#### Scenario: Non-privileged caller cannot assign roles

- **WHEN** a caller without `user.role.assign` attempts to add or remove a role
- **THEN** the response is `403`

#### Scenario: New role appears after token refresh

- **WHEN** an admin adds a role to a user and that user subsequently refreshes their access token
- **THEN** the newly issued access token carries the updated roles and a `tenant_user.role_assigned` event was published
