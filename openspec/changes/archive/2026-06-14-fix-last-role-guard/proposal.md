## Why

A user's tenant membership is modeled *only* by their `user_tenant_role` rows:
`repo.rs:list_tenant_user_ids` decides membership via
`EXISTS(... user_tenant_role ...)`. `remove_user_role` (`commands.rs:716`) guards
the *last admin* but not the *last role*, so removing a user's only role deletes
their membership and they silently vanish from `/settings/users` with no warning
and no way to find them again. This is the reported bug for
`fitrah.pro@gmail.com` in "Demo Premium".

This change is the minimal, urgent fix for that data-integrity bug, split out
from the larger `improve-tenant-users-ui` work so it can ship and be reviewed on
its own. It does **not** add an off-boarding path; that (an explicit
remove-from-tenant action) lives in `improve-tenant-users-ui`, which builds on
this guard.

## What Changes

- Add a `LAST_ROLE` guard to `remove_user_role`: after the existing last-admin
  check, if removing this role would leave the user with zero roles in the
  tenant, refuse with `AppError::conflict("LAST_ROLE", ...)` instead of silently
  un-enrolling them.
- Document the new `LAST_ROLE` conflict code in the IAM API contract.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `tenant-user-management`: removing a user's final role in a tenant is refused
  (`LAST_ROLE`) instead of silently un-enrolling them. Role-event names are
  unchanged.

## Impact

- Backend: `apps/backend/services/iam-service` (`commands.rs`, `repo.rs` helper if
  needed, integration tests). API contract doc
  `docs/internal/11_integration_contracts/apis/iam-service-api.md`.
- Behavior change: callers/tests that relied on last-role removal silently
  un-enrolling a user now receive 409 `LAST_ROLE`. No DB migration. No event
  shape changes.
</content>
</invoke>
