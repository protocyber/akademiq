## Context

The school profile settings page already fetches school media history and renders it in a logo history section. The current web delete action calls the billing service bulk owner deletion endpoint, which removes every school logo media row and clears the active logo. There is no API contract for deleting a single history item.

The billing service owns school logo media storage and tenant `logo_media_id`, so single-item deletion must be implemented server-side with tenant scoping resolved from the authenticated request. The web app should only request deletion by media id and then refresh school profile/media state.

## Goals / Non-Goals

**Goals:**
- Let admins delete individual images from the logo history list.
- Delete the selected media row and backing storage object only.
- Clear `tenant.logo_media_id` when the selected media is the active logo.
- Preserve existing bulk hard deletion semantics for the current logo delete action unless deliberately changed during implementation.
- Keep the UI consistent with existing school profile loading, confirmation, and toast patterns.

**Non-Goals:**
- Promoting another historical logo after deleting the active logo.
- Adding restore/undo behavior for deleted logos.
- Changing logo upload validation, file size limits, or storage provider behavior.
- Reworking the broader media asset model beyond the school-logo use case.

## Decisions

### Add single-delete API by media id

Expose a tenant-scoped delete operation for one media asset, preferably under an explicit school-profile media path such as `DELETE /api/v1/billing/tenants/me/school-profile/media/:media_id`, or reuse an existing media-id route shape if the service already has one available. The handler must verify the asset belongs to `owner_type = school` and `owner_id = tenant_id` before deleting.

Alternative considered: extend the current `DELETE /api/v1/billing/media` query endpoint with `media_id`. This is less clear because the current endpoint is explicitly owner-wide bulk deletion.

### Active deletion clears rather than promotes

When the deleted asset is active, the service clears the tenant's `logo_media_id` and leaves no active logo. This matches the user's product decision and avoids surprising admins by silently restoring an older logo.

Alternative considered: promote the newest inactive logo. This was rejected because deletion should mean the selected active image is no longer used.

### Web mutation invalidates profile and media queries

The web mutation should invalidate both school media and school profile queries because deleting active media can change both the history list and the current logo reference.

Alternative considered: update query caches manually. Invalidating is simpler and consistent with the existing upload/delete mutations.

### History row delete controls use existing UI conventions

`MediaHistoryList` should accept a delete callback and render a per-item delete button. Deleting should be disabled while the selected item is pending and should use confirmation/error handling consistent with existing logo actions.

Alternative considered: hide delete for active media. This conflicts with the chosen behavior that active deletion is allowed and clears the current logo.

## Risks / Trade-offs

- Single-delete route accidentally deletes another tenant's media → Mitigate by resolving tenant id from JWT and filtering by `owner_type`, `owner_id`, and `media_id` in one command/repository path.
- Storage object deletion succeeds but DB update fails, or vice versa → Mitigate by following the service's existing media deletion ordering and error handling conventions; prefer transactional DB changes around row deletion and tenant logo clearing.
- Existing uploaded history objects may already be missing because upload garbage-collects previous active storage objects → Mitigate by keeping deletion idempotent for missing storage where existing bulk deletion already tolerates it, and avoid broadening scope in this change.
- Confusion between bulk and single delete mutations → Mitigate with clear naming such as `useDeleteSchoolLogoMedia` versus the existing bulk delete mutation.
