# web-user-role-management Specification

## Purpose

Defines requirements for role-related UI in the web app: a role-management screen with permission matrix, the user list showing and editing multiple roles per user, permission-gated UI controls, and multiselect role selection in the invitation modal.

## Requirements

### Requirement: Admins SHALL manage a role catalog with a permission matrix

The web app MUST provide a role-management screen (e.g. `settings/roles`),
visible to users holding `role.manage`. It MUST list built-in and custom roles
in a shadcn data table (TanStack Table) with the columns **Nama** (role name with
its `code` as a subtitle), **Tipe** (a Bawaan/Custom badge), and **Jumlah User**
(the role's `user_count`). The table MUST NOT show a permission column: a role's
permissions are viewed and edited only in the create/edit/clone modal's
permission-matrix selector sourced from `GET /tenants/me/permissions`.

The screen MUST allow creating, editing, and deleting **custom** roles. Built-in
roles MUST be presented as read-only with an option to clone into a new custom
role; per-row actions MUST be offered through an actions dropdown (Edit / Clone /
Hapus) in which Edit and Hapus are disabled for built-in roles. The permission
selector MUST only offer permissions the current admin holds (no-escalation), and
surface server `PRIVILEGE_ESCALATION` errors.

The screen MUST provide a search box (matching role name/code) and MUST keep
search, sort, and pagination synchronized to the browser URL so refresh,
bookmark, and share reproduce the same view. Sort MUST be available on Nama,
Tipe, and Jumlah User. List data, sorting, and pagination MUST be server-driven
via the `GET /tenants/me/roles` query parameters and `{ data, meta }` envelope.

#### Scenario: Admin views the role catalog

- **WHEN** an admin opens `settings/roles`
- **THEN** built-in and custom roles appear in a data table showing Nama, Tipe,
  and Jumlah User, built-in rows expose only Clone, and custom rows expose Edit /
  Clone / Hapus

#### Scenario: View state is reflected in the URL

- **WHEN** an admin searches for a role and sorts by Jumlah User descending
- **THEN** the URL carries the search and sort params, and reloading the page
  reproduces the same filtered, sorted view

#### Scenario: Admin clones a built-in role

- **WHEN** an admin chooses Clone on a built-in role
- **THEN** the create modal opens prefilled from that role's permission set as a
  new editable custom role

#### Scenario: Role screen hidden without permission

- **WHEN** a user without `role.manage` is signed in
- **THEN** the role-management entry point is not shown and the route is guarded

### Requirement: Admins SHALL bulk-delete custom roles with a guarded confirmation

The role table MUST offer header and per-row selection checkboxes and a bulk
delete action over the selected roles. The bulk Hapus control MUST be disabled
whenever the selection includes any built-in role, with red helper text
instructing the admin to deselect built-in roles first. When the selection is
entirely custom roles, activating Hapus MUST open a reusable confirmation
AlertDialog (a shadcn `AlertDialog` under `src/components/ui/`) before any delete
is sent. On confirmation the screen MUST call the all-or-nothing
`POST /tenants/me/roles/bulk/delete` endpoint and surface a server refusal (e.g.
`ROLE_IN_USE`, `BUILT_IN_ROLE_IMMUTABLE`) without partially updating the view.

#### Scenario: Built-in role in selection disables bulk delete

- **WHEN** an admin selects a mix of custom and built-in roles
- **THEN** the bulk Hapus control is disabled and red helper text tells the admin
  to deselect built-in roles before deleting

#### Scenario: Confirmed bulk delete of custom roles

- **WHEN** an admin selects two unused custom roles and activates Hapus
- **THEN** an AlertDialog asks for confirmation, and confirming deletes both roles
  and refreshes the list

#### Scenario: Server refusal is surfaced without partial change

- **WHEN** a confirmed bulk delete includes a role still assigned to users and the
  server responds `ROLE_IN_USE`
- **THEN** the screen shows the refusal and no selected role is removed from the
  list

### Requirement: The user list SHALL show and edit multiple roles per user

The tenant users screen MUST display each user's roles as a set (e.g. chips).
Adding and removing roles MUST happen inside the per-user edit modal against the
assignable catalog, calling the add/remove role endpoints; inline per-row role
selectors MUST NOT be used. The UI MUST prevent (or clearly surface the server
refusal of) removing the last administrator, and MUST surface the server's
`LAST_ROLE` refusal when an admin attempts to remove a user's only role so the
user is not silently un-enrolled from the tenant.

#### Scenario: User shows multiple role chips

- **WHEN** a user holds `teacher` and `homeroom_teacher`
- **THEN** the user row displays both roles and the edit modal offers add/remove controls

#### Scenario: Removing the last admin is blocked

- **WHEN** an admin attempts to remove the role that holds `user.role.assign`
  from the last remaining administrator
- **THEN** the UI surfaces the `LAST_ADMIN` refusal and the role is retained

#### Scenario: Removing a user's last role is blocked

- **WHEN** an admin attempts to remove the only role a user holds in the tenant
- **THEN** the UI surfaces the `LAST_ROLE` refusal, the role is retained, and the
  user remains visible in the list

### Requirement: The UI SHALL gate controls on the caller's permissions

UI affordances (invite, disable, assign role, manage roles) MUST be shown/enabled
based on the permissions in the caller's token (`perms`), not on a single role
name.

#### Scenario: Controls reflect held permissions

- **WHEN** a signed-in user's `perms` lacks `user.disable`
- **THEN** the enable/disable control is hidden or disabled for that user

### Requirement: Invitation role selection SHALL use a multiselect dropdown

The invitation modal MUST present assignable roles via a shadcn multiselect
dropdown (e.g. a Command/Popover combobox) rather than a grid of checkboxes. The
control MUST allow selecting one or more roles, MUST require at least one role
before submission, and MUST show the selected roles.

#### Scenario: Admin selects multiple roles in the invite modal

- **WHEN** an admin opens the invite modal and picks `teacher` and `homeroom_teacher` from the dropdown
- **THEN** both roles are shown as selected and submitting creates an invitation carrying both roles

#### Scenario: Empty role selection blocks submission

- **WHEN** an admin clears all roles in the invite modal and attempts to submit
- **THEN** the form shows a validation error requiring at least one role and does not submit
