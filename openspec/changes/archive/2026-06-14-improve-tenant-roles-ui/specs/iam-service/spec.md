## MODIFIED Requirements

### Requirement: Tenant admins SHALL define custom roles from a permission palette

The service MUST expose role-management endpoints gated on the `role.manage`
permission: `GET/POST /tenants/me/roles`, `GET/PATCH/DELETE
/tenants/me/roles/{id}`, `POST /tenants/me/roles/bulk/delete`, and
`GET /tenants/me/permissions` returning the assignable palette. A tenant role
MUST be stored with the tenant's `tenant_id` and a `code` unique within that
tenant that MUST NOT collide with any built-in role code. Built-in roles
(`tenant_id = NULL`) MUST be immutable; customization is achieved by creating a
new role or cloning a built-in.

`GET /tenants/me/roles` MUST accept the query parameters `search` (matches role
name or code, case-insensitive), `sort` (one of `name`, `-name`, `type`,
`-type`, `users`, `-users`), `page`, and `page_size`, and MUST return a
`{ data, meta }` envelope where `meta` carries `page`, `page_size`, and the total
matching `total`. The default sort MUST list built-in roles before custom roles,
then by code. Each role view in `data` MUST include a `user_count` field: the
number of users **in the calling tenant** holding that role (derived from
`user_tenant_role`), computed per-tenant even for built-in roles.

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

#### Scenario: Role list is searchable, sortable, and paginated

- **WHEN** an admin GETs `/tenants/me/roles?search=kurikulum&sort=-users&page=1&page_size=25`
- **THEN** the response contains only roles whose name or code matches
  `kurikulum`, ordered by descending `user_count`, and `meta` reports `page`,
  `page_size`, and the total match count

#### Scenario: Role view reports per-tenant usage count

- **WHEN** three users in the calling tenant hold the `teacher` role
- **THEN** that role's view in the list response has `user_count` equal to `3`,
  counting only users in the calling tenant

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

## ADDED Requirements

### Requirement: Admins SHALL delete multiple custom roles in one all-or-nothing request

The service MUST expose `POST /tenants/me/roles/bulk/delete`, gated on
`role.manage`, accepting a list of role ids. The endpoint MUST be
all-or-nothing: it MUST pre-validate every id and, if **any** id is a built-in
role, a role still assigned to one or more users, or not a custom role of the
calling tenant, it MUST reject the entire request without deleting anything. Only
when every id passes MUST it delete all of them in a single transaction, emitting
one `role.deleted` event per deleted role (the same event the single-role delete
emits).

#### Scenario: Bulk delete succeeds for all-custom unused selection

- **WHEN** an admin POSTs ids of two custom roles, neither assigned to any user,
  to `/tenants/me/roles/bulk/delete`
- **THEN** both roles are deleted in one transaction, two `role.deleted` events
  are emitted, and the response is success

#### Scenario: Bulk delete is refused whole if any role is built-in

- **WHEN** the payload includes a built-in role id alongside custom role ids
- **THEN** the request is refused with `403 BUILT_IN_ROLE_IMMUTABLE` and **no**
  role is deleted

#### Scenario: Bulk delete is refused whole if any role is in use

- **WHEN** the payload includes a custom role that is still assigned to at least
  one user
- **THEN** the request is refused with `409 ROLE_IN_USE` and **no** role is
  deleted
