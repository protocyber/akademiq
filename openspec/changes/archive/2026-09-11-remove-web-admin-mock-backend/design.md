## Context

`apps/web-admin` was built ahead of its backend. `add-platform-admin-web/design.md`
planned for this explicitly: "during early dev, mock the `/api/v1/platform` responses
so UI work proceeds" (line 110), with step 9 of the implementation plan being "Switch
from mocks to the live platform-service once it lands" (line 132). platform-service
landed; step 9 never ran.

What remains is `apps/web-admin/server/`: 17 route handlers covering platform auth,
tenants, users, plans, audit, and overview, backed by an in-memory `mock.ts`. The
switch is invisible rather than explicit — `client.ts` builds request URLs from
`useRuntimeConfig().public.iamBaseUrl` / `platformBaseUrl` (`app/lib/api/client.ts:25-29`),
and both are empty, so every request is same-origin and lands on the Nuxt server
routes. Behind the reverse proxy, path-prefix rules send `/api/v1/platform/*` and
`/api/v1/iam/*` to the real services before Nuxt ever sees them. The mock's reach is
therefore decided by the origin the operator happens to type.

This change deletes the mock and configures the real origins. It is the second half
of a pair: `add-platform-overview-and-plan-read` supplies the `GET /overview`,
`GET /plans`, and unfiltered `GET /users` endpoints that the mock was covering for.

## Goals / Non-Goals

**Goals:**
- One backend, one behaviour, regardless of the origin the app is served from.
- Remove the credential-accepting login handler from the shipped app.
- Make the Users screen usable as a directory now that the endpoint supports listing.
- Leave the e2e suite meaningful rather than tautological.

**Non-Goals:**
- Redesigning the Overview or Plans screens; they are pointed at real data as-is.
- Changing `app/lib/api/client.ts` request/refresh logic — it already works against
  the real backend and needs no edit.
- Unit tests under `tests/unit/`, which stub `fetch` directly and never touch
  `server/`.
- Providing an offline/demo mode (see Open Questions).

## Decisions

### D1: Delete the whole `server/` tree, do not keep it behind a flag

`server/api/**` and `server/utils/mock.ts` are removed outright rather than gated on
an env flag or a dev-only condition.

- **Why:** a flag preserves exactly the failure this change exists to remove — two
  behaviours in one build, with the active one decided by configuration that is easy
  to get wrong. The login mock in particular is an authentication bypass whenever the
  base URLs are blank; the only robust fix is for the code not to exist.
- **Alternative rejected:** keep the mock behind `NODE_ENV !== 'production'`. Dev is
  precisely where the confusion happened, so this preserves the bug where it hurt.
- **Recovery:** the handlers remain in git history if a demo mode is ever wanted; see
  Open Questions for the shape that should take.

### D2: Configure absolute same-origin base URLs

`.env.example` sets both `NUXT_PUBLIC_IAM_BASE_URL` and
`NUXT_PUBLIC_PLATFORM_BASE_URL` to the proxied admin origin, matching the pattern
`apps/web` already uses (absolute same-origin URLs, no Nuxt rewrite, path routing done
by the proxy).

- **Why:** with real values, a same-origin dev request and a proxied request resolve
  to the same backend. Leaving them empty is what made the mock reachable.
- **Trade-off:** developers without the proxy must point these at their own backend
  (e.g. `http://127.0.0.1:8087` and `:8081`). That is a real setup cost, but it is
  explicit configuration rather than a silent fallback.

### D3: Users screen lists first, filters second

`useUserSearchQuery` currently sets `enabled` only when an email is present
(`app/lib/queries/users.ts:22`), so the screen shows nothing until typing. That gate is
removed: the query runs on mount with pagination, and the email input becomes a
filter parameter.

- **Why:** the gate existed because the endpoint rejected an empty `email`. Once the
  backend lists, the UI restriction is an artifact of a constraint that no longer
  exists.
- **Trade-off:** the screen now issues a request on load. Bounded by the server-side
  page-size clamp.

### D4: E2E goes read-only

The flow becomes login → tenants list → tenant detail → audit view. The suspend and
reactivate assertions are dropped.

- **Why:** against the live backend the current test suspends a real tenant
  (`operator-flow.spec.ts:25-30`). A test that mutates shared dev state on every run
  is a liability, and there is no fixture isolation to make it safe.
- **Alternative rejected:** create a throwaway tenant per run and suspend that. It is
  the better test, but tenant creation is a billing-service flow with events and
  side-effects; standing that up belongs in its own change.
- **Trade-off:** suspend/reactivate lose e2e coverage. They keep backend integration
  coverage, and the gap is recorded in Open Questions.

### D5: Credentials and fixtures come from the environment

The e2e reads the operator email/password from environment variables and asserts on
structural elements (headings, table presence) rather than fixture names like
`SMA Negeri 1 Surabaya`.

- **Why:** those names exist only in `mock.ts`. Real tenant names differ per
  environment, so asserting on them would make the suite environment-specific.

## Risks / Trade-offs

- **E2E now needs a live stack plus a real operator account** → no longer
  self-contained, and CI must either provision that or skip the suite. Accepted: a
  self-contained suite that only exercised its own fixtures is what allowed the
  `404`/`405` gap to survive. Recorded as an explicit task so CI implications are not
  discovered later.
- **Blank base URLs now break the app instead of silently mocking** → intended, but it
  will surprise anyone with an existing `.env`. Mitigated by shipping real values in
  `.env.example` and calling it out in the proposal Impact.
- **Ordering hazard** → landing this before `add-platform-overview-and-plan-read`
  leaves three screens broken. Mitigated by the stated dependency and a verification
  task that checks the endpoints answer before the mock is deleted.
- **Overview will show real zeros for tenants without academic data** → correct
  behaviour, and specified as such, but it will look like a regression next to the
  mock's fabricated 960/72.

## Migration Plan

1. Confirm `add-platform-overview-and-plan-read` is deployed and its three endpoints
   answer with an operator token.
2. Set the two base URLs in every local `.env` (values shipped in `.env.example`).
3. Delete `server/`, update the Users screen, rewrite the e2e.
4. Verify the app on both the local dev origin and the proxied origin and confirm they
   agree.

Rollback: revert the commit. The mock returns, along with the dual-behaviour problem —
so prefer fixing forward unless the backend itself is down.

## Open Questions

- Should a demo mode exist for screenshots and offline demos? If so it belongs in a
  dedicated, clearly-labelled fixture app or Storybook-style harness, not in server
  routes that shadow the real API. Not scoped here.
- Should suspend/reactivate regain e2e coverage via a per-run throwaway tenant, once
  tenant provisioning is scriptable from the test harness?
- Does CI run this suite, and against which backend? Unresolved, and it determines
  whether `test:e2e` stays in the default test target.
