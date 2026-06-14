## MODIFIED Requirements

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

## ADDED Requirements

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
