## 1. Login loading through navigation (web)

- [x] 1.1 Add a local `navigating` state to `LoginForm` in `src/app/login/page.tsx`
- [x] 1.2 Set `navigating` true immediately before every `router.push` (single-tenant fast path, 0-tenant, N-tenant, and the `PASSWORD_NOT_SET` redirect)
- [x] 1.3 OR `navigating` into the submit button's `disabled` and `loading` props
- [x] 1.4 Reset `navigating` to false in the `catch` block so retry works after a failure
- [x] 1.5 Verify no enabled gap: button stays loading from submit through navigation on both the single-tenant and tenant-select paths

## 2. tenant-users API exposes email_verified (backend iam-service)

- [x] 2.1 Add `u.email_verified` to the SELECT in `tenant_user_rows_for_ids` (`src/repo.rs`)
- [x] 2.2 Add `email_verified: bool` to `MembershipUserRow` (`src/repo.rs`)
- [x] 2.3 Read the column in `map_membership_user_row` via `row.get("email_verified")`
- [x] 2.4 Add `email_verified: bool` to `TenantUserView` (`src/queries.rs`) and pass it through `fold_tenant_user_rows`
- [x] 2.5 Run `cd apps/backend && make test` for iam-service and update any JSON fixtures in `tests/integration.rs` affected by the new field

## 3. Email-verified indicator (web)

- [x] 3.1 Add `email_verified: boolean` to the `TenantUser` type in `src/lib/query/queries/use-tenant-users.ts`
- [x] 3.2 Create a reusable shadcn-based `EmailVerifiedBadge` (Lucide `Check`/`AlertTriangle` + accessible label/title, not color-only)
- [x] 3.3 Render the indicator in the tenant user-management edit-user view (`src/app/settings/users/page.tsx`) using the row's `email_verified`
- [x] 3.4 Render the same indicator in the signed-in user's profile/account view driven by `useMe`

## 4. Verify

- [x] 4.1 `pnpm lint` and `pnpm build` (or typecheck) pass in `apps/web`
- [x] 4.2 Manually verify: rapid double-click on login submit cannot fire a second request during navigation
- [x] 4.3 Manually verify: verified vs unverified email render the correct indicator in both the profile view and the edit-user view
- [x] 4.4 Confirm the tenant-users response includes `email_verified` for each row
