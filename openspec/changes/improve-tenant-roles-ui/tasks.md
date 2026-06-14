## 1. Backend — list query: search, sort, pagination, user_count

- [ ] 1.1 Extend `RoleRepo::list_roles_for_tenant` (`iam-service/src/repo.rs:907`) to accept search/sort/page/page_size params and return rows plus a total count; add a `user_count` per role computed from `user_tenant_role` scoped to the calling tenant (built-in roles counted per-tenant, not globally). Search matches role name or code case-insensitively; default order stays `is_builtin DESC, code`
- [ ] 1.2 Add `user_count: i64` to `RoleWithPerms` (or a list-specific row struct) and include it in `role_view` (`http.rs:786`)
- [ ] 1.3 Add a `TenantRolesQuery` extractor (mirror `TenantUsersQuery`) and update `list_roles_handler` (`http.rs:796`) to parse it and return `meta { page, page_size, total }`
- [ ] 1.4 Confirm sort keys map to stable SQL: `name`/`-name` → `r.name`, `type`/`-type` → `r.is_builtin`, `users`/`-users` → the computed count

## 2. Backend — bulk delete endpoint

- [ ] 2.1 Add a `BulkDeleteRoles` command in `commands.rs` that pre-validates every id (custom role of this tenant, not built-in, `count_role_holders == 0`) and rejects the whole request on the first violation (`BUILT_IN_ROLE_IMMUTABLE` / `ROLE_IN_USE` / 404), reusing the existing `delete_role` guard logic; on success deletes all ids in one transaction and emits one `role.deleted` event per role
- [ ] 2.2 Add `POST /api/v1/iam/tenants/me/roles/bulk/delete` route (`bulk_delete_roles_handler`, gated on `role.manage`) in `http.rs`
- [ ] 2.3 Add integration tests: list with search/sort/pagination + `user_count` correctness (incl. built-in counted per-tenant), bulk delete all-custom-unused (success + `role.deleted` per role), bulk delete with a built-in id (403, nothing deleted), bulk delete with an in-use role (409 `ROLE_IN_USE`, nothing deleted), non-privileged caller (403)
- [ ] 2.4 Run `cd apps/backend && make test` and confirm green

## 3. Backend — contract docs

- [ ] 3.1 Document the new `GET /tenants/me/roles` query params + `meta` + `user_count`, and the `POST /tenants/me/roles/bulk/delete` endpoint (all-or-nothing, `BUILT_IN_ROLE_IMMUTABLE` / `ROLE_IN_USE` codes) in `docs/internal/11_integration_contracts/apis/iam-service-api.md`

## 4. Web — reusable AlertDialog primitive

- [ ] 4.1 Add `src/components/ui/alert-dialog.tsx` (shadcn AlertDialog: Root/Trigger/Content/Header/Footer/Title/Description/Action/Cancel) following the existing `dialog.tsx` styling conventions
- [ ] 4.2 (Scope guard) Do NOT retrofit existing `window.confirm` call sites (`users/page.tsx`) in this change — introduce the component only

## 5. Web — schemas & query/mutation hooks

- [ ] 5.1 Add `src/lib/schemas/tenant-roles-params.ts` (mirror `tenant-users-params.ts`): `TenantRolesParams`, `TenantRolesSort` (`name|-name|type|-type|users|-users`), defaults, `parse`/`serialize`/`paramsKey` helpers
- [ ] 5.2 Add Vitest specs for the params parse/serialize round-trip (default omitted, non-defaults preserved, invalid sort falls back)
- [ ] 5.3 Update `src/lib/query/queries/use-tenant-roles.ts`: add `user_count` to the `TenantRole` type, make `useTenantRoles(params)` pass query params and return `{ data, meta }` (keep `useTenantPermissions` unchanged — it is the palette, not a paginated list)
- [ ] 5.4 Add `useBulkDeleteTenantRoles` mutation in `src/lib/query/mutations/use-tenant-roles.ts`, invalidating `TENANT_ROLES_QUERY_KEY`
- [ ] 5.5 Add bulk-delete confirmation copy and `ROLE_IN_USE` / `BUILT_IN_ROLE_IMMUTABLE` messages to `src/lib/errors/messages.ts`

## 6. Web — rebuild /settings/roles

- [ ] 6.1 Replace the `RoleCard` grid with the shadcn `DataTable`: columns Nama (name + code subtitle), Tipe (Bawaan/Custom badge), Jumlah User (`user_count`), header + per-row selection checkboxes, server-driven pagination
- [ ] 6.2 Add a per-row actions dropdown (Edit / Clone / Hapus); Edit and Hapus disabled for built-in roles, Clone always available
- [ ] 6.3 Add a search box and keep search/sort/pagination URL-synced via the new `tenant-roles-params` helpers (debounced search, mirroring the users screen)
- [ ] 6.4 Add the bulk action bar: Hapus disabled whenever the selection contains a built-in role, with red helper text to deselect built-in roles; when all-custom, Hapus opens the AlertDialog then calls `useBulkDeleteTenantRoles` and surfaces `ROLE_IN_USE`/`BUILT_IN_ROLE_IMMUTABLE` via toast
- [ ] 6.5 Preserve the existing create/edit/clone `RoleDialog` and its permission checkbox grid unchanged

## 7. Verification

- [ ] 7.1 Run web lint/typecheck and Vitest in `apps/web`; fix failures
- [ ] 7.2 Manually verify: search + sort by Jumlah User reflected in URL and survives reload; built-in role shows only Clone; bulk delete disabled with a built-in selected; confirmed bulk delete of custom roles works; deleting an in-use role is refused with `ROLE_IN_USE`
