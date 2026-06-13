## ADDED Requirements

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
