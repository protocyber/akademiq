## MODIFIED Requirements

### Requirement: Tenant admins SHALL assign one or more roles per user

Role assignment MUST move from a single-role swap to managing a **set** of roles
per user. The service MUST provide add and remove operations (e.g.
`POST /tenants/me/users/{id}/roles/{roleId}` and
`DELETE /tenants/me/users/{id}/roles/{roleId}`), gated on the `user.role.assign`
permission. The assignable set MUST include the tenant's built-in assignable
roles **and** its custom roles. The legacy single-value
`PATCH /tenants/me/users/{id}/role` is superseded.

#### Scenario: Admin adds a role to a user

- **WHEN** an admin with `user.role.assign` adds a role to a user
- **THEN** the user holds that role in addition to any existing roles, and HTTP
  204 is returned

#### Scenario: Admin removes one of several roles

- **WHEN** an admin removes one role from a user holding multiple roles
- **THEN** the user retains the remaining roles

#### Scenario: Non-privileged caller cannot assign roles

- **WHEN** a caller without `user.role.assign` attempts to add or remove a role
- **THEN** the response is `403`

### Requirement: Invitations MAY carry one or more roles

An invitation MUST accept one or more roles from the tenant's assignable set
(built-in and custom). Accepting the invitation MUST grant the invitee every
invited role within one transaction.

#### Scenario: Multi-role invitation grants all roles on acceptance

- **WHEN** an admin invites an email with roles `["teacher", "homeroom_teacher"]`
  and the invitee accepts
- **THEN** the created membership includes both roles in the tenant

#### Scenario: Invitation with a custom role

- **WHEN** an admin invites an email with a tenant-defined custom role
- **THEN** acceptance grants that custom role and the user's effective
  permissions include the custom role's permissions
