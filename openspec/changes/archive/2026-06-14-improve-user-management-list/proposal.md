## Why

The tenant user-management screen (`settings/users`) renders every user as a flat,
client-side card list with a single-select role dropdown and no way to search,
filter, paginate, act on more than one user at a time, or get the data out of the
app. That is workable for a handful of accounts but collapses for a real school:
an admin managing hundreds or thousands of students and staff has no practical way
to find a user, apply a change to many at once, or hand the roster to another tool.
The backend already returns the full list with no query parameters, so all load and
filtering happens in the browser.

This change rebuilds the screen as a server-driven data table with search, role and
status filters, pagination, multi-select bulk actions, CSV/Excel export, and an
admin reset-password control — while keeping the existing invite flow. It is layered
**on top of** `rbac-custom-roles-multirole`: it assumes the multi-role chip model and
permission-gated controls introduced there, and its bulk role actions operate against
the role *set* per user, not the legacy single role.

## What Changes

- **BREAKING (API response shape):** `GET /api/v1/iam/tenants/me/users` moves from a
  bare JSON array to the paginated success envelope
  `{ "data": [...], "meta": { "page", "page_size", "total" } }` and accepts query
  params `search`, `role`, `status`, `page`, `page_size`, `sort`. Filtering, sorting,
  and pagination are performed **server-side** in the repository (`WHERE`/`ILIKE`,
  `ORDER BY`, `LIMIT`/`OFFSET`, plus a `COUNT`).
- **Server-side search** across `full_name`, `email`, and `username`; **filter** by
  role code and by active/disabled status; **sort** by name/status/role.
- **URL-synced view state:** the active `search`, `role`, `status`, `page`,
  `page_size`, and `sort` are reflected in the browser query string. Refreshing,
  bookmarking, or sharing the URL restores the exact same filtered/paged view.
- **Multi-select + bulk actions:** header and per-row checkboxes select users; a bulk
  action bar performs **bulk enable**, **bulk disable**, and **bulk role change**
  against the selected set. Each affected user emits the existing per-user
  `tenant_user.*` event (one event per user) so the audit log (separate change) can
  record it. **Bulk hard-delete is explicitly out of scope** — IAM has no tenant-user
  hard-delete; disable is the destructive-ish action.
- **Export:** a `GET /api/v1/iam/tenants/me/users/export` endpoint streams the current
  (filtered) roster as CSV, suitable for opening in Excel. The web app offers an
  Export button that downloads using the active filters.
- **Reset-password UI:** surface the **already-existing**
  `POST /tenants/me/users/:id/reset-password` endpoint as a per-row admin control.
- **Keep invite:** the invite-user flow is preserved; under rbac it carries one or
  more roles.
- **Import is explicitly deferred** to a phase-2 change that lands with the
  notification/email service. The current invite flow only returns a manual activation
  link, so bulk import producing hundreds of manual links would be unusable. Not built
  here.
- **Web UI rebuild:** replace the card list with a shadcn/ui data table (search input,
  filter selects, pagination controls, selection checkboxes, bulk action bar, row
  actions) per `apps/web/CONVENTIONS.md`.

## Capabilities

### New Capabilities

- `web-user-management-list`: the server-driven tenant user table UI — search,
  role/status filters, pagination, URL-synced view state, multi-select bulk
  enable/disable/role-change, CSV export download, and reset-password control.

### Modified Capabilities

- `tenant-user-management`: the tenant users listing endpoint gains server-side
  search/filter/sort/pagination and a paginated response envelope; new bulk
  enable/disable/role-change operations over a set of users; a CSV export endpoint.
  Each bulk operation emits the same per-user `tenant_user.*` events as the
  single-user operations.

## Impact

- **Depends on `rbac-custom-roles-multirole`** (must be applied first): multi-role
  chips, `perms[]` token for control gating, and the role catalog for filter options
  and bulk role assignment.
- **Backend (`iam-service`):** `queries.rs` (`list_tenant_users` gains filter/sort/
  pagination), `repo.rs` (parameterized `WHERE`/`ILIKE`/`LIMIT`/`OFFSET` + `COUNT`),
  `http.rs` (query-param parsing, paginated envelope, new export + bulk routes),
  `commands.rs` (bulk enable/disable/role-change reusing existing per-user commands and
  emitting one `tenant_user.*` event each via the existing outbox).
- **API contract:** `docs/internal/11_integration_contracts/apis/` updated for the new
  list response shape, query params, bulk endpoints, and export endpoint.
- **Web (`apps/web`):** `settings/users/page.tsx` rebuilt as a data table;
  `lib/query/queries/use-tenant-users.ts` and `lib/query/mutations/use-tenant-users.ts`
  extended for paginated params, bulk mutations, export, and reset-password; new
  schemas for query/filter state; URL query-string sync via Next.js router.
- **Out of scope:** bulk delete, CSV/Excel import (deferred), and the audit log itself
  (separate `tenant-audit-log` change), though bulk actions here emit the events that
  change consumes.
