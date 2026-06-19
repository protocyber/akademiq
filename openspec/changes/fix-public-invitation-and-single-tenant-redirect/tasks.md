## 1. Academic Scope Query Gating

- [x] 1.1 Update academic-config query hooks so academic year list queries accept an optional `enabled` flag while preserving current default behavior.
- [x] 1.2 Update `AcademicScopeProvider` to disable tenant-scoped academic scope queries when no tenant-scoped access token exists.
- [x] 1.3 Verify `/invitations/accept?token=<token>` in an unauthenticated session does not trigger authenticated academic-config requests or redirect to login.

## 2. Single-Tenant Tenant Selection Flow

- [x] 2.1 Add explicit auto-enter loading/navigation state to the tenant selection page for exactly-one-tenant responses.
- [x] 2.2 Ensure the singleton tenant list is not rendered while auto-entering and navigating to the dashboard.
- [x] 2.3 Preserve zero-tenant empty state, multi-tenant picker behavior, and error recovery when tenant loading or auto-enter fails.

## 3. Tenant Selection Route Invariants

- [x] 3.1 Normalize stale `/tenant-select` next targets to `/dashboard` after single-tenant login auto-entry.
- [x] 3.2 Redirect scoped-token users away from `/tenant-select` to `/dashboard` before the tenant picker can render.

## 4. Verification

- [x] 4.1 Run the web lint command for `apps/web`.
- [x] 4.2 Run the web typecheck command for `apps/web`.
- [ ] 4.3 Manually verify public invitation access and single-tenant login/tenant-select behavior.
- [ ] 4.4 Manually verify single-tenant login from `/login?next=/tenant-select` lands on `/dashboard`.
