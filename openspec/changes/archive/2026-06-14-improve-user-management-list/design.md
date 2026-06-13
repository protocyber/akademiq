## Context

`settings/users` is a client-side screen: it fetches the full user array from
`GET /api/v1/iam/tenants/me/users` (no query params) and the full invitation array,
then renders cards in React. Role change is a single-select dropdown calling
`PATCH /tenants/me/users/:id/role`; enable/disable and reset-password endpoints exist
server-side (`/tenants/me/users/:id/{enable,disable,reset-password}`). There is no
search, filter, pagination, or multi-select.

IAM already runs a transactional **outbox** (`iam-service/src/outbox.rs`) and publishes
`tenant_user.invited / activated / role_changed / disabled` to the `akademiq.events`
topic exchange. This is the seam the separate `tenant-audit-log` change consumes; bulk
actions here must keep emitting one event per affected user.

This change sits **on top of `rbac-custom-roles-multirole`**, which replaces the single
`role` claim with `roles[]/perms[]`, introduces multi-role chips per user, a tenant
role catalog, and permission-gated controls. This design assumes that model: the role
filter and bulk role assignment operate against the assignable role catalog, and
control visibility keys off `perms[]`.

## Goals / Non-Goals

**Goals:**
- Server-side search, filter, sort, and pagination on the tenant users listing.
- Browser-URL-synced view state so refresh/bookmark/share restores the same view.
- Multi-select with bulk enable, bulk disable, and bulk role change.
- CSV export of the (filtered) roster, openable in Excel.
- Surface the existing admin reset-password endpoint in the UI.
- Preserve the existing invite flow.
- Keep bulk actions emitting per-user `tenant_user.*` events for the audit log.

**Non-Goals:**
- Bulk hard-delete of users (IAM has no tenant-user hard-delete; out of scope).
- CSV/Excel **import** (deferred to a phase-2 change with the notification service).
- The audit log itself (separate `tenant-audit-log` change).
- Native `.xlsx` generation server-side (CSV is Excel-openable; true xlsx is out).
- Re-specifying multi-role chips or the role catalog (owned by the rbac change).

## Decisions

### D1: Server-side filtering, paginated envelope

`list_tenant_users` and its repository method take an optional filter/sort/page set and
build a parameterized SQL query: `ILIKE` over `full_name`/`email`/`username` for
`search`, equality on role and status, `ORDER BY` for `sort`, `LIMIT`/`OFFSET` for the
page, plus a second `COUNT(*)` over the same `WHERE` for `meta.total`. The HTTP handler
returns `{ "data": [...], "meta": { "page", "page_size", "total" } }`.

- **Why server-side:** the user explicitly chose it; a school can have thousands of
  users — shipping the whole roster to the browser to filter does not scale.
- **Alternative rejected:** keep client-side filtering. Simpler but caps usable tenant
  size and grows payloads unbounded.
- **Param safety:** all values bind as SQL parameters (no string interpolation);
  `page_size` is clamped to a max (e.g. 100) and `sort` is validated against an
  allow-list of columns to prevent injection and pathological queries.
- **BREAKING:** the response shape changes from array to envelope. The web client is
  the only consumer and is updated in lockstep. Note in the API contract.

### D2: URL is the source of truth for view state

The web table reads `search`, `role`, `status`, `page`, `page_size`, `sort` from the
Next.js `searchParams` and writes them back via `router.replace` (no history spam) on
every change. The TanStack Query key includes these params so each distinct view is
cached independently. On load, the query string seeds initial state; with no params,
sensible defaults apply (`page=1`, default `page_size`, no filters).

- **Why:** refresh/bookmark/share restores the exact view (explicit requirement).
- **Alternative rejected:** React state only — lost on refresh, not shareable.
- **Debounce:** the search input debounces before pushing to the URL to avoid a request
  per keystroke.

### D3: Bulk actions = loop existing per-user commands, one event each

New bulk endpoints (`POST /tenants/me/users/bulk/{enable,disable,role}`) accept a list
of user IDs (and a role for bulk-role). Each reuses the existing single-user command
path inside one request so behavior (last-admin guard, permission checks, status
transitions) is identical, and each affected user emits its own `tenant_user.*` event
through the existing outbox. The response reports per-user success/failure so a
partial failure (e.g. last-admin guard tripping on one row) does not silently drop the
others.

- **Why per-user events:** the audit log change records individual actions; one
  coarse "bulk" event would lose the per-user trail.
- **Why per-user result reporting:** bulk operations routinely partially fail; the UI
  must show which rows succeeded.
- **Alternative rejected:** a single bulk SQL `UPDATE` — bypasses domain guards and
  event emission.

### D4: CSV export streams server-side with active filters

`GET /tenants/me/users/export?<same filters>` returns `text/csv` built from the same
filtered query as the list (without pagination). The web app triggers a download. CSV
is chosen over xlsx because it is Excel-openable with no extra backend dependency.

- **Alternative rejected:** client builds CSV from fetched rows — would require
  fetching all pages first, defeating server-side pagination.

### D5: Reset-password reuses the existing endpoint

No new backend work for reset-password — the UI wires a per-row control to
`POST /tenants/me/users/:id/reset-password`, gated on the caller's permission, with a
confirm step and toast feedback.

## Risks / Trade-offs

- **Response-shape break** → only the web client consumes it; updated together and
  noted in the API contract. No external API consumers today.
- **Bulk action partial failure confusion** → per-user result list surfaced in the UI;
  toasts summarize "N succeeded, M failed".
- **`ILIKE` performance at scale** → acceptable for v1; add a trigram/index follow-up
  if profiling shows slow search on large tenants. Document as a known follow-up.
- **URL state + query cache key drift** → keep a single typed parser/serializer for the
  param set so the query key, the request, and the URL never disagree.
- **Coupling to rbac change** → if rbac is not applied first, the role filter and bulk
  role assignment have no catalog to target. Mitigation: this change is explicitly
  sequenced after rbac; tasks call that out.

## Migration Plan

1. Apply `rbac-custom-roles-multirole` first.
2. Backend: extend repo/query/handler with filters + paginated envelope; add bulk and
   export endpoints; update API contract docs. Existing single-user endpoints unchanged.
3. Web: update query/mutation hooks for the envelope and new endpoints; rebuild the
   page as a data table with URL-synced state. Deploy together with the backend since
   the list response shape changes.
4. Rollback: revert web + backend together; the single-user endpoints and events are
   untouched, so no data migration is involved.

## Open Questions

- Default `page_size` and the hard max — propose `25` default, `100` max unless you
  prefer otherwise.
- Whether export should also respect the current `sort`, or always export a stable
  canonical order — propose: respect active filters, ignore pagination, sort by name.
