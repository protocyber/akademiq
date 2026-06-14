## MODIFIED Requirements

### Requirement: The tenant users screen SHALL be a server-driven table with search, filters, sort, and pagination

The web app MUST render `settings/users` as a shadcn data table (built on
TanStack Table) backed by the paginated `GET /tenants/me/users` endpoint. The
page heading MUST read "Pengguna". It MUST provide a search input, a role
filter, a status filter, sortable columns, header and per-row selection
checkboxes, and pagination controls. Search/filter/sort/page changes MUST drive
server requests (not client-side filtering of a full list), and the search input
MUST be debounced before issuing a request. The invitations ("Undangan") section
MUST appear below the main table rather than beside it.

#### Scenario: Filtering issues a server request

- **WHEN** an admin types in the search box or selects a role/status filter
- **THEN** the table requests the matching page from the server and shows server-paginated results

#### Scenario: Pagination navigates server pages

- **WHEN** an admin clicks next page
- **THEN** the next server page is fetched and displayed with the active filters preserved

#### Scenario: Invitations render below the table

- **WHEN** an admin opens `settings/users`
- **THEN** the data table renders first and the pending-invitations section appears below it

### Requirement: The table SHALL support multi-select bulk actions

The data table MUST provide a header checkbox and per-row checkboxes to select
users, and a bulk action control (e.g. a shadcn dropdown menu) to bulk enable,
bulk disable, and bulk change role for the selected set. After a bulk action it
MUST surface per-user outcomes (how many succeeded and which failed and why).
Bulk delete MUST NOT be offered.

#### Scenario: Bulk disable selected users

- **WHEN** an admin selects several users and chooses "Disable"
- **THEN** the selected users are disabled and the result summarizes successes and any failures

#### Scenario: Bulk action partial failure is shown

- **WHEN** a bulk role change includes the last administrator and is refused for that user
- **THEN** the UI shows that user's failure reason while reporting the others as succeeded

### Requirement: The table SHALL expose export and user CRUD via modals

The screen MUST offer an Export action that downloads the current filtered
roster as CSV via the export endpoint. It MUST provide an "add user" modal that
creates a user via `POST /tenants/me/users` with `username`, `full_name`,
`roles`, and optional `email`/`password` fields, and a per-user "edit" modal
that updates identity fields via `PATCH /tenants/me/users/:id`, manages the
user's roles, triggers password reset via
`POST /tenants/me/users/:id/reset-password`, toggles enable/disable, and offers a
confirmed "remove from tenant" action via `DELETE /tenants/me/users/:id`. The
`username` field MUST be required, reject values containing `@`, and surface the
server's `USERNAME_TAKEN` conflict as a field error; when create fails because the
`username`/`email` already belongs to an existing user, the message MUST direct
the admin to use the invitation flow rather than implying a duplicate typo. The
invite flow MUST be preserved. Inline per-row "add role" selectors and
reset-password buttons MUST be removed in favor of the edit modal. All controls
MUST be gated on the caller's permissions.

#### Scenario: Export downloads the filtered roster

- **WHEN** an admin with active filters clicks Export
- **THEN** a CSV reflecting those filters is downloaded

#### Scenario: Add user via modal

- **WHEN** an admin submits the add-user modal with a unique username, full name, and at least one role
- **THEN** the user is created, the table refreshes to include them, and the modal closes with success feedback

#### Scenario: Duplicate username surfaces as a field error

- **WHEN** an admin submits the add-user (or edit) modal with a username already in use
- **THEN** the `username` field shows the `USERNAME_TAKEN` error and the modal stays open

#### Scenario: Edit modal hosts reset password, enable/disable, and remove

- **WHEN** an admin opens a user's edit modal
- **THEN** it offers identity-field editing, role management, a reset-password action with confirmation, an enable/disable toggle, and a confirmed "remove from tenant" action, with no equivalent inline row controls

#### Scenario: Creating a user that already exists points to invitations

- **WHEN** an admin submits the add-user modal with a `username` or `email` that already belongs to an existing user in the system
- **THEN** the modal stays open and the error explains the person already has an account and should be added via the invitation flow
