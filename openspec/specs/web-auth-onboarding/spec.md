# web-auth-onboarding Specification

## Purpose

Specifies frontend requirements for the web client's authentication and onboarding flows, detailing route accessibility, styling boundaries (shadcn/ui), data-fetching standards (TanStack Query), unified loading state design, validation handling, multi-step registration forms, auth middleware token handling, and module settings page UI.

## Requirements

### Requirement: Web app SHALL provide registration, login, dashboard, and modules pages

The Next.js app MUST ship at minimum these routes: `/register`, `/login`,
`/dashboard`, and `/settings/modules`. Routes other than `/register` and
`/login` MUST require an authenticated session and redirect to `/login`
when no valid session is present.

#### Scenario: Unauthenticated user visiting /dashboard is redirected

- **WHEN** an unauthenticated client navigates to `/dashboard`
- **THEN** the response redirects to `/login` and the URL after redirect contains `?next=/dashboard`

#### Scenario: Authenticated user visiting /login is redirected to dashboard

- **WHEN** an authenticated client (valid access token in cookie or local storage) navigates to `/login`
- **THEN** the response redirects to `/dashboard`

### Requirement: UI primitives SHALL come from shadcn/ui only

All interactive UI MUST be composed from shadcn/ui components installed
into `components/ui/` via the shadcn CLI (New York style, Tailwind v4).
Feature components and pages MUST NOT use the native HTML elements
`<button>`, `<input>`, `<select>`, `<textarea>`, raw `<form>` without
React Hook Form wiring, or `<a>` for in-app navigation. Structural
elements (`<div>`, `<section>`, `<main>`, `<header>`, `<nav>`, `<ul>`,
`<li>`, `<p>`, `<span>`, headings) remain allowed. ESLint MUST enforce
this via `react/forbid-elements` and Next.js navigation MUST use the
`Link` component.

#### Scenario: ESLint blocks forbidden elements

- **WHEN** a contributor introduces a `<button>` or `<input>` element inside `apps/web/app` or `apps/web/components/{features,pages}`
- **THEN** `pnpm lint` exits non-zero with a `react/forbid-elements` error pointing at the offending file and line

#### Scenario: Forms use shadcn Form primitives

- **WHEN** a contributor inspects any form on `/register`, `/login`, or `/settings/modules`
- **THEN** the markup is composed from shadcn `<Form>`, `<FormField>`, `<FormItem>`, `<FormLabel>`, `<FormControl>`, `<FormMessage>`, and `<Button>` primitives, with no raw native form controls

#### Scenario: In-app navigation uses Next Link

- **WHEN** a contributor links between routes within the app
- **THEN** the markup uses Next.js `<Link>` and ESLint blocks any `<a href="/...">` to a relative path

### Requirement: All data access SHALL go through TanStack Query

Reads MUST use `useQuery` or `useInfiniteQuery`. Writes MUST use
`useMutation`. Direct `fetch()` calls MUST be confined to `lib/api.ts`.
Components MUST NOT use `useEffect` to fetch data. The root layout MUST
mount a `QueryClientProvider` whose `QueryClient` is created via a
per-request factory so server-rendered pages and the client share the
same instance via `HydrationBoundary`. Read-heavy public pages SHOULD
prefetch on the server with `dehydrate` and rehydrate with the same
hooks on the client.

#### Scenario: No raw fetch outside the API layer

- **WHEN** a reviewer runs `rg -n "\\bfetch\\(" apps/web/app apps/web/components apps/web/features` excluding `lib/api.ts` and `lib/query/`
- **THEN** the command returns no matches

#### Scenario: No useEffect-based data fetching

- **WHEN** a reviewer runs `rg -n "useEffect[\\s\\S]{0,200}fetch\\(" apps/web/`
- **THEN** the command returns no matches

#### Scenario: Plan catalog is prefetched and hydrated

- **WHEN** a user opens `/register` with JavaScript disabled to inspect the initial HTML
- **THEN** the rendered HTML already contains the plan cards from the SSR prefetch, and on hydration the client `usePlans` hook reads from the dehydrated cache without a second network call

#### Scenario: Mutations go through useMutation

- **WHEN** a contributor inspects the registration submit, login submit, or module toggle implementations
- **THEN** each implementation calls a `useMutation`-backed hook from `lib/query/mutations/` rather than calling `fetch` or the API client directly from the component

### Requirement: Loading state SHALL follow a two-tier convention

The web app MUST follow a two-tier loading-state convention. Action-bound
controls (buttons, select triggers, switch rows, anything the user
clicks to start a fetch) MUST render a circular spinner inside the
control while a related `useMutation` is `isPending` or a user-triggered
query is refetching. The control MUST be `disabled` while pending. The
spinner MUST be a shared `<Spinner />` component (Lucide `Loader2` with
`animate-spin`, sized via prop). Layout regions whose content depends
on a `useQuery` initial load MUST render shadcn `<Skeleton>` placeholders
that mirror the final layout's shape until the query resolves. A
surface MUST pick exactly one tier: action controls never render
skeletons as their primary loading indicator; layout regions never
render a centered standalone spinner as their primary indicator on
first paint.

#### Scenario: Submit button shows inline spinner during mutation

- **WHEN** a user clicks the registration `Submit` button and the `useRegisterTenant` mutation enters `isPending`
- **THEN** the button is `disabled`, renders the `<Spinner size="sm" />` inside it, and the button's onClick is ignored until `isPending` returns false

#### Scenario: Plan catalog renders skeleton on first paint

- **WHEN** the `/register` plan step renders and `usePlans` is in initial loading state with no SSR-prefetched data
- **THEN** the page renders shadcn `<Skeleton>` cards matching the plan card layout, and replaces them with real plan cards once data arrives

#### Scenario: Module toggle row shows inline spinner

- **WHEN** a tenant admin flips a module switch and `useToggleModule` is `isPending`
- **THEN** the affected row's switch is `disabled` and the row renders an inline `<Spinner size="sm" />` next to the switch until the mutation settles

#### Scenario: Modules list renders skeleton on first paint

- **WHEN** `/settings/modules` first renders and `useTenantMe` is loading with no prefetched data
- **THEN** the modules list region renders shadcn `<Skeleton>` rows matching the final list, not a centered spinner

#### Scenario: Fetch error renders retry alert

- **WHEN** a `useQuery` settles with an error other than `UNAUTHENTICATED`
- **THEN** the surface renders a shadcn `<Alert variant="destructive">` containing the error message and a `<Button>` whose click invokes the query's `refetch()`, with the spinner inside that button while the retry runs

### Requirement: Forms SHALL use Zod schemas with React Hook Form and shared server-error mapping

Every form MUST define its schema once with Zod in `lib/schemas/`,
import it via `zodResolver` into a React Hook Form instance, and submit
through a `useMutation` hook. Field keys in the Zod schema MUST match
the backend field names exactly. The web app MUST provide a shared
`applyServerFieldErrors(form, error)` helper that consumes a backend
`VALIDATION_ERROR` envelope and calls `form.setError(field, { type:
"server", message })` for each entry in `error.fields`. Field-level
backend errors MUST render via shadcn `<FormMessage>`; non-field errors
MUST render in a top-of-form shadcn `<Alert>` and trigger a toast.

#### Scenario: Zod blocks submit on client validation failure

- **WHEN** a user enters an admin password shorter than the minimum on `/register`
- **THEN** the form prevents submission, the password field's `<FormMessage>` shows the Zod error, no network request fires, and the submit button never enters `isPending`

#### Scenario: Backend validation errors render inline

- **WHEN** the backend responds to `POST /tenants/register` with `{ "error": { "code": "VALIDATION_ERROR", "fields": { "admin_email": ["already taken"], "plan_id": ["unknown"] } } }`
- **THEN** `applyServerFieldErrors` is called, RHF `setError` fires for both fields, the corresponding `<FormMessage>` elements render the messages, and unrelated fields keep their existing state

#### Scenario: Non-validation errors surface in alert and toast

- **WHEN** a registration mutation fails with a non-`VALIDATION_ERROR` code (e.g. `EMAIL_ALREADY_EXISTS`, `INTERNAL_ERROR`)
- **THEN** the form renders a top-of-form shadcn `<Alert variant="destructive">` with the error message, a toast is fired via the global `<Toaster />`, and no field-level message is set

#### Scenario: applyServerFieldErrors helper is unit-tested

- **WHEN** Vitest runs the unit suite for `lib/forms/apply-server-field-errors.ts`
- **THEN** at least one test passes a `VALIDATION_ERROR` payload with multiple fields and asserts `form.setError` was called once per field with `{ type: "server" }` and the matching message

### Requirement: Registration page SHALL be a multi-step form with plan selection

The `/register` page MUST guide the user through (1) school details, (2)
plan selection from `GET /api/v1/billing/plans`, (3) admin account, and
(4) submit. Plan selection MUST display the per-plan feature matrix.
The wizard MUST be implemented with shadcn `<Card>` per step and a
stepper composed from shadcn primitives. The plan list MUST be loaded
via the `usePlans` TanStack Query hook (SSR-prefetched) and render
skeleton cards on first paint when no prefetched data is available.

#### Scenario: Plans are loaded from the API via TanStack Query

- **WHEN** a user opens `/register` and reaches the plan selection step
- **THEN** the page renders the plans returned by `usePlans` (sourced from `GET /api/v1/billing/plans`) as shadcn `<Card>` components with name, price, and entitled features, and shows skeleton cards while the query is loading

#### Scenario: Submit posts to the registration endpoint via mutation

- **WHEN** a user completes all steps and clicks the submit `<Button>`
- **THEN** the form invokes the `useRegisterTenant` mutation, the button shows the inline spinner and is disabled while `isPending`, and on success the client follows the response per the `tenant-onboarding` capability

### Requirement: API client SHALL attach access tokens and refresh on 401

A shared API client wrapper in `lib/api.ts` MUST attach
`Authorization: Bearer <access_token>` to all authenticated requests.
On HTTP 401 with code `UNAUTHENTICATED` or `EXPIRED_ACCESS_TOKEN`, the
wrapper MUST attempt one refresh via `POST /api/v1/iam/auth/refresh`,
retry the original request, and redirect to `/login` if the refresh
fails. The refresh logic MUST be defined once and shared by every
TanStack Query hook, never duplicated per call site.

#### Scenario: Expired access token triggers transparent refresh

- **WHEN** an authenticated request returns 401 with `EXPIRED_ACCESS_TOKEN` and the refresh token is still valid
- **THEN** the wrapper calls `/auth/refresh`, replaces the stored access token, retries the original request, and the calling `useQuery` or `useMutation` observes a successful response without surfacing the 401

#### Scenario: Failed refresh redirects to login

- **WHEN** the refresh call returns 401 (e.g., refresh token expired or revoked)
- **THEN** the wrapper clears stored tokens and navigates to `/login?next=<current-path>`

### Requirement: Modules page SHALL show entitled and non-entitled modules with appropriate controls

The `/settings/modules` page MUST display every feature code defined in
the catalog. Modules entitled by the current plan MUST be toggleable
shadcn `<Switch>` controls bound to the `useToggleModule` mutation.
Modules not entitled by the current plan MUST appear as disabled
switches wrapped in a shadcn `<Tooltip>` with an "Upgrade plan" hint.
The list MUST render shadcn `<Skeleton>` rows on first paint.

#### Scenario: Entitled module toggles persist via mutation

- **WHEN** a tenant admin on Premium toggles the `attendance` module off
- **THEN** the row's switch is `disabled` and shows an inline spinner while `useToggleModule` is `isPending`, the PATCH call returns 200, the row reflects the new state, and reloading the page shows `attendance` as off

#### Scenario: Non-entitled module is visible but disabled

- **WHEN** a tenant admin on Starter views the modules page
- **THEN** the `promotion` row renders a disabled shadcn `<Switch>` wrapped in a shadcn `<Tooltip>` indicating the plan does not include it, and clicking the switch does not issue a network request

#### Scenario: Modules list shows skeleton on first paint

- **WHEN** the page first renders and `useTenantMe` has no prefetched data
- **THEN** the list region renders skeleton rows that match the final row layout until the query resolves

### Requirement: Web SHALL offer public self-service signup

The web app MUST provide a signup page that submits email + password (and an
optional username) to `POST /auth/register` and, on success, treats the returned
identity token as an authenticated session pending tenant selection.

#### Scenario: Visitor signs up

- **WHEN** a visitor completes the signup form with a valid email and password
- **THEN** the client calls `POST /auth/register`, stores the identity token, and
  proceeds to tenant selection (which shows the 0-tenant empty state for a brand
  new account)

### Requirement: Web SHALL resolve tenant context after login

After any successful login or signup, the client MUST call `GET /my-tenants` and
branch: zero memberships → 0-tenant empty state; exactly one → automatically call
`POST /tenants/{id}/enter` and proceed into the app (single-tenant fast path);
many → present a tenant picker, entering the chosen tenant via
`POST /tenants/{id}/enter`. A "switch school" action MUST re-invoke `/enter` for a
different tenant.

#### Scenario: Single-tenant user lands directly in the app

- **WHEN** a user with exactly one membership logs in
- **THEN** the client auto-enters that tenant and the experience matches a direct
  login-into-app flow, with no visible picker

#### Scenario: Multi-tenant user picks a school

- **WHEN** a user with more than one membership logs in
- **THEN** the client shows a tenant picker and enters the selected tenant on
  choice

#### Scenario: Zero-tenant user sees an empty state

- **WHEN** an authenticated user has no memberships
- **THEN** the client shows a "You're not part of any school yet" screen and
  restricts navigation to tenant-less routes

### Requirement: Auth guards SHALL treat identity-only sessions as valid but limited

Routing guards MUST recognize "authenticated with an identity token, no tenant
entered" as a valid state that may reach only tenant-less routes (profile,
tenant list, invitation acceptance). Tenant-scoped pages MUST require a
tenant-scoped token and redirect an identity-only session to tenant selection.

#### Scenario: Identity-only session is kept out of tenant pages

- **WHEN** a user holding only an identity token navigates to a tenant-scoped page
- **THEN** the guard redirects them to tenant selection rather than rendering the
  page or logging them out
