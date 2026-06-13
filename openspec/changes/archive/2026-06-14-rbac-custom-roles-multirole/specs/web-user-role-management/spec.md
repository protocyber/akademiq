## ADDED Requirements

### Requirement: Admins SHALL manage a role catalog with a permission matrix

The web app MUST provide a role-management screen (e.g. `settings/roles`),
visible to users holding `role.manage`. It MUST list built-in and custom roles,
show each role's permissions, and allow creating, editing, and deleting **custom**
roles via a permission-matrix selector sourced from `GET /tenants/me/permissions`.
Built-in roles MUST be presented as read-only with an option to clone into a new
custom role. The permission selector MUST only offer permissions the current
admin holds (no-escalation), and surface server `PRIVILEGE_ESCALATION` errors.

#### Scenario: Admin views the role catalog

- **WHEN** an admin opens `settings/roles`
- **THEN** built-in roles appear read-only and custom roles appear editable, each
  showing its permission set

#### Scenario: Admin clones a built-in role

- **WHEN** an admin clones `teacher` and removes `grade.record` from the clone
- **THEN** a new custom role is created without `grade.record`, and the built-in
  `teacher` is unchanged

#### Scenario: Role screen hidden without permission

- **WHEN** a user without `role.manage` is signed in
- **THEN** the role-management entry point is not shown and the route is guarded

### Requirement: The user list SHALL show and edit multiple roles per user

The tenant users screen MUST display each user's roles as a set (e.g. chips) and
allow adding/removing roles against the assignable catalog, replacing the
single-select role dropdown. Changes MUST call the add/remove role endpoints. The
UI MUST prevent (or clearly surface the server refusal of) removing the last
administrator.

#### Scenario: User shows multiple role chips

- **WHEN** a user holds `teacher` and `homeroom_teacher`
- **THEN** the user row displays both roles and offers add/remove controls

#### Scenario: Removing the last admin is blocked

- **WHEN** an admin attempts to remove the role that holds `user.role.assign`
  from the last remaining administrator
- **THEN** the UI surfaces the `LAST_ADMIN` refusal and the role is retained

### Requirement: The UI SHALL gate controls on the caller's permissions

UI affordances (invite, disable, assign role, manage roles) MUST be shown/enabled
based on the permissions in the caller's token (`perms`), not on a single role
name.

#### Scenario: Controls reflect held permissions

- **WHEN** a signed-in user's `perms` lacks `user.disable`
- **THEN** the enable/disable control is hidden or disabled for that user
