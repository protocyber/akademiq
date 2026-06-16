## MODIFIED Requirements

### Requirement: The tenant users listing SHALL support server-side search, filter, sort, and pagination

`GET /api/v1/iam/tenants/me/users` MUST accept optional query parameters `search`,
`role`, `status`, `page`, `page_size`, and `sort`, and MUST apply them server-side
against the database. `search` MUST match (case-insensitive, substring) over
`full_name`, `email`, and `username`. `role` MUST filter by role code and `status` by
account status. `sort` MUST be validated against an allow-list of sortable columns and
`page_size` MUST be clamped to a maximum. All parameter values MUST bind as SQL
parameters (no string interpolation). The response MUST use the paginated envelope
`{ "data": [ ... ], "meta": { "page", "page_size", "total" } }` where `total` is the
count of rows matching the filters before pagination. Each row in `data` MUST include
the user's `email_verified` boolean so clients can show verification status without an
extra request.

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

#### Scenario: Each row reports email verification status

- **WHEN** an admin requests `/tenants/me/users`
- **THEN** every row in `data` includes an `email_verified` boolean reflecting that user's stored verification state

## ADDED Requirements

### Requirement: Email verification status SHALL be visible wherever a user email is shown

The UI MUST show a verification indicator derived from `email_verified` wherever a
user's email is displayed prominently: at minimum the signed-in user's own
profile/account view (driven by `useMe`) and the tenant user-management edit-user
view (driven by the tenant-users list). The indicator MUST be a check when the
email is verified and an alert/attention indicator when it is not, and MUST carry
an accessible label so the state is not conveyed by color or icon shape alone.

#### Scenario: Verified email shows a check

- **WHEN** a view renders an email whose `email_verified` is true
- **THEN** a check indicator with an accessible "verified" label appears next to the email

#### Scenario: Unverified email shows an alert

- **WHEN** a view renders an email whose `email_verified` is false
- **THEN** an alert indicator with an accessible "not verified" label appears next to the email

#### Scenario: State is not conveyed by color alone

- **WHEN** the verification indicator is rendered in either state
- **THEN** an accessible text label or title communicates the state independently of color
