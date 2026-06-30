## Why

The `add-platform-service` change introduces a cross-tenant control plane
(`/api/v1/platform` + a `typ:"platform"` operator token), but there is no UI for
operators to use it. AkademiQ's existing app (`apps/web`) is a tenant-scoped
Next.js app and is the wrong place for a cross-tenant back-office. Operators need a
dedicated admin frontend to manage tenants, billing/plans, and global users, served
from a separate origin for token isolation. The user has chosen Vue/Nuxt for this
app, with a GitHub-like look and dark mode by default.

## What Changes

- **New frontend app** in a new git submodule `apps/web-admin`
  (`git@github.com:protocyber/akademiq-web-admin.git`, tracks `main`), mirroring how
  `apps/web` is mounted.
- **Stack**: Nuxt 4 (v4.4.8) + Nuxt UI 4 (v4.9.0) + Tailwind v4 (v4.3.2) +
  TanStack Vue Query + Zod. GitHub-like UI, light/dark with **dark as default**.
- **Conventions (Vue idiom)**: a new `apps/web-admin/CONVENTIONS.md` that translates
  `apps/web/CONVENTIONS.md` to Nuxt — Nuxt UI components only (no native interactive
  HTML), all data access through TanStack Vue Query (no direct `$fetch`/`useFetch`
  in pages/components), centralized Zod schemas, centralized error messages,
  circular loading indicator on every loading data state, and required-field markers.
- **Auth**: operator login against iam-service's operator endpoints; seamless
  automatic token refresh modeled on `apps/web` so an expired access token triggers
  a silent refresh, never a forced logout. Uses the `typ:"platform"` token.
- **Features (MVP)**: manage tenants (list/detail, suspend/reactivate), manage
  billing (plan catalog CRUD, per-tenant subscription override), manage global
  users (cross-tenant lookup), plus operator audit log view and a usage/overview
  dashboard. Additional SaaS-admin features (impersonation, hard-delete, feature
  flags, announcements) are noted as out of scope for MVP.
- **Code sharing**: none — full duplication. Zod schemas, error-message map, and API
  client are reimplemented in `apps/web-admin` (no shared package).
- **Orchestration**: register the submodule, add `WEB_ADMIN_DIR` to root
  `.env.example`, a `WEB_ADMIN_PORT` (default `3010`) and `NUXT_PUBLIC_*` base URLs
  in `apps/web-admin/.env.example`, mprocs + Makefile dev targets, and a Traefik
  host router for `admin.akademiq.web.id`.

## Capabilities

### New Capabilities
- `web-admin-foundation`: the Nuxt 4 app shell — project setup, GitHub-like theme
  with dark default, Nuxt UI 4 + Tailwind v4, TanStack Vue Query provider, layout,
  navigation, and the loading-state convention.
- `web-admin-operator-auth`: operator login UI, session storage, and seamless
  automatic `typ:"platform"` token refresh with route guards.
- `web-admin-tenant-management`: tenant list/detail and suspend/reactivate flows.
- `web-admin-billing-management`: plan-catalog CRUD and per-tenant subscription
  override flows.
- `web-admin-user-management`: cross-tenant global user lookup and detail.
- `web-admin-observability`: operator audit log view and a usage/overview
  dashboard.

### Modified Capabilities
<!-- None. This is a brand-new app in a new submodule; it consumes the
     /api/v1/platform contract defined by add-platform-service. -->

## Impact

- **New submodule**: `apps/web-admin` + entry in `.gitmodules`; new remote repo
  `protocyber/akademiq-web-admin`.
- **Depends on**: `add-platform-service` — the `/api/v1/platform` API contract and
  the operator token/refresh endpoints must exist (or be stubbed) for end-to-end
  function.
- **Orchestration/infra**: root `.env.example` (`WEB_ADMIN_DIR`), parent `Makefile`
  (`dev-web-admin`, wired into `make dev`/`test`/`build`), `mprocs.yaml`,
  `apps/web-admin/.env.example` (`WEB_ADMIN_PORT=3010`, `NUXT_PUBLIC_*_BASE_URL`),
  `infra/traefik/akademiq.dynamic.yaml` (host router for `admin.akademiq.web.id`),
  `make doctor`.
- **New conventions doc**: `apps/web-admin/CONVENTIONS.md` (authoritative for this
  app, parallel to `apps/web/CONVENTIONS.md`).
- **Security**: served from a distinct origin (`admin.akademiq.web.id`) to isolate
  operator tokens/cookies from the tenant app.
