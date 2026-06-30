## 1. Submodule and project bootstrap

- [ ] 1.1 Create empty remote repo `protocyber/akademiq-web-admin` (private)
- [ ] 1.2 `git submodule add -b main git@github.com:protocyber/akademiq-web-admin.git apps/web-admin` and confirm `.gitmodules` entry
- [ ] 1.3 Scaffold Nuxt 4 (v4.4.8) app inside the submodule
- [ ] 1.4 Install and configure Nuxt UI 4 (v4.9.0) + Tailwind v4 (v4.3.2); verify compatibility
- [ ] 1.5 Add TanStack Vue Query + Zod; pin all versions exactly
- [ ] 1.6 Set render mode (CSR-first for MVP) and base project config

## 2. Conventions and tooling

- [ ] 2.1 Write `apps/web-admin/CONVENTIONS.md` translating `apps/web` rules to Vue/Nuxt idiom
- [ ] 2.2 Configure ESLint to forbid native interactive HTML in pages/components (Nuxt UI only)
- [ ] 2.3 Configure lint rule / review guidance forbidding direct `$fetch`/`useFetch` in pages/components
- [ ] 2.4 Set up Vitest (unit) and Playwright (e2e) harnesses

## 3. Foundation (web-admin-foundation)

- [ ] 3.1 Provide a single TanStack Vue Query client at app root (`VueQueryPlugin`)
- [ ] 3.2 GitHub-like theme with Nuxt UI color mode; default to dark on first load; persist toggle
- [ ] 3.3 App shell: layout, navigation, header with theme toggle and operator menu
- [ ] 3.4 Shared circular loading indicator + two-tier loading convention (inline on actions, region on first paint)
- [ ] 3.5 Shared DataTable layout component (card header + toolbar + table + optional pagination)
- [ ] 3.6 Centralized error-message map and toast/alert helpers

## 4. Operator auth (web-admin-operator-auth)

- [ ] 4.1 API client module: attach `Bearer` platform token; confine raw fetch here
- [ ] 4.2 Operator login page + Zod schema + `useMutation` against iam operator login
- [ ] 4.3 Session storage for platform access/refresh tokens (match apps/web approach)
- [ ] 4.4 Seamless single-flight refresh: on expiry, refresh once, retry original request, de-dupe concurrent refreshes
- [ ] 4.5 Redirect to login with `next` on refresh failure; redirect authed users away from login
- [ ] 4.6 Route guards requiring an authenticated platform session on all non-login routes
- [ ] 4.7 Tests: successful login, invalid credentials, silent refresh, refresh-failure redirect, concurrent-expiry single refresh

## 5. Tenant management (web-admin-tenant-management)

- [ ] 5.1 Query hook + tenants list page (DataTable, search, pagination, loading indicator)
- [ ] 5.2 Tenant detail page (profile, subscription, modules, usage) with not-found state
- [ ] 5.3 Suspend mutation with confirmation dialog + inline loading + success toast + refresh
- [ ] 5.4 Reactivate mutation with inline loading + success toast + refresh
- [ ] 5.5 Centralized error handling for command failures (no optimistic state change on failure)

## 6. Billing management (web-admin-billing-management)

- [ ] 6.1 Plan catalog list page (DataTable, loading indicator)
- [ ] 6.2 Create/update plan form: central Zod schema + UForm + server field-error mapping
- [ ] 6.3 Deactivate plan flow with confirmation
- [ ] 6.4 Duplicate-code conflict handling (centralized message, form retained)
- [ ] 6.5 Per-tenant subscription override flow with confirmation + unknown-plan handling

## 7. User management (web-admin-user-management)

- [ ] 7.1 Global user search by email (query hook + results DataTable + empty state)
- [ ] 7.2 User detail page listing tenant memberships and per-tenant roles

## 8. Observability (web-admin-observability)

- [ ] 8.1 Operator audit log read-only view (DataTable, pagination, no mutate/delete controls)
- [ ] 8.2 Overview/usage dashboard with per-widget loading indicators

## 9. Orchestration and routing

- [ ] 9.1 `apps/web-admin/.env.example`: `WEB_ADMIN_PORT=3010`, `NUXT_PUBLIC_*_BASE_URL`, `NODE_ENV`
- [ ] 9.2 Root `.env.example`: add `WEB_ADMIN_DIR`
- [ ] 9.3 `mprocs.yaml`: add web-admin dev process
- [ ] 9.4 Parent `Makefile`: `dev-web-admin` target, wire web-admin into `make dev`/`test`/`build`
- [ ] 9.5 `make doctor`: check web-admin tooling and `.env`
- [ ] 9.6 `infra/traefik/akademiq.dynamic.yaml`: host router for `admin.akademiq.web.id` → web-admin:3010, plus `/api/v1/platform` → platform-service:8087 at priority 100

## 10. Integration and verification

- [ ] 10.1 During early dev, mock `/api/v1/platform` responses; switch to live platform-service once available
- [ ] 10.2 Run lint + Vitest; fix failures
- [ ] 10.3 Playwright e2e: login → list tenants → suspend a test tenant → audit entry visible
- [ ] 10.4 Verify dark-mode-default, loading indicators on every data-backed surface, and no native interactive HTML in pages/components
