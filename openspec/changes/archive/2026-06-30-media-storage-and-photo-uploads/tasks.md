# Implementation Tasks

## 1. Shared `common-media` library (local backend)

- [x] 1.1 Create `apps/backend/libs/common-media` crate; register it in the workspace `Cargo.toml` `[workspace.dependencies]`
- [x] 1.2 Define the `StorageBackend` trait (`put`, `get` → bytes + content_type, `delete`) and a `MediaError`/`AppError` mapping
- [x] 1.3 Implement `LocalBackend` (configured directory) preserving current on-disk behavior
- [x] 1.4 Add shared validation: max 2MB, allowed types `image/jpeg|png|webp`, returning `FILE_TOO_LARGE` / `INVALID_FILE_TYPE`
- [x] 1.5 Add a canonical `media://` URI builder + resolver to a service-relative `/api/v1/<service>/media/:id` path
- [x] 1.6 Add backend selection from env (`MEDIA_BACKEND`, default `local`) with a constructor used at startup
- [ ] 1.7 Unit tests for validation, URI build/resolve, and local round-trip (put/get/delete) — skipped backend test execution; run manually: `cd apps/backend && cargo test -p common-media`

## 2. Cloudflare R2 backend

- [x] 2.1 Add an S3-compatible client dependency to the workspace (gated to `common-media`)
- [x] 2.2 Implement `R2Backend` (`put`/`get`/`delete`) against the R2 endpoint/bucket
- [x] 2.3 Read R2 config from env (`MEDIA_R2_ACCOUNT_ID`, `MEDIA_R2_ACCESS_KEY_ID`, `MEDIA_R2_SECRET_ACCESS_KEY`, `MEDIA_R2_BUCKET`, `MEDIA_R2_ENDPOINT`); ensure no secret is logged
- [ ] 2.4 Wire `MEDIA_BACKEND=r2` into the constructor; add an integration/smoke test (skipped when R2 env absent) — skipped backend test execution; run manually: `cd apps/backend && cargo test -p common-media r2`

## 3. iam-service (avatar fix)

- [x] 3.1 Replace ad-hoc disk storage in `commands.rs` avatar upload with `common-media`
- [x] 3.2 Serve `GET /api/v1/iam/media/:id` with the stored `content_type` (drop hard-coded `application/octet-stream`)
- [ ] 3.3 Keep `media://` → HTTP resolution in `/me`; add/adjust tests asserting image content type on serve — skipped backend test execution; run manually: `cd apps/backend && cargo test -p iam-service`

## 4. billing-service (logo fix)

- [x] 4.1 Refactor `upload_school_logo` to store via `common-media` (replace inline `file_url` construction)
- [x] 4.2 Add `GET /api/v1/billing/media/:id` serving stored bytes with the recorded content type
- [x] 4.3 Resolve each asset in the school media list to a servable HTTP path (not raw `media://`)
- [ ] 4.4 Update/extend billing integration tests for serve + resolved list — skipped backend test execution; run manually: `cd apps/backend && cargo test -p billing-service`

## 5. academic-ops-service (student/teacher photo backend)

- [x] 5.1 Refactor `store_media_locally` to use `common-media`; remove `format!("file://{path:?}")`
- [x] 5.2 Add `GET /api/v1/academic-ops/media/:id` serving stored bytes with the recorded content type
- [x] 5.3 Confirm `reflect_active_media` still sets `photo_media_id` in the same transaction for student and teacher
- [ ] 5.4 Update/extend academic-ops integration tests (upload → reflected `photo_media_id` → serve) — skipped backend test execution; run manually: `cd apps/backend && cargo test -p academic-ops-service`

## 6. Env & config

- [x] 6.1 Add `MEDIA_BACKEND` + R2 vars to `apps/backend/.env.example` (and per-service config structs) with safe defaults
- [x] 6.2 Document the local↔R2 switch and that switching does not migrate existing objects (point to `docs/internal/13_engineering_standards/18_media_storage.md`)

## 7. Web — fix rendering + dropzone reuse

- [x] 7.1 School logo: render the resolved media path (stop using raw `file_url`) in `settings/school-profile/page.tsx`
- [x] 7.2 Convert avatar upload (`avatar-upload.tsx`) and school-logo upload to the shared `FileDropzone` (image/*, 2MB)
- [x] 7.3 Update `next.config.ts` `remotePatterns` to cover billing + academic-ops media paths (env-host aware)
- [x] 7.4 Verify avatar renders via `next/image` after the content-type fix

## 8. Web — teacher & student photo upload

- [x] 8.1 Add a reusable photo-upload UI (FileDropzone-based) wired to `POST /api/v1/academic-ops/media` with owner_type/owner_id
- [x] 8.2 Integrate it on the student create/edit surface (populate/refresh `photo_media_id`)
- [x] 8.3 Integrate it on the teacher create/edit surface (populate/refresh `photo_media_id`)
- [x] 8.4 Add TanStack Query mutation + cache invalidation; centralized error messages for `FILE_TOO_LARGE` / `INVALID_FILE_TYPE`

## 9. Web — report-card print photo

- [x] 9.1 Resolve the student's `photo_media_id` to an absolute academic-ops media URL on the print page
- [x] 9.2 Render it with a plain `<img>` (not `next/image`) for print fidelity; render cleanly when no photo

## 10. Verification

- [ ] 10.1 Backend: `cd apps/backend && make test` (common-media + affected service suites) green — skipped backend test execution; run manually: `cd apps/backend && make test`
- [x] 10.2 Web: lint + typecheck + relevant component tests green
- [ ] 10.3 Manual: avatar at `/profile`, logo at `/settings/school-profile`, student/teacher photo upload, and student photo on report-card print all load with `MEDIA_BACKEND=local`
- [ ] 10.4 Manual: same flows load with `MEDIA_BACKEND=r2` using provided credentials

## Manual Backend Tests

- `cd apps/backend && cargo test -p common-media`
- `cd apps/backend && cargo test -p common-media r2`
- `cd apps/backend && cargo test -p iam-service`
- `cd apps/backend && cargo test -p billing-service`
- `cd apps/backend && cargo test -p academic-ops-service`
- `cd apps/backend && make test`
