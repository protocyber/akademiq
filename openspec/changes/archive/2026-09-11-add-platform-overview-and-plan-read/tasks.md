## 1. Repository layer (platform-service)

- [x] 1.1 Add `overview_totals()` to `src/repo.rs` returning the tenant count and per-status counts from `platform_tenant` (single `GROUP BY status` query)
- [x] 1.2 Add `overview_usage_totals()` to `src/repo.rs` returning `SUM(student_count)` and `SUM(teacher_count)` from `platform_tenant_stats`, coalescing NULL to 0 for an empty table
- [x] 1.3 Add `list_users(limit, offset)` to `src/repo.rs` mirroring `search_users_by_email` row shape (`UserRow`) with a deterministic `ORDER BY lower(email)`

## 2. Overview endpoint

- [x] 2.1 Add the `GET /api/v1/platform/overview` route to the router in `src/http.rs`
- [x] 2.2 Implement the handler: `require_platform_admin`, call the two repo methods, return `{ data: { tenants_by_status, totals: { tenants, students, teachers } }, meta: {} }`
- [x] 2.3 Verify the response shape matches what `apps/web-admin` already types in `app/lib/api/types.ts` (`Overview`) and renders in `app/pages/index.vue`

## 3. Plan catalog read

- [x] 3.1 Add the `GET /api/v1/platform/plans` route to the router, keeping the existing `POST` on the same path
- [x] 3.2 Implement the handler as `forward_to_billing(GET, "/api/v1/billing/plans")` with `require_platform_admin` and no audit write
- [x] 3.3 Confirm downstream errors pass through `map_downstream_error()` rather than surfacing an empty catalog

## 4. User directory listing

- [x] 4.1 Make `email` optional in `UserSearchQuery` and drop the empty-email `VALIDATION_ERROR` branch in `search_users`
- [x] 4.2 Route the handler to `list_users` when `email` is absent/blank and to `search_users_by_email` when present, reusing the shared `pagination()` helper (`src/http.rs:464`) for the clamp
- [x] 4.3 Return the paginated envelope `meta: { page, page_size }` for the listing path, matching `list_tenants`/`list_audit`

## 5. Projection backfill

- [x] 5.1 Add a `run_upsert "platform.platform_tenant_stats"` block to `apps/backend/scripts/bootstrap-projections.sh`, sourced from `academic_ops.student` and `academic_ops.teacher` grouped by `tenant_id`, guarded by `table_exists` like the sibling blocks
- [x] 5.2 Make the upsert idempotent on the `tenant_id` primary key (`ON CONFLICT DO UPDATE` refreshing counts and `updated_at`)
- [x] 5.3 Run the script against the dev stack and confirm `platform_tenant_stats` reports 195 students / 15 teachers for `TPQ BAITUR ROCHMAN` and 0 for `SMA Negeri 5 Surabaya`

## 6. Contract documentation

- [x] 6.1 Document `GET /overview` in `docs/internal/11_integration_contracts/apis/platform-service-api.md` (response shape, operator gating, projection sourcing)
- [x] 6.2 Document `GET /plans` in the same file, noting the billing-service forward and that reads are not audited
- [x] 6.3 Update the `GET /users` entry: `email` optional, paginated listing when omitted, page-size clamp — and note the behaviour change from the previous `VALIDATION_ERROR`

## 7. Tests

- [x] 7.1 Integration test: `GET /overview` returns correct totals and `tenants_by_status` for seeded projection rows
- [x] 7.2 Integration test: `GET /overview` succeeds with zeroed usage totals when `platform_tenant_stats` is empty
- [x] 7.3 Integration test: `GET /users` with no `email` returns a paginated page; with `email` keeps matching behaviour; oversized `page_size` is clamped
- [x] 7.4 Integration test: all three endpoints reject a non-operator caller with `403` and reject a `typ:"access"` token
- [ ] 7.5 Run the backend suite: `cd apps/backend && cargo test -p platform-service --tests` — skipped for manual backend execution; tests compile clean via `cargo check -p platform-service --tests`

## 8. Verification against the live stack

- [x] 8.1 Obtain an operator token and confirm `GET /overview`, `GET /plans`, and `GET /users` each return `200` with data (previously `404`, `405`, and `400`)
- [x] 8.2 Confirm no `operator_audit` rows were written by the read calls
- [x] 8.3 Confirm `remove-web-admin-mock-backend` is unblocked — the three endpoints answer on the same paths the web-admin client builds

## Manual Backend Tests

- `cd apps/backend && cargo test -p platform-service --tests` (integration tests use Postgres testcontainers; requires Docker)
