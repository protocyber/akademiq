## Why

`apps/web-admin` ships a bundled mock backend: 17 Nuxt server routes under
`server/api/**` plus `server/utils/mock.ts` that answer the entire
`/api/v1/platform` and platform-auth surface with fabricated data. This was
deliberate scaffolding — `add-platform-admin-web/design.md:132` lists "Switch from
mocks to the live platform-service once it lands" as the final step — but that step
was never taken. platform-service has since landed and runs.

The leftover mock is now actively harmful:

- **The same build behaves differently per origin.** `NUXT_PUBLIC_IAM_BASE_URL` and
  `NUXT_PUBLIC_PLATFORM_BASE_URL` are empty, so requests are same-origin. Opened at
  `localhost:3010` the app hits its own mock and shows invented data; opened through
  the reverse proxy, `/api/v1/platform/*` is routed to the real service. Same code,
  two realities.
- **It hid a real gap.** Overview and Plans looked finished for months while the
  backend routes returned `404` and `405`. The mock even hard-codes
  `students: 960, teachers: 72` in `server/api/v1/platform/overview.get.ts` — numbers
  an operator could easily mistake for real telemetry.
- **The mock login accepts any password.** `server/api/v1/iam/platform/auth/login.post.ts`
  succeeds for any non-empty password except the literal string `invalid`. If the
  base-URL config is ever blank in a deployed environment, that is an authentication
  bypass reachable from the browser.
- **The e2e suite tests the mock, not the product.** `tests/e2e/operator-flow.spec.ts`
  logs in as `operator@example.com` / `secret` and suspends `SMA Negeri 1 Surabaya` —
  fixtures that exist only in `mock.ts`.

With `add-platform-overview-and-plan-read` supplying the three missing read
endpoints, nothing depends on the mock anymore.

## What Changes

- **REMOVED: the entire `apps/web-admin/server/` tree** — 17 route handlers plus
  `server/utils/mock.ts`. The app becomes a pure client of the real backend.
  **BREAKING** for anyone running the app with empty base URLs: requests that used to
  be answered locally now require a reachable backend.
- **Real base URLs by default.** `NUXT_PUBLIC_IAM_BASE_URL` and
  `NUXT_PUBLIC_PLATFORM_BASE_URL` are set in `.env.example` so a fresh clone talks to
  a real backend, and `localhost:3010` and the proxied origin behave identically.
- **MODIFIED: the Users screen becomes a browsable directory.** It currently requires
  typing an email before anything appears, because the endpoint demanded it. With
  `email` now an optional filter, the screen lists users on load and the input
  filters that list.
- **MODIFIED: the e2e suite runs read-only against the live backend.** The flow
  becomes login → tenants → tenant detail → audit, with credentials and expected
  fixtures supplied by environment rather than hard-coded. The suspend/reactivate
  assertions are dropped: run against a real stack they mutate real tenant state.
- **Corrected stale guidance** in `nuxt.config.ts:38-42`, whose comment instructs the
  reader to leave base URLs empty to reach "the bundled Nuxt server-route mocks".
- `playwright.config.ts` still starts the dev server with `npm run dev` although the
  app is now pnpm-managed; fixed while the file is being touched.

## Capabilities

### New Capabilities

<!-- None. This change removes scaffolding and retargets existing capabilities at the
     real backend. -->

### Modified Capabilities

- `web-admin-foundation`: adds a requirement that the app has no bundled backend and
  is configured against real service origins, so behaviour does not depend on which
  origin it is served from.
- `web-admin-user-management`: the global user directory is browsable without a
  search term; email becomes a filter over a listed directory rather than a
  precondition for any result.
- `web-admin-observability`: the overview dashboard is sourced from the live
  `GET /api/v1/platform/overview` endpoint, and reports real zeros rather than
  fabricated totals.

## Impact

- **Depends on `add-platform-overview-and-plan-read`.** That change must land first;
  removing the mock before the read endpoints exist would leave Overview, Plans, and
  the Users listing broken.
- **`apps/web-admin`** — deletes `server/`; edits `app/pages/users/index.vue` and
  `app/lib/queries/users.ts` for the listing behaviour; updates `.env.example`,
  `nuxt.config.ts`, `playwright.config.ts`, and rewrites `tests/e2e/operator-flow.spec.ts`.
- **Local setup** — every developer must set the two base URLs in their own `.env`
  (gitignored). Without them the app has no backend at all, where previously it
  silently fell back to the mock.
- **Testing** — e2e now requires a running backend stack and a real operator account
  (`akademiq platform create-operator`). This is a genuine cost: the suite is no
  longer self-contained. Accepted because a self-contained suite that only ever
  exercised fixtures is what let the `404`/`405` gap survive undetected.
- **Out of scope:** unit tests under `tests/unit/` (they stub `fetch` directly and do
  not touch `server/`), and any redesign of the Plans or Overview screens beyond
  pointing them at real data.
