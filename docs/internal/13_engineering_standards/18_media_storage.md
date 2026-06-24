# Media Storage Strategy

This document records how AcademiQ stores and serves uploaded media
(avatars, school logos, student/teacher photos) and **why we use a shared
library instead of a dedicated storage service today**. It also defines the
concrete triggers that would justify extracting a `storage-service` later.

## Decision

> Media storage is implemented as a **shared backend library**
> (`libs/common-media`), consumed by each service that owns media. There is
> **no** standalone `storage-service`. Each owning service keeps its own
> `media_asset` table and writes the active-media reflection
> (`photo_media_id` / `logo_media_id`) in the **same database transaction** as
> the media insert.

The library provides:

- A `StorageBackend` trait with two implementations selected by environment:
  - `local` — writes bytes to a configured directory (current behaviour).
  - `r2` — Cloudflare R2 (S3-compatible) object storage.
- One validation path (max size, allowed content types).
- One URL-resolution scheme so the frontend never receives a raw
  `media://` URI.

Backend selection is env-driven (e.g. `MEDIA_BACKEND=local|r2`). R2 credentials
are read from env. See the per-service `.env.example` for the variable names.
Switching between `local` and `r2` does not migrate existing objects; copy or
re-upload media before flipping an environment that already has uploads.

### Serving model

Images are served through a **backend proxy** endpoint per service
(`GET /api/v1/<service>/media/:media_id`), regardless of whether the bytes live
on local disk or in R2. The browser always talks to a same-origin path; R2 is a
backend storage detail. This keeps the frontend uniform across environments,
avoids CORS and public-bucket exposure, and leaves room for access control on
the serve path later.

The serve handler **must** return the stored `content_type` from
`media_asset`, not a hard-coded `application/octet-stream`, so that
`next/image` and browsers treat the response as an image.

## Why a shared library and not a `storage-service`

A dedicated `storage-service` is a legitimate end-state — the existing
"A future File service can replace this backend" comments in
`billing-service` and `academic-ops-service` anticipate it. We deliberately
chose **not** to build it yet. The reasoning:

1. **Atomicity of active-media reflection.** Each owning service updates its
   entity (`student.photo_media_id`, `tenant.logo_media_id`, the user avatar)
   in the *same transaction* as the `media_asset` insert. Moving storage into a
   separate service turns every upload into a distributed write (store bytes in
   storage-service **and** set `*_media_id` in the owning service) with no
   shared transaction. That requires an outbox/saga to stay consistent — heavy
   machinery for uploading an image.

2. **No new synchronous shared dependency on the upload hot path.** A
   storage-service that every service calls on upload becomes a new shared
   runtime dependency: if it is down, nobody can upload an avatar, logo, or
   student photo. The projection/event model in this codebase exists precisely
   to avoid this kind of synchronous cross-service coupling.

3. **The duplicated logic is small.** Storage is roughly "validate → write/put
   → return URL." A shared library captures 100% of the deduplication value
   (one R2 client, one trait, one validation routine, one content-type fix)
   without introducing a network hop or a distributed transaction.

4. **Lowest-cost change.** A new service requires (per
   [`01_repo_structure.md`](./01_repo_structure.md) and the parent
   `AGENTS.md`): a new crate, `storage_db`, refinery migrations, Makefile
   targets, a `docker-compose` entry, a Traefik `PathPrefix(/api/v1/storage)`
   mapping, a `STORAGE_PORT` slot, OTel wiring, and an integration harness. The
   shared library needs none of that.

5. **No bridge burned.** The `StorageBackend` trait defined in the library is
   the same abstraction we would extract into a service later. Building the
   library builds the seam.

### Trade-off summary

| Concern                       | `common-media` lib | `storage-service` |
|-------------------------------|--------------------|-------------------|
| Coupling on upload path       | none               | hard sync dep     |
| Active-media reflection       | single DB tx       | distributed write (saga) |
| Effort to ship                | small              | large             |
| R2 credential surface         | per consuming service | single service |
| CDN / cache rule              | per service        | centralized       |
| Independent scaling / async   | no                 | yes               |

## When to revisit (migrate to `storage-service`)

Reconsider a dedicated service when **any** of the following becomes true:

1. **Non-owned media appears.** Media that is not owned by exactly one entity
   in one service (e.g. chat attachments, a shared document library, bulk
   uploads) weakens the in-transaction reflection argument that anchors this
   decision.
2. **Async/heavy processing is required.** Thumbnail generation, image
   transcoding, virus scanning, or OCR — work with a different scaling profile
   and failure domain than the owning services' request paths.
3. **Independent scaling or bandwidth isolation** is needed so that media
   traffic stops competing with auth, grading, or academic workloads.
4. **A cross-service media catalog** must outlive any single owning service, or
   media must be queried/managed independently of its owner.
5. **Credential or compliance isolation** (e.g. a single audited egress point
   for object storage) becomes a hard requirement.

When migrating, the `StorageBackend` trait moves behind a service boundary and
each owning service replaces its in-process call with a client call plus an
outbox event to preserve the active-media reflection.

## Current implementation notes (state at time of writing)

- `iam-service` serves avatars at `GET /api/v1/iam/media/:media_id` and
  resolves `media://` URIs to that path in its `me` response. This is the
  reference pattern for the proxy serve model.
- `billing-service` (school logo) and `academic-ops-service` (student/teacher/
  family photos) store bytes but, prior to consolidation, lacked a serve
  endpoint and URI resolution — which is why their images failed to load. The
  shared library plus a per-service serve endpoint closes that gap.
- `academic-ops-service` previously recorded `file_url` via
  `format!("file://{path:?}")`, which debug-formats the path (embedded quotes)
  and is not a usable URL; the shared library replaces ad-hoc URL construction.
