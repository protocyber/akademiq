## Context

The `media-storage-and-photo-uploads` change landed a shared `common-media`
library, `local` + `r2` backends, per-service proxy serve endpoints, and
teacher/student photo upload. Three gaps remain, all surfaced in practice:

1. **No deletion.** academic-ops and billing have **no** delete route. The
   IAM `DELETE /api/v1/iam/me/avatar` exists but `delete_avatar`
   (`iam-service/src/commands.rs:2110`) only nulls `avatar_url` — there is a
   literal `// TODO: Delete file from storage when media_repo is implemented`.
   Bytes are orphaned forever.
2. **Silent leak on replace.** No upload path reads the previous active
   object, so every re-upload orphans the prior bytes. The R2/local store
   grows monotonically.
3. **Flat, ungrouped keys + loose limits.** The storage key is the bare
   `media_id` (`media_key(media_id) == "{uuid}"`), so all objects sit in one
   flat namespace with no grouping, and the max size is a generous 2 MB with
   no client compression — phone photos (2–5 MB) are rejected or waste
   bandwidth.

The store is flat-by-nature: R2/S3 is a flat namespace and `/` is only a
prefix delimiter (per Cloudflare R2 docs). The `media_asset` table already
carries `owner_type` (`student`|`teacher`|`school`|`family`) and `media_id`.
IAM is the odd one out: it has **no** `media_asset` table — just a single
`user.avatar_url` column (`V20__add_profile_fields.sql`).

## Goals / Non-Goals

**Goals:**
- Owner-type-prefixed storage keys (`student/{id}`, `teacher/{id}`,
  `school/{id}`, `family/{id}`, `avatar/{id}`) reconstructed at runtime —
  no new persisted column.
- Hard-delete media: academic-ops + billing bulk delete (active + history,
  bytes + rows); IAM avatar delete actually removes bytes.
- Garbage-collect the previous object on every re-upload (full GC).
- 512 KB upload limit with client-side compression.
- Migrate existing flat-keyed objects to the new prefixed keys.

**Non-Goals:**
- Persisting a `storage_key` column (rejected — see D1; the convention will
  not change, so a column would be redundant derivable data).
- Unifying IAM into a `media_asset` table (rejected — see D2).
- Per-history-row selective delete UI (bulk only, per D3).
- Server-side transcoding, thumbnail generation, virus scanning, EXIF
  stripping (still out of scope, as in the parent change).
- Direct/presigned R2 URLs (serving stays proxied, as in the parent change).

## Decisions

### D1: Reconstructed prefix keys, not a persisted column
The storage key is `"{owner_type}/{media_id}"`, computed at runtime from two
columns that already exist. The serve/delete handlers read the
`media_asset` row (they already do, to get `content_type`) and reconstruct
the key; IAM hardcodes `avatar/{media_id}` since it always knows the kind.

**Alternative considered — persist a `storage_key` column.** Rejected
because, for this system, the convention (`{owner_type}/{id}`) is fixed and
`owner_type` on a row is effectively immutable. A column would store
derivable data, add a real schema migration, and introduce a drift risk
(collected value vs. computed value). Persisting only pays off if the folder
convention can change later; the owner confirmed it will not.

> Note: because the key is reconstructed, **any code path that needs a key
> must read `owner_type` first.** The serve handler already reads the row
> for `content_type`; the delete/GC paths must do the same. This is the one
> invariant the implementation must hold.

### D2: IAM stays special (no `media_asset` table)
IAM keeps its single `user.avatar_url` column and uses a hardcoded
`avatar/` prefix. Avatars are 1-per-user with no useful history.

**Alternative considered — unify IAM into `media_asset`.** Rejected: it
adds a table + migration + query for negligible benefit, and widens the
blast radius of an otherwise small change. The cost is one hardcoded prefix
string in IAM, which is acceptable.

### D3: Bulk hard delete (active + history), not per-row
A `DELETE /api/v1/<service>/media?owner_type=&owner_id=` removes **all**
rows for that owner (active + inactive history), deletes every matching
storage object, and nulls the owning `photo_media_id`/`logo_media_id`/
`avatar_url`.

**Alternative considered — per-history-row delete.** Rejected for now: the
web UI only renders the active asset, so per-row delete would first require
a new history-list UI. Bulk delete gives users "remove my photo entirely"
now; selective history cleanup can follow if needed.

### D4: Full garbage collection on replace
Every upload path reads the **previous** active asset for the owner, and if
one exists, deletes its storage object before the new one becomes active
(in the same DB transaction that flips `is_active`). This makes "hard
delete" honest across all entry points, not just the explicit delete button.

**Alternative considered — delete-only (leak on replace).** Rejected: it
would keep the monotonic bucket growth that motivates this change. Cost is
one extra read before overwrite; delete backends are idempotent on missing
objects (`LocalBackend` ignores `NotFound`; S3/R2 `delete_object` is
idempotent), so deleting an already-gone object is safe.

### D5: 512 KB limit + client-side compression
The shared `MAX_MEDIA_SIZE_BYTES` drops from 2 MB to 512 KB. The web app
compresses (downscale + re-encode to JPEG/WebP) in the browser before
upload so phone photos fit. The duplicated constants (backend + 3–4 web
spots + hint text) collapse into a single shared value.

**Alternative considered — limit cut only, no compression.** Rejected: 512
KB is tight for camera JPEGs (commonly 2–5 MB); without compression most
users would hit `FILE_TOO_LARGE` and get a bad UX. This revises the parent
change's documented non-goal of "no image transcoding" — client-side
downscaling is now explicitly in scope. Logo/avatar cases easily fit 512 KB
post-compression; student photos destined for report-card print remain
acceptable quality at the target dimensions.

### D6: One-time object migration, no schema change
A script copies existing objects from the bare `{media_id}` key to
`{owner_type}/{media_id}` (academic-ops + billing) and to `avatar/{id}`
(IAM). For R2 this is an in-bucket copy (`CopyObject` then `DeleteObject`,
or a prefix-preserving copy); for local it is a file move. **No DB migration,
no new columns.** The `media://…` URI scheme and `avatar_url` values are
unchanged (the URI is logical; only the physical key moves).

## Risks / Trade-offs

- **Reconstruct invariant drift:** any new code path that builds a key
  without reading `owner_type` will 404. → Mitigate with a single helper
  `media_key_for_owner(owner_type, media_id)` in `common-media` and a lint
  against bare `media_key(media_id)` in media-owning services.
- **Client compression quality/parity:** browser canvas re-encoding varies
  across browsers and can soften images. → Use a conservative target
  (longest edge ≤ 1024px, quality ~0.8); the report-card photo is already
  rendered small on the print page.
- **Migration window:** objects copied mid-migration must not 404. → The
  migration copies first, then deletes the old key only after the new key
  is verified; serve reads `owner_type` so it always targets the new key.
- **Bulk delete is destructive:** history rows are removed permanently.
  → Confirm in the UI ("Hapus foto? Tindakan ini tidak dapat dibatalkan");
  the operation is scoped to one owner and tenant-guarded.
- **512 KB may reject high-detail logos at print size.** → Acceptable; logos
  are vector-like and compress well; revisit if reported.

## Migration Plan

1. Land `common-media` helper + 512 KB limit; wire reconstructed keys into
   the three services' upload paths (behavior-preserving for fresh uploads).
2. Add GC-on-replace to all upload paths.
3. Add the bulk delete command + route to academic-ops and billing; fix IAM
   avatar delete to remove bytes.
4. Add the one-time object-copy script; run against existing data (local
   and/or R2).
5. Web: delete buttons, client compression, centralized size constant.
6. Rollback: reconstructed keys are additive; revert to flat keys by
   reversing the helper. Deleted objects are gone (hard delete) — no soft
   rollback, by design.
