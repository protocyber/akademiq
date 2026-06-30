# Implementation Tasks

## 1. Shared `common-media` library

- [x] 1.1 Add `media_key_for_owner(owner_type, media_id) -> String` returning `"{owner_type}/{media_id}"`; add an `avatar_key(media_id) -> String` returning `"avatar/{media_id}"`
- [x] 1.2 Lower `MAX_MEDIA_SIZE_BYTES` from `2 * 1024 * 1024` to `512 * 1024`
- [x] 1.3 Update the validation unit test (`validates_images`) to assert the new 512 KB boundary; add a unit test for `media_key_for_owner` / `avatar_key`
- [x] 1.4 Keep the existing `media_key(media_id)` but discourage new use in media-owning services (prefixed helper is the norm going forward)

## 2. academic-ops-service (reconstructed keys + GC + delete)

- [x] 2.1 Change `upload_media` to store at `media_key_for_owner(owner_type, media_id)` instead of the bare `media_key(media_id)`
- [x] 2.2 Change `serve_media` to read the asset row's `owner_type` and reconstruct the key before `get` (it already reads the row for `content_type`)
- [x] 2.3 Add GC-on-replace: in `upload_media`, before inserting the new active asset, look up the previous active asset for the owner, reconstruct its key, and `media_storage.delete` it within the same transaction (idempotent)
- [x] 2.4 Add a `bulk_delete_owner_media` repo method that deletes all `media_asset` rows for `(tenant_id, owner_type, owner_id)` and returns the removed `(media_id, owner_type)` pairs (for object deletion)
- [x] 2.5 Add a `delete_owner_media` command that runs the repo delete in a transaction, reconstructs each key, deletes each storage object, and nulls `photo_media_id` on the owning entity (student/teacher/family)
- [x] 2.6 Add the route `DELETE /api/v1/academic-ops/media` (query params `owner_type`, `owner_id`) wired to the command; tenant resolved from JWT
- [x] 2.7 Extend academic-ops integration tests: upload-replace deletes old object; bulk delete removes rows + objects + nulls `photo_media_id`; bulk delete of owner with no media succeeds

## 3. billing-service (reconstructed keys + GC + delete)

- [x] 3.1 Change `upload_school_logo` to store at `media_key_for_owner("school", media_id)`
- [x] 3.2 Change `serve_media` to read the asset row's `owner_type` and reconstruct the key before `get`
- [x] 3.3 Add GC-on-replace in `upload_school_logo`: delete the previous active logo's object (key `school/{prev_media_id}`) within the transaction
- [x] 3.4 Add a `bulk_delete_owner_media` repo method + `delete_owner_media` command (nulls `logo_media_id` on the tenant)
- [x] 3.5 Add the route `DELETE /api/v1/billing/media` (query params `owner_type=school`, `owner_id`) wired to the command; tenant resolved from JWT
- [x] 3.6 Extend billing integration tests: logo replace deletes old object; bulk delete removes rows + objects + nulls `logo_media_id`

## 4. iam-service (avatar prefix + GC + delete-bytes fix)

- [x] 4.1 Change `upload_avatar` to store at `avatar_key(media_id)` (`avatar/{media_id}`) instead of the bare `media_key(media_id)`
- [x] 4.2 Change `serve_media_handler` to use `avatar_key(media_id)` when reconstructing the key
- [x] 4.3 Add GC-on-replace in `upload_avatar`: before storing the new avatar, parse the existing `avatar_url` for the previous `media_id` and `media_storage.delete(avatar_key(prev_id))` if present
- [x] 4.4 Fix `delete_avatar` (resolve the `// TODO`): parse the current `avatar_url` for `media_id`, `media_storage.delete(avatar_key(media_id))`, then `clear_avatar_url` — order delete-before-clear so a mid-failure leaves the column intact
- [x] 4.5 Extend iam tests: avatar replace deletes old object; avatar delete removes bytes and nulls `avatar_url`; deleting an avatar whose object is already gone succeeds

## 5. One-time object migration script

- [x] 5.1 Add a script that, for each service, copies existing objects from the bare `{media_id}` key to `{owner_type}/{media_id}` (academic-ops + billing, reading `owner_type` from `media_asset`) and to `avatar/{media_id}` (iam, parsing `avatar_url`)
- [x] 5.2 For R2: copy-then-verify-then-delete-old (`CopyObject` + read-back + `DeleteObject`); for local: file move with verification
- [x] 5.3 Document run instructions (env: `MEDIA_BACKEND`, local dir vs R2 creds) and that it is safe to re-run (idempotent on the new key)

## 6. Web — delete actions

- [x] 6.1 Add a TanStack Query delete mutation for academic-ops media (`DELETE /api/v1/academic-ops/media?owner_type=&owner_id=`) with cache invalidation of `useMediaAssets`
- [x] 6.2 Add a TanStack Query delete mutation for the billing school logo (`DELETE /api/v1/billing/media?owner_type=school&owner_id=`) with cache invalidation
- [x] 6.3 Add a "Hapus Foto" button (with confirm dialog) to `photo-upload.tsx` shown when an active photo exists; revert to placeholder on success
- [x] 6.4 Add a "Hapus Logo" button (with confirm dialog) to `settings/school-profile/page.tsx`; revert to placeholder on success
- [x] 6.5 Keep the existing avatar "Hapus Avatar" button wired to the (now fixed) `DELETE /api/v1/iam/me/avatar`

## 7. Web — client-side compression + centralized limit

- [x] 7.1 Add a reusable client image-compression utility (canvas downscale, longest edge cap, JPEG/WebP re-encode) with a fallback that passes the file through if it is already small
- [x] 7.2 Centralize the 512 KB max size and the "Maksimal 512KB" hint text in a single shared constant consumed by `FileDropzone` hints, `photo-upload.tsx`, `avatar-upload.tsx`, and the school-logo surface
- [x] 7.3 Wire the compression step into all upload mutations (avatar, logo, student/teacher photo) so the compressed blob is sent
- [x] 7.4 Keep centralized error messages for `FILE_TOO_LARGE` / `INVALID_FILE_TYPE` in sync with the new limit

## 8. Docs

- [x] 8.1 Update `docs/internal/13_engineering_standards/18_media_storage.md`: record the reconstructed `{owner_type}/{id}` key convention (and `avatar/{id}` for IAM), the hard-delete + GC behavior, the 512 KB limit, and the client-compression decision
- [x] 8.2 Note in the doc that switching the folder convention later would require a new object migration (why we reconstruct rather than persist)

## 9. Verification

- [ ] 9.1 Backend: `cd apps/backend && make test` (common-media + iam + billing + academic-ops suites) green — run manually. Skipped by automation per backend-test guardrail; run manually with the command below.
- [x] 9.2 Web: lint + typecheck + relevant component tests green
- [ ] 9.3 Manual: with `MEDIA_BACKEND=local`, verify delete + replace-GC across avatar, logo, student/teacher photo (old files removed from disk); verify a phone photo compresses and uploads under 512 KB
- [ ] 9.4 Manual: with `MEDIA_BACKEND=r2`, verify the same flows delete objects from the bucket and objects land under their `owner_type/` (and `avatar/`) prefixes
- [ ] 9.5 Run the one-time migration script against existing local and/or R2 data; confirm legacy flat-keyed objects still serve after migration

## Manual Backend Tests

- `cd apps/backend && cargo test -p common-media`
- `cd apps/backend && cargo test -p iam-service`
- `cd apps/backend && cargo test -p billing-service`
- `cd apps/backend && cargo test -p academic-ops-service`
- `cd apps/backend && make test`
