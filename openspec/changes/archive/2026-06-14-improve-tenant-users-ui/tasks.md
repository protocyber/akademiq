## 1. Dependency — last-role guard

- [x] 1.1 The `LAST_ROLE` guard on `remove_user_role` is delivered by the separate `fix-last-role-guard` change and is a prerequisite for this one. Do NOT re-implement it here; this change builds on it (the edit modal surfaces `LAST_ROLE`, and the explicit remove-from-tenant action below is the sanctioned off-boarding path it enables). Confirm `fix-last-role-guard` is applied before starting section 2

## 2. Backend — create, update & remove-from-tenant endpoints

- [x] 2.0 Add `PERM_USER_UPDATE = "user.update"` to `common-auth` (`jwt.rs`) and re-export it (`lib.rs`); seed it onto the built-in roles that currently hold `user.invite` (update the role/permission seed + any migration)
- [x] 2.1 Add `CreateTenantUser` command (username, full_name, roles[], optional email/password) and `UpdateTenantUser` command (username/email/full_name) in `commands.rs`, resolving `tenant_id` from the access token, reusing `common-auth::hash_password` for any password, and granting roles in one transaction on create. When `password` is omitted, create a pending/reset-required account (same end state as an unaccepted invitation) rather than requiring a password
- [x] 2.2 Map DB unique-violation on `lower(username)` to `AppError::conflict("USERNAME_TAKEN", ...)` and email uniqueness to its existing conflict; emit `tenant_user.created` / `tenant_user.updated` via the outbox, with the `tenant_user.updated` payload recording which identity fields changed (for the audit-log consumer). Create MUST reject an existing user (no upsert) so the conflict can steer the admin to invitations
- [x] 2.3 Add `POST /api/v1/iam/tenants/me/users` (`create_tenant_user_handler`, gated on `user.invite`) and `PATCH /api/v1/iam/tenants/me/users/:id` (`update_tenant_user_handler`, gated on the new `user.update`) routes in `services/iam-service/src/http.rs`; PATCH returns 404 for non-member users
- [x] 2.4 Validate `username` server-side (required, no `@`, format) returning `VALIDATION_ERROR` field errors
- [x] 2.5 Add `RemoveUserFromTenant` command + `DELETE /api/v1/iam/tenants/me/users/:id` (`remove_tenant_user_handler`, gated on `user.disable`): drop all of the user's roles in the tenant in one transaction, honor the last-admin guard (refuse `LAST_ADMIN`), return 404 for non-members, emit `tenant_user.removed`, and do NOT delete the global user record
- [x] 2.6 Add integration tests: create with unique username (201 + `tenant_user.created`), create with existing username (409 `USERNAME_TAKEN`, no user created), `@` in username (422), non-privileged caller (403), update full_name (200 + `tenant_user.updated`), update to taken username (409), update non-member (404), update without `user.update` (403), remove-from-tenant (user gone from list, global record intact, `tenant_user.removed`), remove last admin (409 `LAST_ADMIN`), remove non-member (404)
- [x] 2.7 Run `cd apps/backend && make test` and confirm green

## 3. Backend — contract docs

- [x] 3.1 Document the new create/update/remove-from-tenant endpoints and `LAST_ROLE` / `USERNAME_TAKEN` codes and the `user.update` permission in `docs/internal/11_integration_contracts/apis/iam-service-api.md`
- [x] 3.2 Add the `tenant_user.created` / `tenant_user.updated` / `tenant_user.removed` events to the IAM event contract docs (leaving `tenant_user.role_assigned` / `role_removed` / `role_changed` names unchanged) and note the last-role invariant in `docs/internal/10_data_design/01_IAM_Service_ERD.md`

## 4. Web — dependencies & shadcn primitives

- [x] 4.1 Add `@tanstack/react-table` and `cmdk` to `apps/web` with pinned versions
- [x] 4.2 Add shadcn `table` and `dropdown-menu` primitives under `src/components/ui/`
- [x] 4.3 Add shadcn `command` primitive and build a reusable multiselect combobox (Command + Popover) under `src/components/ui/`
- [x] 4.4 Add a thin `src/components/ui/data-table.tsx` wired for `manualPagination`/`manualSorting`

## 5. Web — schemas & query/mutation hooks

- [x] 5.1 Add `createTenantUserSchema` and `updateTenantUserSchema` in `src/lib/schemas/` with backend-matching field names; reuse the existing `username` rule from `src/lib/schemas/signup.ts` (extract to a shared `username` schema instead of re-declaring the `^[a-z][a-z0-9_-]{2,63}$` regex) so the rule stays in one place; export inferred types
- [x] 5.2 Add Vitest specs for both schemas (≥1 valid, ≥1 invalid case each)
- [x] 5.3 Add `useCreateTenantUser`, `useUpdateTenantUser`, and `useRemoveTenantUser` mutation hooks in `src/lib/query/mutations/use-tenant-users.ts`, invalidating `TENANT_USERS_QUERY_KEY`
- [x] 5.4 Add `USERNAME_TAKEN` (incl. the create-time "already has an account, use invitation" variant), `LAST_ROLE`, and remove-from-tenant confirmation copy to `src/lib/errors/messages.ts`

## 6. Web — rebuild /settings/users

- [x] 6.1 Rename the page heading to "Pengguna"
- [x] 6.2 Replace the CSS-grid table with the shadcn data table: role chips column, status, sortable columns, header + per-row selection checkboxes, server-driven pagination
- [x] 6.3 Preserve URL-synced search/role/status/page/sort using the existing `tenant-users-params` helpers (debounced search)
- [x] 6.4 Port bulk enable/disable/change-role into a shadcn dropdown-menu bulk action control with per-user outcome reporting; keep CSV export. Bulk "change role" MUST be implemented via the add/remove role endpoints (so `LAST_ROLE`/`LAST_ADMIN` guards run) and MUST NOT call the single-role `change_user_role` replace path
- [x] 6.5 Add the add-user modal (username, full_name, roles multiselect, optional email/password) wired to `useCreateTenantUser`; surface `USERNAME_TAKEN` as a `username` field error via `applyServerFieldErrors`, with the create-time variant steering the admin to the invitation flow
- [x] 6.6 Add the edit-user modal: identity-field edit via `useUpdateTenantUser`, role add/remove (surfacing `LAST_ADMIN`/`LAST_ROLE`), reset-password with confirmation, enable/disable toggle, and a confirmed "remove from tenant" action via `useRemoveTenantUser`
- [x] 6.7 Remove the inline per-row "tambah role" selector and the inline reset-password button
- [x] 6.8 Move the invitations ("Undangan") section below the main table
- [x] 6.9 Replace the invite modal's roles checkbox grid with the shadcn multiselect dropdown (≥1 role required)

## 7. Verification

- [x] 7.1 Run web lint/typecheck and Vitest in `apps/web`; fix failures
- [ ] 7.2 Manually verify the bug scenario: removing `fitrah.pro@gmail.com`'s last role in "Demo Premium" is refused with `LAST_ROLE` and the user stays in the list
- [ ] 7.3 Manually verify create-user (unique + duplicate username), edit-user identity update, and invite multiselect flows
