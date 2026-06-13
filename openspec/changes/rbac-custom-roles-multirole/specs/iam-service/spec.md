## ADDED Requirements

### Requirement: Authorization SHALL be decided by permissions, not role names

The platform MUST define a fixed, seeded `permission` vocabulary of action codes
(e.g. `user.invite`, `user.disable`, `user.role.assign`, `role.manage`,
`billing.view`, `billing.manage`, `academic.config.write`, `report.generate`,
`report.transition`, `grade.record`). Each built-in role MUST be seeded with a
`role_permission` set that reproduces its current behavior. Service authorization
checks MUST be expressed as permission checks (`require_permission`) rather than
role-name comparisons. The permission vocabulary MUST NOT be editable by tenants.

#### Scenario: A held permission authorizes an action

- **WHEN** a caller's access token carries `perms` containing `user.invite`
- **THEN** `POST /tenants/me/invitations` is authorized regardless of which role
  granted that permission

#### Scenario: A missing permission is refused

- **WHEN** a caller's token does not contain `user.invite`
- **THEN** the request is refused with `403 FORBIDDEN`

#### Scenario: Built-in roles preserve prior behavior

- **WHEN** a user holds the built-in `tenant_admin` role after migration
- **THEN** the user is allowed exactly the actions `tenant_admin` could perform
  before this change, now expressed as permissions

### Requirement: Tenant admins SHALL define custom roles from a permission palette

The service MUST expose role-management endpoints gated on the `role.manage`
permission: `GET/POST /tenants/me/roles`, `GET/PATCH/DELETE
/tenants/me/roles/{id}`, and `GET /tenants/me/permissions` returning the
assignable palette. A tenant role MUST be stored with the tenant's `tenant_id`
and a `code` unique within that tenant that MUST NOT collide with any built-in
role code. Built-in roles (`tenant_id = NULL`) MUST be immutable; customization
is achieved by creating a new role or cloning a built-in.

#### Scenario: Admin creates a custom role

- **WHEN** an admin with `role.manage` POSTs `{ code, name, permissions: [...] }`
  to `/tenants/me/roles`
- **THEN** a tenant-scoped role is created with that permission set and HTTP 201

#### Scenario: Built-in role cannot be edited

- **WHEN** a PATCH or DELETE targets a built-in role (`tenant_id = NULL`)
- **THEN** the service responds `403` (or `409`) and the built-in is unchanged

#### Scenario: Custom code cannot shadow a built-in

- **WHEN** an admin creates a role whose `code` equals a built-in code (e.g.
  `principal`)
- **THEN** the request is rejected with a validation error

### Requirement: Role authoring SHALL NOT escalate privilege

When creating or editing a role, the service MUST reject any permission the
calling admin does not currently hold in their own effective permission set.

#### Scenario: Admin cannot grant a permission they lack

- **WHEN** an admin without `billing.view` attempts to create a role that
  includes `billing.view`
- **THEN** the request is rejected with `403 PRIVILEGE_ESCALATION` and no role is
  created

### Requirement: A user SHALL hold multiple roles within a tenant

`user_tenant_role` MUST permit several rows per `(user_id, tenant_id)`, keyed by
`UNIQUE(user_id, tenant_id, role_id)`. The service MUST provide endpoints to add
and remove a role from a user (gated on `user.role.assign`), replacing the
single-role swap. Removing a role MUST NOT be allowed to leave the tenant with
zero users holding `user.role.assign`.

#### Scenario: A user is granted a second role

- **WHEN** an admin adds `homeroom_teacher` to a user who already holds `teacher`
- **THEN** the user holds both roles in that tenant

#### Scenario: The last administrator cannot be stripped

- **WHEN** removing a role would leave no user in the tenant holding
  `user.role.assign`
- **THEN** the removal is refused with `409 LAST_ADMIN`

### Requirement: Effective permissions SHALL be the union of all the user's roles

The service MUST, when issuing a tenant-scoped access token (at
`/tenants/{id}/enter` and `/auth/refresh`), resolve **all** of the user's roles
in that tenant, set `roles` to the list of role codes held, and set `perms` to
the deduplicated union of those roles' permissions.

#### Scenario: Permissions union across roles

- **WHEN** a user holds two roles granting `{grade.record}` and
  `{report.transition}`
- **THEN** the issued token's `perms` contains both `grade.record` and
  `report.transition`, and `roles` lists both role codes

### Requirement: The access token SHALL carry roles and permissions

The tenant-scoped access token claims MUST be
`{ sub, tenant_id, roles: [code…], perms: [code…], typ: "access", iat, exp, jti }`.
The `roles` array carries role identity for workflow and display; the `perms`
array is the authority used by guards. The single `role: String` claim is
removed after a one-release dual-read compatibility window during which
extractors MUST accept both the legacy `role` claim and the new
`roles`/`perms` claims.

#### Scenario: New token shape is issued

- **WHEN** a user enters a tenant
- **THEN** the access token contains `roles` and `perms` arrays and no scalar
  `role` claim

#### Scenario: Legacy token still verifies during the compatibility window

- **WHEN** a service receives an access token carrying only the legacy
  `role: String` claim during the dual-read window
- **THEN** the extractor accepts it, treating `roles` as `[role]` and resolving
  `perms` from that built-in role's seeded permission set

### Requirement: Custom role codes SHALL NOT drive service workflows

Service state machines (e.g. the report-card approval workflow) MUST match only
built-in role codes (`ROLE_*` constants) when deriving workflow identity. Custom
role codes MAY appear in `roles` for display and audit but MUST NOT be
interpreted as a workflow step.

#### Scenario: Custom role does not gain workflow authority

- **WHEN** a user holds a custom role whose code is not a built-in `ROLE_*`
- **THEN** the report-card workflow does not treat that code as SubjectTeacher,
  HomeroomTeacher, or Principal; workflow authority comes only from held
  permissions and built-in role identity
