## Context

`add-platform-service` introduces the cross-tenant backend (`/api/v1/platform` +
`typ:"platform"` operator token + operator login/refresh in iam-service). This
change builds the operator-facing UI that consumes it. The user chose Vue/Nuxt
(distinct from the tenant app `apps/web`, which is Next.js), a GitHub-like look,
dark mode by default, and a separate git submodule mounted like `apps/web`.

Locked decisions from exploration:
- Submodule `apps/web-admin` → `git@github.com:protocyber/akademiq-web-admin.git`
  (branch `main`), mirroring the `apps/web` mount.
- Stack pinned: Nuxt 4 (4.4.8), Nuxt UI 4 (4.9.0), Tailwind v4 (4.3.2), TanStack
  Vue Query, Zod.
- Full code duplication — no shared package across the two frontends.
- A new `apps/web-admin/CONVENTIONS.md` translating `apps/web`'s rules to Vue/Nuxt.
- Served from `admin.akademiq.web.id` (separate origin for token isolation).

## Goals / Non-Goals

**Goals:**
- A Nuxt 4 admin app whose data access goes exclusively through TanStack Vue Query
  (no `$fetch`/`useFetch` in pages/components), with a single shared API client
  doing seamless `typ:"platform"` token refresh.
- A Vue-idiom convention set with the same guardrails as `apps/web`: component-only
  UI (Nuxt UI), centralized Zod schemas, centralized error messages, circular
  loading indicator on every loading data state, required-field markers.
- MVP feature coverage: tenant management, billing/plan management, global user
  lookup, audit log view, overview dashboard.
- Clean orchestration: registered submodule, dev targets, Traefik host routing.

**Non-Goals:**
- Building the backend (owned by `add-platform-service`).
- Impersonation, hard-delete/GDPR purge, feature flags, announcement broadcast,
  invoicing UI (post-MVP).
- Sharing code with `apps/web` (explicitly duplicated).
- SSR-heavy prefetch patterns beyond what the admin views need (admin is a
  behind-login back-office; CSR-first is acceptable).

## Decisions

### D1. Separate submodule + separate origin
`apps/web-admin` is its own repo/submodule like `apps/web`, and is served from
`admin.akademiq.web.id`. A distinct origin isolates operator tokens/cookies from
the tenant app, so a tenant-app XSS cannot reach an operator session. *Alternative:*
a route segment inside `apps/web` — rejected (mixes planes, shares origin, and the
stack is different anyway).

### D2. Nuxt UI 4 + Tailwind v4, GitHub-like, dark default
Nuxt UI 4 is the component layer (parallel to shadcn in `apps/web`); native
interactive HTML is forbidden in pages/components. Theme uses Nuxt UI color mode
with the initial preference defaulted to dark. GitHub-like = restrained neutral
palette, dense tables, monospace accents where useful. *Alternative:* hand-rolled
components — rejected (reinvents accessibility + theming Nuxt UI already provides).

### D3. Data access only via TanStack Vue Query
Reads use `useQuery`/`useInfiniteQuery`, writes use `useMutation`. Raw fetching is
confined to a single API client module; pages/components consume composables from a
`queries/`/`mutations/` layer. One `VueQueryPlugin` client is provided at app root.
This mirrors `apps/web` rule #2 and keeps the loading-state convention enforceable.

### D4. Seamless refresh in one shared client
The API client attaches `Authorization: Bearer <platform access>`; on a `401` with
an expired-token code it performs **one** refresh via the operator refresh endpoint,
retries the original request, and redirects to login only when refresh fails.
Concurrent expiries share a single in-flight refresh (promise de-dupe) so we don't
fire N refreshes. Modeled directly on `apps/web`'s `lib/api/client.ts`. This is the
property most likely to regress; it gets dedicated tests.

### D5. Forms = Zod + Nuxt UI UForm + centralized error mapping
Schemas live in a central `schemas/` dir and export inferred types. Nuxt UI
`<UForm>` binds a Zod schema natively. Backend `VALIDATION_ERROR` field maps are
applied back onto form fields via a shared helper (parallel to
`apply-server-field-errors.ts`). Field keys match backend names exactly.

### D6. Centralized error copy + toasts
A single `errors/messages.ts`-equivalent maps backend error codes to user copy;
components never render raw API messages. Transient feedback uses Nuxt UI toasts;
form-level non-field errors render a persistent alert plus a toast.

### D7. DataTable convention
Tenant list, user search results, plan catalog, and audit log use a shared
DataTable layout (card header with primary actions; toolbar with search/filters;
table; optional pagination), echoing `apps/web` rule #10 so list pages are uniform.

### D8. Ports and routing
`WEB_ADMIN_PORT=3010` (tenant web uses 3009). Traefik adds a host router:
`Host(admin.akademiq.web.id)` → web-admin:3010, and
`Host(admin.akademiq.web.id) && PathPrefix(/api/v1/platform)` →
platform-service:8087. Because routing is per-host, the client uses same-origin
absolute base URLs and needs no Nuxt proxy/rewrite (mirroring the `apps/web`
Traefik setup).

```
  Host(admin.akademiq.web.id)
    ├─ PathPrefix(/api/v1/platform)  → platform-service:8087   (priority 100)
    └─ everything else               → web-admin (Nuxt) :3010   (priority 1)
```

## Risks / Trade-offs

- **Refresh races / forced logout regressions** → single shared in-flight refresh
  promise; dedicated tests for concurrent-expiry and refresh-failure paths.
- **Convention drift between two frontends** (React rules don't map 1:1) → write
  `apps/web-admin/CONVENTIONS.md` explicitly in Vue idiom and lint against it; do
  not point reviewers at the Next.js doc.
- **Duplication cost** (schemas/error-copy diverge from `apps/web`) → accepted
  trade-off per user; keep duplicated modules small and clearly named so a future
  shared package is a mechanical extraction.
- **Frontend ahead of backend** → contract is fixed by `add-platform-service`;
  during early dev, mock the `/api/v1/platform` responses so UI work proceeds, then
  switch to the live service.
- **Token isolation only holds if origin stays separate** → keep admin on its own
  subdomain; never serve it under the tenant app origin.
- **Nuxt 4 / Nuxt UI 4 are recent majors** → pin exact versions (4.4.8 / 4.9.0 /
  Tailwind 4.3.2) and verify Nuxt UI 4 ↔ Tailwind v4 compatibility during setup.

## Migration Plan

1. Create remote repo `protocyber/akademiq-web-admin` (empty).
2. `git submodule add -b main <url> apps/web-admin`; add to `.gitmodules`.
3. Scaffold Nuxt 4 + Nuxt UI 4 + Tailwind v4; pin exact versions.
4. Write `apps/web-admin/CONVENTIONS.md`; set up ESLint to enforce the Vue rules.
5. Build foundation (theme/dark-default, Vue Query provider, layout/nav,
   loading-state convention), then auth (login + seamless refresh + guards),
   against mocked `/api/v1/platform`.
6. Build feature areas: tenants, billing/plans, users, audit, dashboard.
7. Orchestration: root `.env.example` (`WEB_ADMIN_DIR`),
   `apps/web-admin/.env.example` (`WEB_ADMIN_PORT=3010`, `NUXT_PUBLIC_*`),
   `mprocs.yaml`, parent `Makefile` (`dev-web-admin` wired into `make dev`),
   `make doctor`.
8. Traefik host router for `admin.akademiq.web.id`.
9. Switch from mocks to the live platform-service once it lands.

Rollback: the submodule and its Traefik route are additive; removing the host
router and the submodule entry fully retracts the app without touching the tenant
stack.

## Open Questions

- SSR vs SPA: render mode for an authenticated back-office — default to CSR
  (`ssr: false`) for simplicity, or keep SSR for the shell? Lean CSR for MVP.
- Where to store the operator session (in-memory + refresh cookie vs localStorage)?
  Should match whatever `apps/web` does for refresh-token handling — confirm during
  setup.
- Exact GitHub-like palette tokens in Nuxt UI 4 theme config — finalize with the
  frontend-design pass.
- Does this submodule need its own CI, or is parent-orchestrated `make test`
  enough for now?
