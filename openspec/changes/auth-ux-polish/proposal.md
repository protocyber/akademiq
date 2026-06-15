## Why

Three rough edges in the authenticated-session UX, all isolated from the
in-flight academic redesigns:

- **Login button stops spinning before navigation finishes.** On a successful
  login the button's loading state is tied to the mutations
  (`login`/`myTenants`/`enterTenant` in `app/login/page.tsx`), but once those
  resolve the spinner clears while `router.push(next)` is still navigating — the
  enabled button invites a second click during the gap.
- **Token refresh is purely reactive.** `lib/api/client.ts` only refreshes
  *after* a request comes back 401 (`EXPIRED_ACCESS_TOKEN`). The user can hit a
  visible error/redirect on the first call after expiry. The access token
  already carries an `exp` claim (`lib/auth/access-claims.ts`), so we can refresh
  proactively in the background before it lapses.
- **Email verification status is invisible.** `useMe` returns
  `email_verified: boolean`, but no screen surfaces it. Users and admins can't
  tell a verified email from an unverified one in the edit-user form (or
  wherever email is shown).

## What Changes

- **MODIFIED login flow** — keep the submit button in its loading/disabled state
  through the post-login navigation, not just the mutations, so it cannot be
  clicked again while the app routes to the dashboard/tenant-select.
- **MODIFIED token lifecycle** — add **proactive background refresh**: schedule a
  refresh shortly before the access token's `exp`, reusing the existing
  single-flight `tryRefresh()` guard, so a logged-in user stays signed in without
  hitting an expiry-driven error or redirect. The reactive 401 path stays as a
  safety net.
- **MODIFIED email display** — show a verification indicator (a check icon when
  `email_verified` is true, an alert icon when false) next to the email in the
  edit-user form, and anywhere else email is prominently displayed.

## Capabilities

### Modified Capabilities

- `web-auth-onboarding`: the login submit stays loading through navigation, and
  the API client refreshes the access token proactively in the background before
  expiry (in addition to the existing on-401 refresh).
- `tenant-user-management`: the edit-user view surfaces an email-verification
  indicator driven by `email_verified`.

## Impact

- **Web (`apps/web`):**
  - `app/login/page.tsx` — hold loading across `router.push`.
  - `lib/api/client.ts` (+ a small scheduler) — decode `exp` and schedule a
    pre-expiry refresh via the existing `tryRefresh()`; start/reset on token set,
    clear on logout.
  - Edit-user form (and shared email display) — verification icon from
    `email_verified`.
- **No backend impact** — refresh endpoint, `exp` claim, and `email_verified`
  already exist.
- **Out of scope:** the avatar dropdown / theme switcher (`shell-and-theming`),
  the passwordless-invite flow (`iam-passwordless-invite`), and any change to
  token TTLs or the refresh contract itself.
