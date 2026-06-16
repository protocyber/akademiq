## Why

Two isolated rough edges remain in the authenticated-session UX. The earlier
`auth-ux-polish` proposal also bundled a proactive token-refresh item, but the
auto-logout pain it targeted is already resolved by the reactive on-401 refresh
path in `lib/api/client.ts` (now tolerant of `EXPIRED_ACCESS_TOKEN`,
`UNAUTHENTICATED`, and `INVALID_TOKEN`, with tenant-select recovery). This change
drops the refresh work entirely and keeps only the two genuine, still-open
defects:

- **Login button stops spinning before navigation finishes.** The submit
  button's loading state is tied to the `login`/`myTenants`/`enterTenant`
  mutations (`src/app/login/page.tsx`). Once those resolve the spinner clears
  while `router.push(next)` is still navigating — the re-enabled button invites a
  second click during the gap.
- **Email verification status is invisible.** The DB and APIs already carry
  `email_verified`, but no screen surfaces it. `useMe` exposes it for the signed-in
  user, yet the tenant user-management list/edit view does not show it — and the
  tenant-users API (`TenantUserView`) does not even return the field.

## What Changes

- **MODIFIED login flow** — keep the submit button disabled and in its loading
  state through the post-login navigation, not just while the mutations are
  pending, so it cannot be clicked again during the route transition. The failure
  path still restores the button for retry.
- **ADDED email-verification indicator** — show a verification indicator (check
  icon when `email_verified` is true, alert icon when false, with an accessible
  label so state is not color-only) in two places:
  - the signed-in user's own profile/account view (driven by `useMe`), and
  - the tenant user-management edit-user view (driven by the tenant-users list).
- **MODIFIED tenant-users API** — extend `TenantUserView` (iam-service) and the
  web `TenantUser` type to include `email_verified`, so the edit-user indicator
  has data. This is a read-only field addition: the `email_verified` column
  already exists on the `user` table, so **no migration** is required.

## Capabilities

### Modified Capabilities

- `web-auth-onboarding`: the login submit stays loading/disabled through
  navigation (failure restores it).
- `tenant-user-management`: the tenant-users query exposes `email_verified`, and
  the edit-user view surfaces a verification indicator.

## Impact

- **Web (`apps/web`):**
  - `src/app/login/page.tsx` — hold loading across `router.push` via a local
    `navigating` flag; reset it on the failure path.
  - `src/lib/query/queries/use-tenant-users.ts` — add `email_verified` to the
    `TenantUser` type.
  - `src/app/settings/users/page.tsx` — render the indicator in the edit-user
    view; a small reusable `EmailVerifiedBadge` (shadcn-based) shared with the
    profile view.
  - Profile/account view — render the same indicator from `useMe`.
- **Backend (`apps/backend/services/iam-service`):**
  - `src/queries.rs` — add `email_verified` to `TenantUserView` and propagate it
    through `fold_tenant_user_rows`.
  - `src/repo.rs` — add `u.email_verified` to the tenant-user SELECT, the
    `MembershipUserRow` struct, and `map_membership_user_row`.
  - **No migration** — the `email_verified` column already exists.
- **Out of scope:** proactive/background token refresh (dropped — reactive path
  already prevents auto-logout), token TTLs, the refresh contract, the avatar
  dropdown / theme switcher, and the passwordless-invite flow.
