## Context

Two small, independent UX defects remain in the authenticated session. They share
no code path; the only reason to group them is that both are low-risk auth/account
polish suitable for one change.

Current state:

- **Login loading** — `src/app/login/page.tsx` binds the submit button's
  `disabled`/`loading` to `login.isPending || myTenants.isPending ||
  enterTenant.isPending`. After the mutations resolve, `router.push(next)` (or
  `/tenant-select`) runs while those flags are already `false`, so the button is
  briefly enabled mid-navigation.
- **Email verification** — `email_verified` exists on the `user` table and is
  returned by `/me` (`useMe`, `use-me.ts:16`). The tenant-users path does not carry
  it: `TenantUserView` (iam-service `queries.rs:151`) and the web `TenantUser` type
  (`use-tenant-users.ts:21`) both omit the field, and no UI renders it.

Constraints: web is shadcn/ui-only with a two-tier loading convention
(`web-auth-onboarding`); backend follows `apps/backend/CONVENTIONS.md`. The
tenant-users change is read-only (the column already exists), so no migration and
no events are involved.

## Goals / Non-Goals

**Goals:**

- Keep the login submit button loading/disabled continuously from submit through
  post-login navigation, restoring it on failure.
- Surface `email_verified` as an accessible indicator in the user's own profile
  view and in the tenant user-management edit-user view.
- Extend the tenant-users API and web type with `email_verified` so the edit-user
  indicator has data.

**Non-Goals:**

- Proactive/background token refresh (dropped — the reactive on-401 path already
  prevents auto-logout). No change to token TTLs or the refresh contract.
- Any new migration (the `email_verified` column already exists).
- Changes to the avatar dropdown / theme switcher or the passwordless-invite flow.

## Decisions

**1. Hold login loading with a local `navigating` flag, OR-ed into the button.**
Add `const [navigating, setNavigating] = React.useState(false)` in `LoginForm`.
Set it `true` immediately before each `router.push` on the success branches; the
button's `disabled`/`loading` becomes `login.isPending || myTenants.isPending ||
enterTenant.isPending || navigating`. In the `catch` block, call
`setNavigating(false)` so retry works. Because the component unmounts on
successful navigation, the flag never needs an explicit reset on success.

- *Alternative considered:* derive loading purely from a router/transition hook
  (`useTransition`/`router.events`). App Router does not expose navigation-complete
  events cleanly, and the explicit flag is simpler and local. The flag is set on
  every push branch (single-tenant fast path, 0-tenant, N-tenant) so no enabled gap
  remains. The `PASSWORD_NOT_SET` branch also pushes — set the flag there too.

**2. One reusable `EmailVerifiedBadge` component, shared by both views.**
The indicator appears in at least two places, so factor a small shadcn-based
component (Lucide `Check` / `AlertTriangle` plus a visible or `sr-only` label and a
`title`). State is communicated by label/title, not color alone, satisfying the
accessibility scenario.

- *Alternative considered:* inline the icon in each view. Rejected — duplicates the
  accessibility wiring and risks divergence between the two surfaces.

**3. Add `email_verified` to the tenant-users read path end-to-end.**
Backend chain (read-only, no migration):
`repo.rs` SELECT (`u.email_verified`) → `MembershipUserRow` field →
`map_membership_user_row` (`row.get("email_verified")`) → `fold_tenant_user_rows`
passthrough → `TenantUserView` field (`#[derive(Serialize)]` emits it). Apply the
same column to both the `list_tenant_users` and `export_tenant_users` row builders,
which already share `tenant_user_rows_for_ids`, so one SELECT edit covers both.
Web: add `email_verified: boolean` to the `TenantUser` type.

- *Alternative considered:* fetch `/me`-style verification per row on demand.
  Rejected — N extra requests for a list; the field is one cheap column already in
  the row's table.

## Risks / Trade-offs

- **Stale frontend type vs. backend response** → The web `TenantUser` type must be
  updated in the same change; otherwise the field is silently dropped at the type
  boundary. Mitigation: the tasks pair the backend and web type edits.
- **iam-service serialization test drift** → `email_verified` already appears in
  `services/iam-service/tests/integration.rs`; adding it to `TenantUserView` may
  shift expected JSON. Mitigation: run `cd apps/backend && make test` (or the
  iam-service target) and update fixtures if needed.
- **Login flag left set on an unhandled branch** → If a future success branch adds
  a push without setting `navigating`, the gap reappears; if a failure branch
  forgets `setNavigating(false)`, the button stays stuck. Mitigation: set the flag
  at every `router.push` and reset once in the shared `catch`.

## Migration Plan

No data migration. Ship backend (`iam-service`) and web together so the web type
and UI match the new API field. Rollback is a plain revert of both submodule
commits; the added column read has no persistent side effects.
