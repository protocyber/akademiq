## ADDED Requirements

### Requirement: The web app SHALL provide an audit-log screen gated on `audit.view`

The web app MUST provide a `settings/audit-log` screen, visible and routable only to
users whose `perms[]` include `audit.view`. The entry point MUST be hidden and the
route guarded for users without the permission.

#### Scenario: Screen hidden without permission

- **WHEN** a signed-in user without `audit.view` is active
- **THEN** the audit-log entry point is not shown and the route is guarded

#### Scenario: Admin opens the audit log

- **WHEN** a user with `audit.view` opens `settings/audit-log`
- **THEN** the activity trail for their tenant is shown

### Requirement: The audit-log screen SHALL be a server-driven, URL-synced table

The screen MUST render the trail from `GET /tenants/me/audit-log` with server-side
filtering (event type, actor, target, date range) and pagination. The active filters,
page, page_size, and sort MUST be synchronized to the browser URL and restored on load
so refresh, bookmark, or share reproduces the same view.

#### Scenario: Filtering issues a server request

- **WHEN** an admin selects an event type or sets a date range
- **THEN** the table requests the matching server page and shows paginated results

#### Scenario: Refresh restores the same view

- **WHEN** an admin applies filters and a page, then refreshes the browser
- **THEN** the same filtered, paginated trail is shown

### Requirement: The screen SHALL present each entry with actor, target, and detail

Each row MUST show the event type, the acting user, the affected user, and when it
occurred, with the full event `details` available in an expandable form rather than
raw JSON inline.

#### Scenario: Expand entry detail

- **WHEN** an admin expands an audit row
- **THEN** the full payload detail for that event is shown in a readable form
