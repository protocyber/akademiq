## Context

Three backend services own uploaded media and each grew its own handling:

- `iam-service` (avatars): stores to disk, serves `GET /api/v1/iam/media/:id`,
  resolves `media://` → HTTP path in `/me`. Works, except the serve handler
  returns `application/octet-stream`.
- `billing-service` (school logo): stores to disk, **no serve endpoint**, returns
  raw `media://…` `file_url` to the web, which `<img>` cannot load.
- `academic-ops-service` (student/teacher/family photos): stores to disk but
  records `format!("file://{path:?}")` (debug-formatted path with quotes) and
  has **no serve endpoint**.

All three keep a `media_asset` table and reflect the active asset onto the
owning row (`tenant.logo_media_id`, `student.photo_media_id`, user
`avatar_url`) inside a single DB transaction. The web app already has a
reusable `FileDropzone` (mandated by the `web-file-upload` spec) and `next/image`
with a `remotePatterns` allowlist limited to the iam media path.

The storage decision (shared library, not a service) and its rationale are
recorded in `docs/internal/13_engineering_standards/18_media_storage.md`.

## Goals / Non-Goals

**Goals:**
- One shared `libs/common-media` library: `StorageBackend` trait, `local` + `r2`
  backends, env selection, validation (2MB, image MIME), URL/URI resolution.
- A uniform proxy serve endpoint per owning service returning the real
  `content_type`.
- Fix the logo and avatar rendering bugs; fix the academic-ops `file://` bug.
- Teacher and student photo upload via the existing `FileDropzone`; student
  photo on the report-card print page.
- Storage backend switchable via `.env` without code changes.

**Non-Goals:**
- A standalone `storage-service` (deferred; triggers documented in 18_media_storage.md).
- Thumbnail generation, image transcoding, virus scanning, EXIF stripping.
- Presigned / public-bucket direct-to-R2 URLs (we proxy through the backend).
- Changing the `media_asset` schema or the per-service ownership/transaction model.
- Family-member photo upload UI (column exists; out of scope here).

## Decisions

### D1: Shared library, not a service
A `libs/common-media` crate consumed by the three services, matching the
existing `common-{auth,db,logging,errors}` pattern. Keeps the active-media
reflection in one DB transaction with the media insert; avoids a synchronous
shared dependency on the upload hot path. Full argument in 18_media_storage.md.
*Alternative considered:* `storage-service` — rejected for now because it turns
an atomic write into a distributed saga and is the heaviest possible change.

### D2: `StorageBackend` trait
```
trait StorageBackend {
    async fn put(&self, key: &str, content_type: &str, bytes: &[u8]) -> Result<()>;
    async fn get(&self, key: &str) -> Result<(Bytes, String)>; // bytes + content_type
    async fn delete(&self, key: &str) -> Result<()>;
}
```
`key` is derived from `media_id` (+ tenant prefix). `LocalBackend` writes under a
configured dir; `R2Backend` uses an S3-compatible client against the R2 endpoint.
Constructed once at startup from env and stored in each service's `AppState`.
*Alternative considered:* per-service ad-hoc fns — rejected, that is the current
duplication causing the bugs.

### D3: Backend proxy serving + correct content-type
Each service keeps `GET /api/v1/<service>/media/:media_id`, reads bytes via the
backend, and returns the `content_type` stored in `media_asset`. The browser is
always same-origin; R2 vs local is invisible to the frontend. This fixes the
avatar bug (octet-stream → real image type) and gives billing/academic-ops a
serve path. *Alternative considered:* direct/presigned R2 URLs — rejected to
keep the frontend uniform and avoid CORS/public-bucket and `remotePatterns`
churn per environment.

### D4: Canonical URI + resolution
The stored `file_url` keeps the `media://` form. Each service resolves it to its
own `GET …/media/:id` path in API responses (iam already does this for `/me`;
billing must do it for the logo list; academic-ops returns `photo_media_id` and
the web builds the URL). This removes the raw `media://` and the
`file://"…"` strings from API output.

### D5: Env-based backend selection
`MEDIA_BACKEND=local|r2` (default `local`). When `r2`, read
`MEDIA_R2_ACCOUNT_ID`, `MEDIA_R2_ACCESS_KEY_ID`, `MEDIA_R2_SECRET_ACCESS_KEY`,
`MEDIA_R2_BUCKET`, `MEDIA_R2_ENDPOINT`. Added to each service's `.env.example`.
Secrets are never logged or printed.

### D6: Frontend uses `FileDropzone` everywhere
Avatar, school logo, and teacher/student photo uploads use the existing
`FileDropzone` in single-image mode (`accept="image/*"`, `maxSize=2MB`),
replacing bare `<input type="file">`. `next.config.ts` `remotePatterns` extends
to billing and academic-ops media paths (and stays env-host aware).

## Risks / Trade-offs

- **Proxy bandwidth**: serving via backend uses service bandwidth/CPU vs direct
  R2. → Acceptable for low-volume profile images; `Cache-Control: immutable` and
  CDN in front mitigate; revisit per 18_media_storage triggers.
- **R2 client dependency weight** added to three services. → One shared crate
  isolates the client; only constructed when `MEDIA_BACKEND=r2`.
- **Migration of existing local files to R2** is not automatic. → Out of scope;
  existing `media://` rows keep resolving via whichever backend holds the bytes;
  document that switching backends does not move existing objects.
- **Print fidelity for student photos** with `next/image`. → Use a plain `<img>`
  with a resolved absolute URL on the print page to avoid optimizer issues.
- **Content-type trust**: we store the client/declared content-type. → Validate
  against an allowlist (jpeg/png/webp) on upload; serve only stored allowlisted
  types.

## Migration Plan

1. Land `common-media` with `local` backend; refactor the three services to use
   it (behavior-preserving for iam besides the content-type fix).
2. Add serve endpoints to billing + academic-ops; add URI resolution to billing.
3. Add the `r2` backend behind `MEDIA_BACKEND`.
4. Add teacher/student upload UI + report-card print photo.
5. Rollback: `MEDIA_BACKEND=local` restores disk behavior; serve endpoints and
   the library are additive and safe to keep.
