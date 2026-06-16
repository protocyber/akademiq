# tenant-user-management Specification

## Purpose

Defines requirements for managing users within a tenant: invitation-based onboarding (where invitations attach membership to accounts that may already exist), single-use invitation tokens, role assignment per user, account enable/disable, searchable/filterable/paginated tenant user listings, bulk operations, and CSV roster export.

## Requirements

### Requirement: Tenant admins SHALL invite tenant-scoped users by email and roles

The service MUST provide `POST /api/v1/iam/tenants/me/invitations` restricted
to callers with `user.invite`, accepting an email and one or more roles from the
assignable set (built-in and custom). It MUST store only a hash of the activation
token and emit `tenant_user.invited`. Accepting the invitation MUST grant the
invitee every invited role within one transaction.

#### Scenario: Admin invites a teacher

- **WHEN** an admin with `user.invite` POSTs `{ email, roles: ["teacher"] }` to `/tenants/me/invitations`
- **THEN** the response is HTTP 201 with a pending invitation and an activation link, and a `tenant_user.invited` event is published

#### Scenario: Non-privileged caller cannot invite

- **WHEN** a user without `user.invite` POSTs to `/tenants/me/invitations`
- **THEN** the response is HTTP 403

#### Scenario: Multi-role invitation grants all roles on acceptance

- **WHEN** an admin invites an email with roles `["teacher", "homeroom_teacher"]`
  and the invitee accepts
- **THEN** the created membership includes both roles in the tenant

#### Scenario: Invitation with a custom role

- **WHEN** an admin invites an email with a tenant-defined custom role
- **THEN** acceptance grants that custom role and the user's effective
  permissions include the custom role's permissions

### Requirement: Invitations SHALL grant membership to an account that may already exist

Accepting an invitation MUST grant the invited roles and tenant membership. When
the invited email already has an account, acceptance attaches the membership to
that account without requiring a password. When the invited email has **no**
account, acceptance MUST create a new account and attach membership; creating
that account MUST NOT require the invitee to choose a password at accept time.
The invitee MUST be signed in (scoped token pair) upon acceptance in both cases.

#### Scenario: Existing account accepts without a password

- **WHEN** the invited email already has an account and the invitation is accepted
- **THEN** the membership and roles are attached and a scoped session is issued,
  with no password input required

#### Scenario: New account is created without a password

- **WHEN** the invited email has no account and the invitation is accepted with
  only the token
- **THEN** a new account is created in a no-password state, membership and roles
  are granted, and a scoped session is issued

#### Scenario: Name falls back when not provided

- **WHEN** a new account is created from a button-only accept with no name input
- **THEN** the account's name is taken from the invitation record (or a
  placeholder the user can edit later), and acceptance still succeeds

### Requirement: Invitation tokens SHALL be single-use and time-bound

Accepting an invitation MUST attach the `user_tenant_role` membership (creating
the account first only when no matching account exists) and mark the invitation
accepted within one transaction. A token MUST NOT be redeemable more than once,
MUST be rejected after expiry, and MUST be rejected if revoked.

#### Scenario: Successful acceptance creates an authenticated user

- **WHEN** an invitee POSTs `{ token, password, full_name }` to `/invitations/accept` with a valid, unexpired token
- **THEN** the response is HTTP 201 with access + refresh tokens, the user has the invited role in the tenant, and a `tenant_user.activated` event is published

#### Scenario: Reused token is rejected

- **WHEN** an already-accepted invitation token is submitted again
- **THEN** the response is HTTP 409 `INVITATION_ALREADY_USED` and no new user is created

#### Scenario: Expired token is rejected

- **WHEN** a token is submitted after its `expires_at`
- **THEN** the response is HTTP 410 `INVITATION_EXPIRED`

### Requirement: The service SHALL seed a `principal` role

IAM MUST seed a `principal` role with a stable `role.code` matching a
`ROLE_PRINCIPAL` constant in `common-auth`, so the report-card approval chain
has a final approver.

#### Scenario: Principal role exists and is assignable

- **WHEN** a tenant admin invites a user with role `principal`
- **THEN** the invitation succeeds and, after acceptance, the user's access token carries the `principal` role

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

### Requirement: Admins SHALL disable and re-enable tenant accounts

The service MUST allow a tenant admin to disable an account (blocking login)
and re-enable it, emitting `tenant_user.disabled` on disable.

#### Scenario: Disabled account cannot log in

- **WHEN** an admin disables a user and that user attempts to log in
- **THEN** the login is rejected and a `tenant_user.disabled` event was published

#### Scenario: Re-enabled account can log in

- **WHEN** an admin re-enables a previously disabled user
- **THEN** that user can log in again

### Requirement: The tenant users listing SHALL support server-side search, filter, sort, and pagination

`GET /api/v1/iam/tenants/me/users` MUST accept optional query parameters `search`,
`role`, `status`, `page`, `page_size`, and `sort`, and MUST apply them server-side
against the database. `search` MUST match (case-insensitive, substring) over
`full_name`, `email`, and `username`. `role` MUST filter by role code and `status` by
account status. `sort` MUST be validated against an allow-list of sortable columns and
`page_size` MUST be clamped to a maximum. All parameter values MUST bind as SQL
parameters (no string interpolation). The response MUST use the paginated envelope
`{ "data": [ ... ], "meta": { "page", "page_size", "total" } }` where `total` is the
count of rows matching the filters before pagination.

#### Scenario: Search narrows the result set server-side

- **WHEN** an admin requests `/tenants/me/users?search=budi`
- **THEN** only users whose name, email, or username contains "budi" are returned, and `meta.total` reflects the filtered count

#### Scenario: Filter by role and status

- **WHEN** an admin requests `/tenants/me/users?role=teacher&status=active`
- **THEN** only active users holding the `teacher` role are returned

#### Scenario: Pagination returns the requested page with totals

- **WHEN** an admin requests `/tenants/me/users?page=2&page_size=25`
- **THEN** rows 26–50 of the filtered set are returned and `meta` reports `page=2`, `page_size=25`, and the full `total`

#### Scenario: page_size is clamped and sort is validated

- **WHEN** an admin requests `/tenants/me/users?page_size=100000&sort=DROP`
- **THEN** the response clamps `page_size` to the allowed maximum and rejects or ignores the invalid sort without executing arbitrary SQL

### Requirement: Admins SHALL apply enable, disable, and role-change to multiple users in one request

The service MUST provide bulk operations
(`POST /api/v1/iam/tenants/me/users/bulk/enable`,
`/bulk/disable`, `/bulk/role`) that accept a set of user IDs (and, for role, the target
role). Each affected user MUST be processed through the same domain path as the
single-user operation so that authorization checks and the last-administrator guard
still apply, and each MUST emit its own per-user `tenant_user.*` event via the outbox.
The response MUST report per-user success or failure so a partial failure does not
silently drop other users. Bulk hard-delete MUST NOT be provided.

#### Scenario: Bulk disable emits one event per user

- **WHEN** an admin bulk-disables three users
- **THEN** all three are disabled and three separate `tenant_user.disabled` events are published

#### Scenario: Partial failure is reported per user

- **WHEN** a bulk role change includes the last remaining administrator
- **THEN** the last-admin user is rejected with its reason while the other users succeed, and the response lists each user's outcome

#### Scenario: No bulk delete endpoint exists

- **WHEN** a client attempts a bulk hard-delete of users
- **THEN** no such endpoint is available

### Requirement: Admins SHALL export the filtered user roster as CSV

The service MUST provide `GET /api/v1/iam/tenants/me/users/export` that returns the
roster as `text/csv` using the same `search`/`role`/`status` filters as the listing
(without pagination). The CSV MUST be openable in spreadsheet tools.

#### Scenario: Export honors active filters

- **WHEN** an admin requests `/tenants/me/users/export?role=teacher`
- **THEN** the response is a CSV containing only `teacher` users matching the filter, with no pagination applied

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

### Requirement: Accepting an invitation SHALL NOT require choosing a password up front

A user accepting a tenant invitation MUST be able to do so without choosing a
password at accept time. The invited user MAY set a password later via the
self-service set-password flow. Roles and membership are granted on acceptance
regardless of whether a password has been set.

#### Scenario: Invitee joins with a single action

- **WHEN** an invited user accepts the invitation
- **THEN** they gain their tenant membership and a session without being required
  to enter a password during acceptance

#### Scenario: Password set later

- **WHEN** the invited user later completes the set-password flow
- **THEN** password login becomes available for their account
