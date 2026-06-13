## 0. Prerequisite

- [x] 0.1 Confirm `rbac-custom-roles-multirole` is applied first (multi-role chips, `perms[]` token, role catalog); this change builds on it

## 1. Backend — list query (iam-service)

- [x] 1.1 Add a filter/sort/page params struct to `list_tenant_users` input (`search`, `role`, `status`, `page`, `page_size`, `sort`)
- [x] 1.2 Extend `repo.rs` `list_tenant_users` to build a parameterized query: `ILIKE` over `full_name`/`email`/`username`, equality on role + status, `ORDER BY` from a column allow-list, `LIMIT`/`OFFSET`
- [x] 1.3 Add a `COUNT(*)` over the same `WHERE` for `meta.total`
- [x] 1.4 Clamp `page_size` to a max (propose 100, default 25) and validate `sort` against the allow-list
- [x] 1.5 Update `http.rs` list handler to parse query params and return the `{ data, meta:{page,page_size,total} }` envelope (BREAKING shape change)

## 2. Backend — bulk operations (iam-service)

- [x] 2.1 Add `POST /tenants/me/users/bulk/enable` reusing the per-user enable command, one `tenant_user.*` event per user via outbox
- [x] 2.2 Add `POST /tenants/me/users/bulk/disable` reusing the per-user disable command + event each
- [x] 2.3 Add `POST /tenants/me/users/bulk/role` reusing the per-user role command + event each (respects last-admin guard)
- [x] 2.4 Return a per-user result list (success/failure + reason) so partial failures are reported; ensure no bulk-delete route exists

## 3. Backend — CSV export (iam-service)

- [x] 3.1 Add `GET /tenants/me/users/export` that runs the same filtered query (no pagination) and streams `text/csv`
- [x] 3.2 Set `Content-Disposition` + correct content type so it downloads and opens in spreadsheets

## 4. Backend — tests & contract

- [x] 4.1 Tests: search/filter/sort/pagination correctness and `meta.total`
- [x] 4.2 Tests: `page_size` clamp and `sort` allow-list reject (no arbitrary SQL)
- [x] 4.3 Tests: bulk enable/disable/role emit one event per user; partial-failure reporting; last-admin guard honored
- [x] 4.4 Tests: export honors filters and ignores pagination
- [x] 4.5 Update `docs/internal/11_integration_contracts/apis/` for new list params, paginated envelope, bulk endpoints, and export endpoint
- [x] 4.6 Run backend `make test` for iam-service

## 5. Web — data layer (apps/web)

- [x] 5.1 Add a typed params parser/serializer for `search/role/status/page/page_size/sort` (single source of truth for URL + query key + request)
- [x] 5.2 Update `use-tenant-users.ts` query to send params, consume the paginated envelope, and key the cache by params
- [x] 5.3 Add bulk mutations (enable/disable/role) and a reset-password mutation in `use-tenant-users.ts` mutations
- [x] 5.4 Add an export helper that triggers a CSV download with the active filters

## 6. Web — UI rebuild (apps/web)

- [x] 6.1 Rebuild `settings/users/page.tsx` as a shadcn/ui data table (search input, role + status filter selects, sortable columns, pagination controls)
- [x] 6.2 Sync view state to the URL via `router.replace`, seed from `searchParams` on load, debounce search; no history spam
- [x] 6.3 Add header + per-row selection checkboxes and a bulk action bar (enable / disable / change role); surface per-user outcomes via toast/summary
- [x] 6.4 Add Export button and per-row reset-password action with a confirm step; gate controls on `perms[]`
- [x] 6.5 Preserve the existing invite flow and pending-invitations card

## 7. Web — tests & checks

- [x] 7.1 Tests: URL sync restores view on refresh and from a shared URL
- [x] 7.2 Tests: filtering/pagination issue server requests; bulk action result handling
- [x] 7.3 Run web lint/typecheck and `make test` for web
