## Why

Admins can see historical school logos on `/settings/school-profile`, but they cannot remove individual images from that history. The current delete action is too coarse because it removes every logo asset and clears the active logo at once.

## What Changes

- Add support for deleting a single school logo media asset by `media_id`.
- If the deleted asset is inactive, remove only that history item and its stored object.
- If the deleted asset is active, remove the asset and stored object, then clear the tenant's active `logo_media_id`.
- Add per-image delete controls to the logo history section in the school profile settings page.
- Keep the existing bulk-delete behavior available for deleting all school logo media.

## Capabilities

### New Capabilities

### Modified Capabilities
- `billing-service`: Add single school logo media deletion behavior, including active-logo clearing when deleting the active asset.

## Impact

- Backend billing API: add a tenant-scoped single media deletion endpoint or equivalent route.
- Backend billing command/repository layer: delete one media row and backing storage object, clearing `tenant.logo_media_id` when needed.
- Web query/mutation layer: add a single-logo delete mutation and invalidate school profile/media queries.
- Web settings UI: add delete buttons to the logo history list and confirmation/error handling consistent with existing school logo actions.
- API documentation/specs: document the new single-delete contract separately from bulk hard deletion.
