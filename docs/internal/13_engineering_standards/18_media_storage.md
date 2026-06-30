# Media Storage Strategy

This document records how AkademiQ stores and serves uploaded media
(avatars, school logos, student/teacher/family photos) and **why we use a shared
library instead of a dedicated storage service today**. It also defines the
concrete triggers that would justify extracting a `storage-service` later.

## Decision

> Media storage is implemented as a **shared backend library**
> (`libs/common-media`), consumed by each service that owns media. There is
> **no** standalone `storage-service`. Each owning service stores the active
> photo/logo as a `media://` URI directly on the owning entity column
> (`photo_url` / `logo_url`) — a single-active, no-history model mirroring
> the IAM avatar pattern.

The library provides:

- A `StorageBackend` trait with two implementations selected by environment:
  - `local` — writes bytes to a configured directory (current behaviour).
  - `r2` — Cloudflare R2 (S3-compatible) object storage.
- One validation path (512 KB max size, allowed content types).
- One key-derivation convention: owner-backed media is stored at
  `{owner_type}/{media_id}` and IAM avatars at `avatar/{media_id}`.
- One URL-resolution scheme so the frontend never receives a raw
  `media://` URI — every HTTP response resolves the URI to a renderable
  serve path before returning.

Backend selection is env-driven (`MEDIA_BACKEND=local|r2`). R2 credentials
are read from env. See the per-service `.env.example` for the variable names.
Switching between `local` and `r2` does not migrate existing objects; copy or
re-upload media before flipping an environment that already has uploads.

### Storage key convention

Object keys are grouped by logical owner prefix, but the prefix is
**reconstructed at runtime** from the serve path rather than persisted in a
separate column:

- `academic-ops-service`: `{owner_type}/{media_id}` for `student`, `teacher`,
  and `family` media.
- `billing-service`: `school/{media_id}` for school logos.
- `iam-service`: `avatar/{media_id}` for avatars.

R2/S3 remains a flat namespace; `/` is only a visual prefix delimiter. The
serve handler uses the `owner_type` path segment to reconstruct the key —
no DB lookup is needed because content-type lives in the storage sidecar (local)
or object metadata (R2).

If the folder convention changes later, existing objects need a new object
migration. That is the cost of reconstructing the key instead of persisting it;
we accept it to avoid storing redundant, drift-prone data.

### Single-active model (no history)

Each entity carries exactly one active photo/logo at a time. The columns are:
- `tenant.logo_url` — school logo (Billing)
- `student.photo_url`, `teacher.photo_url`, `family_profile.photo_url` — people photos (Academic Ops)
- `iam.user.avatar_url` — user avatar (IAM)

All four store a host-agnostic `media://{owner_id}/{media_id}.{ext}` URI.
The HTTP layer calls `resolve_media_uri_for_owner` (or `resolve_media_uri_for_avatar`
for IAM) to turn this into a public serve path before including it in responses.

### Deletion and garbage collection

The previous blob is garbage-collected synchronously when a new photo/logo is
uploaded (GC-on-replace) or when the photo/logo is explicitly cleared. The storage
backend's `delete` operation is idempotent, so missing objects do not cause errors.
An upload failure after the blob is written but before the column is updated leaves
the blob orphaned; a future admin tool could sweep unreferenced blobs if needed.

### Upload limit and client compression

The backend shared limit is 512 KB (`common-media::MAX_MEDIA_SIZE_BYTES`). The
web client compresses image uploads in the browser (canvas downscale, longest
edge cap, JPEG/WebP re-encode) before sending avatar, logo, and student/teacher
photo uploads so phone-camera images can fit under the server limit.

### Serving model

Images are served through a **backend proxy** endpoint per service, regardless
of whether the bytes live on local disk or in R2. The browser always talks to a
same-origin path; R2 is a backend storage detail.

Serve path patterns:
- `GET /api/v1/iam/media/{media_id}` — avatar (IAM, key `avatar/{media_id}`)
- `GET /api/v1/billing/media/school/{media_id}` — school logo (key `school/{media_id}`)
- `GET /api/v1/academic-ops/media/{owner_type}/{media_id}` — people photos (key `{owner_type}/{media_id}`)

The serve handler reconstructs the storage key from the path segments — no DB
lookup required. It returns the stored object content type (not a hard-coded
`application/octet-stream`) so that `next/image` and browsers treat the response
as an image.

## Why a shared library and not a `storage-service`

A dedicated `storage-service` is a legitimate end-state. We deliberately chose
**not** to build it yet. The reasoning:

1. **Atomicity.** Each owning service updates its entity column (`photo_url`,
   `logo_url`, `avatar_url`) in the *same transaction* as the storage write
   (or, in the single-active model, in a separate commit immediately after the
   blob put). A separate service turns every upload into a distributed write with
   no shared transaction — heavy machinery for uploading an image.

2. **No new synchronous shared dependency on the upload hot path.** A
   storage-service that every service calls on upload becomes a new shared
   runtime dependency: if it is down, nobody can upload an avatar, logo, or
   student photo.

3. **The duplicated logic is small.** Storage is roughly "validate → write/put
   → return URL." A shared library captures 100% of the deduplication value
   (one R2 client, one trait, one validation routine, one content-type fix)
   without introducing a network hop or a distributed transaction.

4. **Lowest-cost change.** A new service requires a new crate, a separate DB,
   refinery migrations, Makefile targets, a docker-compose entry, a Traefik
   mapping, OTel wiring, and an integration harness. The shared library needs
   none of that.

5. **No bridge burned.** The `StorageBackend` trait defined in the library is
   the same abstraction we would extract into a service later.

### Trade-off summary

| Concern                       | `common-media` lib | `storage-service` |
|-------------------------------|--------------------|-------------------|
| Coupling on upload path       | none               | hard sync dep     |
| Active-media reflection       | single DB write    | distributed write |
| Effort to ship                | small              | large             |
| R2 credential surface         | per consuming service | single service |
| CDN / cache rule              | per service        | centralized       |
| Independent scaling / async   | no                 | yes               |

## When to revisit (migrate to `storage-service`)

Reconsider a dedicated service when **any** of the following becomes true:

1. **Non-owned media appears.** Media that is not owned by exactly one entity
   in one service (e.g. chat attachments, a shared document library, bulk
   uploads) weakens the in-transaction reflection argument.
2. **Async/heavy processing is required.** Thumbnail generation, image
   transcoding, virus scanning, or OCR.
3. **Independent scaling or bandwidth isolation** is needed so that media
   traffic stops competing with auth, grading, or academic workloads.
4. **A cross-service media catalog** must outlive any single owning service.
5. **Credential or compliance isolation** (e.g. a single audited egress point
   for object storage) becomes a hard requirement.

When migrating, the `StorageBackend` trait moves behind a service boundary and
each owning service replaces its in-process call with a client call plus an
outbox event to preserve the active-photo reflection.
