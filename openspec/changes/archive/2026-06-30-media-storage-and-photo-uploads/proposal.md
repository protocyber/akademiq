## Why

Uploaded images are broken across the app: the school logo on
`/settings/school-profile` renders a raw `media://…` URI the browser cannot
load, and the `/profile` avatar fails because the serve endpoint returns the
wrong content type and the bytes never reach `next/image`. The three media
implementations (iam, billing, academic-ops) diverged independently — only iam
has a working serve path, billing and academic-ops have none, and academic-ops
records an unusable `file://"…"` URL. On top of fixing this, we need teacher and
student photo upload (rendered on the report-card print page) and a way to
switch storage between local disk and Cloudflare R2 via `.env`.

## What Changes

- Add a shared backend library `libs/common-media` with a `StorageBackend`
  trait and two implementations selected by env (`MEDIA_BACKEND=local|r2`),
  centralizing validation (max 2MB, allowed image types) and URL resolution.
  Decision and rationale recorded in
  `docs/internal/13_engineering_standards/18_media_storage.md`.
- Add Cloudflare R2 (S3-compatible) storage backend; credentials read from env.
- Every media-owning service exposes a **backend proxy** serve endpoint
  `GET /api/v1/<service>/media/:media_id` that returns the stored
  `content_type` (not `application/octet-stream`).
- Fix billing logo: add the serve endpoint and resolve `media://` → HTTP path so
  `/settings/school-profile` renders the logo.
- Fix iam avatar: serve the correct `content_type` so `next/image` accepts it.
- Fix academic-ops: replace `format!("file://{path:?}")` with the shared
  library's URL scheme and add the serve endpoint.
- Add teacher and student photo upload UI (using the existing `FileDropzone`
  component) wired to the academic-ops `media` endpoint, populating
  `photo_media_id`.
- Render student photo on the report-card print page.
- Convert the avatar and school-logo uploads to use the existing `FileDropzone`
  component instead of bare `<input type="file">`.
- Update `next.config.ts` image `remotePatterns` to cover the billing and
  academic-ops media paths.

## Capabilities

### New Capabilities
- `media-storage`: Backend media storage abstraction — the `common-media`
  library, the `local` and `r2` backends, env-based selection, the per-service
  proxy serve endpoint contract, content-type handling, and `media://` URI
  resolution.

### Modified Capabilities
- `web-file-upload`: Extend the reusable upload primitives so avatar, school
  logo, and teacher/student photo uploads all use the shared `FileDropzone`
  (single-image mode, 2MB limit, image MIME constraint).
- `academic-ops-service`: Add the teacher/student photo upload + serve behavior
  and `photo_media_id` reflection through the shared library.
- `billing-service`: Add the school-logo serve endpoint and `media://`
  resolution.
- `iam-service`: Serve avatars with the correct stored content type.
- `web-report-cards`: Render the student photo on the report-card print page.

## Impact

- **Backend**: new `libs/common-media` crate (workspace dep wiring); changes in
  `iam-service`, `billing-service`, `academic-ops-service` (http routes,
  commands, state/config, env). New `MEDIA_BACKEND` + R2 env vars in each
  service's `.env.example`. R2 adds an S3-compatible client dependency.
- **Web**: `avatar-upload.tsx`, `settings/school-profile/page.tsx`, new
  teacher/student photo upload UI, report-card print page, `next.config.ts`
  image patterns.
- **Infra/docs**: `apps/backend/.env.example`, root `.env.example` if needed;
  the storage decision doc already added under engineering standards.
- **No new service, no Traefik mapping change** — serving stays on existing
  service path prefixes.
