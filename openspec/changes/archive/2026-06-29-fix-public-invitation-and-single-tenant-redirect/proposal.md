## Why

Public invitation acceptance links must be accessible to unauthenticated users, including clean incognito sessions. A global academic scope provider currently starts tenant-scoped queries outside authenticated app pages, which can redirect public routes to login before the invitation page can render.

Single-tenant users should also enter their only tenant without briefly seeing the tenant selection list, avoiding confusing flicker during onboarding and login.

## What Changes

- Prevent global academic scope queries from running unless a tenant-scoped access token is present.
- Preserve public access to invitation acceptance pages while keeping tenant-scoped pages protected.
- Ensure single-tenant auto-entry keeps the tenant selection page in a loading state until navigation completes.
- Keep multi-tenant and zero-tenant tenant selection behavior unchanged.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `web-auth-onboarding`: Public invitation acceptance and tenant selection redirect behavior are clarified.

## Impact

- Affected frontend code under `apps/web`:
  - `src/components/providers/academic-scope-provider.tsx`
  - `src/lib/query/queries/use-academic-config.ts`
  - `src/app/tenant-select/page.tsx`
- No backend API or database changes expected.
- No breaking changes.
