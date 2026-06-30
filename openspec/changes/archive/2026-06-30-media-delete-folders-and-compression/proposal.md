## Why

The media subsystem (introduced by the `media-storage-and-photo-uploads`
change) can store and serve images but has **no way to delete them**:
academic-ops and billing have no delete endpoint at all, and the IAM
"Hapus Avatar" button only nulls the DB column while leaving the bytes
orphaned in R2 forever (a literal `// TODO: Delete file from storage`).
On top of that, every re-upload (avatar, logo, student/teacher photo)
silently leaks the previous object — the bucket grows monotonically.
Finally, uploads are uncapped at the cost of a generous 2 MB limit and no
client compression, so phone-camera photos (commonly 2–5 MB) are rejected
or waste bandwidth.

## What Changes

- **Storage key prefix by owner type.** Organize R2/local objects into
  prefixes derived from `owner_type` (`student/`, `teacher/`, `school/`,
  `family/`) and a fixed `avatar/` prefix for IAM. R2 is a flat namespace;
  the `/` is only a visual delimiter. The key is **reconstructed** at
  runtime (`"{owner_type}/{media_id}"`) from columns that already exist —
  no new `storage_key` column, no schema migration. IAM uses a hardcoded
  `avatar/` prefix because it has no `media_asset` table.
- **Hard-delete media.** academic-ops and billing each gain
  `DELETE /api/v1/<service>/media?owner_type=&owner_id=` that **bulk**
  removes all asset rows (active + history) for an owner, deletes every
  matching object from storage, and nulls the owning
  `photo_media_id`/`logo_media_id`. IAM's existing
  `DELETE /api/v1/iam/me/avatar` is fixed to actually delete the bytes
  (resolving the `// TODO`).
- **Orphan-on-replace garbage collection.** Every upload path reads the
  previous active object's key and deletes it from storage before the new
  one becomes active, so re-uploading no longer leaks.
- **512 KB upload limit with client-side compression.** Lower the shared
  `MAX_MEDIA_SIZE_BYTES` from 2 MB to 512 KB and add browser-side
  downscale/re-encode before upload so phone photos fit. Consolidate the
  duplicated 2 MB constants (backend + 3–4 web spots + hint text) into a
  single shared value.
- **One-time object migration script.** Existing objects stored at the
  bare `{media_id}` key are copied to `{owner_type}/{media_id}` so they
  keep resolving after the prefix change. No DB schema change is needed.

## Capabilities

### New Capabilities
<!-- None. This change extends the media subsystem introduced by
     media-storage-and-photo-uploads; it does not introduce a new
     capability. -->

### Modified Capabilities
- `media-storage`: storage keys SHALL be prefixed by owner type
  (reconstructed at runtime, no persisted column); the shared max upload
  size SHALL be 512 KB; the backend delete contract is added (hard delete
  of bytes).
- `iam-service`: avatar upload SHALL use the `avatar/` prefix and SHALL
  garbage-collect the previous object on replace; avatar delete SHALL
  remove the stored bytes (not just null the column).
- `academic-ops-service`: SHALL expose a bulk hard-delete media endpoint
  for an owner and SHALL garbage-collect the previous active photo on
  replace.
- `billing-service`: SHALL expose a bulk hard-delete media endpoint for
  the school logo owner and SHALL garbage-collect the previous logo on
  replace.
- `web-file-upload`: SHALL add delete affordances (Hapus Foto/Logo) wired
  to the new delete endpoints; SHALL compress images client-side before
  upload; SHALL centralize the 512 KB size constant and hint text.

## Impact

- **Backend (`libs/common-media`)**: add a prefixed-key helper
  (`media_key_for_owner(owner_type, media_id)`); lower
  `MAX_MEDIA_SIZE_BYTES` to 512 KB; the `StorageBackend::delete` contract
  is already present — used here in earnest.
- **Backend services**: academic-ops + billing add a bulk delete command,
  repo method, and `DELETE` route; upload commands gain a "delete previous
  active key" step (read owner_type → reconstruct key → delete). IAM
  avatar upload/delete reconstruct the `avatar/{id}` key. No DB migration,
  no new columns.
- **Web**: new delete buttons + TanStack Query delete mutations with cache
  invalidation; a reusable client image-compression step before upload;
  the `512 KB` constant centralized. Affected: `photo-upload.tsx`,
  `avatar-upload.tsx`, `settings/school-profile/page.tsx`, the shared
  `FileDropzone` hint, and upload mutation hooks.
- **Infra/scripts**: a one-time object-copy script (flat `{id}` →
  `{owner_type}/{id}`, and → `avatar/{id}`) run against the local dir or
  R2 bucket for existing data.
- **Docs**: `docs/internal/13_engineering_standards/18_media_storage.md`
  updated to record the folder convention (reconstructed prefix, not
  persisted), the delete/GC behavior, and the 512 KB limit.
- **No new service, no Traefik mapping change** — delete reuses the
  existing per-service path prefixes.
