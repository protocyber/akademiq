## 1. Backend API Contract

- [x] 1.1 Add a tenant-scoped single school logo media delete route in billing-service.
- [x] 1.2 Document the new single-delete endpoint in the billing service API contract.

## 2. Backend Deletion Behavior

- [x] 2.1 Add repository support for finding/deleting one school-owned media asset by tenant id and media id.
- [x] 2.2 Add command-handler logic that deletes the selected media row and backing storage object only.
- [x] 2.3 Clear tenant `logo_media_id` when the deleted media asset is active.
- [x] 2.4 Ensure deleting inactive media leaves the active logo unchanged.
- [ ] 2.5 Add backend tests for inactive deletion, active deletion, and cross-tenant/non-owner protection. Skipped in this session per backend-test guardrail; run manually with `cd apps/backend && make test`.

## 3. Web Data Layer

- [x] 3.1 Add a web mutation for deleting one school logo media asset by `media_id`.
- [x] 3.2 Invalidate school profile and school media query keys after successful single deletion.

## 4. Web UI

- [x] 4.1 Update the logo history list to render a delete button for each media item.
- [x] 4.2 Wire each history delete button to the single-delete mutation with confirmation and pending state.
- [x] 4.3 Ensure deleting the active history item refreshes the page into a no-current-logo state.

## 5. Verification

- [ ] 5.1 Run relevant backend tests for billing-service. Skipped in this session per backend-test guardrail; run manually with `cd apps/backend && make test`.
- [x] 5.2 Run relevant web lint/typecheck/tests for the school profile page. `pnpm typecheck` passed; `rtk lint` still fails on pre-existing issues outside this change.
- [x] 5.3 Run OpenSpec validation/status for `delete-school-logo-history-item`.

## Manual Backend Tests

- `cd apps/backend && make test`
