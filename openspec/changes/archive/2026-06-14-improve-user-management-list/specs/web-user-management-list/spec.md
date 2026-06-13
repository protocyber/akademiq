## ADDED Requirements

### Requirement: The tenant users screen SHALL be a server-driven table with search, filters, sort, and pagination

The web app MUST render `settings/users` as a data table backed by the paginated
`GET /tenants/me/users` endpoint. It MUST provide a search input, a role filter, a
status filter, sortable columns, and pagination controls. Search/filter/sort/page
changes MUST drive server requests (not client-side filtering of a full list), and the
search input MUST be debounced before issuing a request.

#### Scenario: Filtering issues a server request

- **WHEN** an admin types in the search box or selects a role/status filter
- **THEN** the table requests the matching page from the server and shows server-paginated results

#### Scenario: Pagination navigates server pages

- **WHEN** an admin clicks next page
- **THEN** the next server page is fetched and displayed with the active filters preserved

### Requirement: View state SHALL be synchronized to the browser URL

The active `search`, `role`, `status`, `page`, `page_size`, and `sort` MUST be
reflected in the browser query string and MUST be restored from the query string on
load. Refreshing, bookmarking, or sharing the URL MUST reproduce the same
filtered/paged/sorted view. Updating view state MUST NOT spam browser history.

#### Scenario: Refresh restores the same view

- **WHEN** an admin applies `search=budi`, `role=teacher`, `page=3` and refreshes the browser
- **THEN** the table reloads showing the same search term, role filter, and page

#### Scenario: Shared URL reproduces the view

- **WHEN** an admin copies the URL with active filters and opens it in a new tab
- **THEN** the same filtered, paginated view is shown

### Requirement: The table SHALL support multi-select bulk actions

The table MUST provide a header checkbox and per-row checkboxes to select users, and a
bulk action bar to bulk enable, bulk disable, and bulk change role for the selected
set. After a bulk action it MUST surface per-user outcomes (how many succeeded and
which failed and why). Bulk delete MUST NOT be offered.

#### Scenario: Bulk disable selected users

- **WHEN** an admin selects several users and chooses "Disable"
- **THEN** the selected users are disabled and the result summarizes successes and any failures

#### Scenario: Bulk action partial failure is shown

- **WHEN** a bulk role change includes the last administrator and is refused for that user
- **THEN** the UI shows that user's failure reason while reporting the others as succeeded

### Requirement: The table SHALL expose export and per-user reset-password controls

The screen MUST offer an Export action that downloads the current filtered roster as
CSV via the export endpoint, and a per-row reset-password action wired to
`POST /tenants/me/users/:id/reset-password` with a confirmation step. Both controls
MUST be gated on the caller's permissions and the invite flow MUST be preserved.

#### Scenario: Export downloads the filtered roster

- **WHEN** an admin with active filters clicks Export
- **THEN** a CSV reflecting those filters is downloaded

#### Scenario: Reset password from a row

- **WHEN** an admin confirms reset-password for a user
- **THEN** the reset-password endpoint is called and the admin sees success or error feedback
