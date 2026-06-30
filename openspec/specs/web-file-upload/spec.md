# web-file-upload Specification

## Purpose

Defines reusable web file-upload UI primitives and spreadsheet import dialogs for operational screens.
## Requirements
### Requirement: The web app SHALL provide a reusable drag-and-drop file dropzone

The web app SHALL provide a reusable `FileDropzone` component (`src/components/ui/file-dropzone.tsx`) that accepts a single file via both drag-and-drop and click-to-browse, styled with shadcn tokens. It MUST accept an `accept` (MIME/extension) constraint and an optional `maxSize`, MUST reject files that fail those constraints with inline feedback, and MUST show the selected file's name (and size) with a control to clear the selection. All single-image upload surfaces — profile avatar, school logo, and teacher/student photo — MUST use `FileDropzone` configured with client-side compression and a 512 KB maximum size (was 2 MB) and the accept constraint `image/jpeg|png|webp` (image/*).

#### Scenario: Image upload surfaces reuse the dropzone

- **WHEN** a user opens the avatar, school-logo, or teacher/student photo upload
- **THEN** the upload UI is the shared `FileDropzone` constrained to images up to 512 KB, and an over-limit or non-image file is rejected with inline feedback

### Requirement: Spreadsheet import SHALL be available as a reusable dialog on the relevant screens

The web app MUST provide a reusable `ImportDialog` that wraps `FileDropzone`, a
download-template link, the import action, and a row-level error report for failed
validation. It MUST be launched from an **[Impor ▾]** control on the `/students`
and `/teachers` screens. The standalone `/import` page MUST be removed and the
operational navigation MUST NOT include an Import entry.

#### Scenario: Import a valid sheet from the students screen

- **WHEN** an admin opens the import dialog from `/students`, drops a valid sheet, and submits
- **THEN** the import runs, a success summary is shown, and the students table reflects the imported rows

#### Scenario: Row-level errors are reported in the dialog

- **WHEN** an admin imports a sheet with an invalid row
- **THEN** the dialog shows the per-row error report and no rows are persisted

#### Scenario: The standalone import page is gone

- **WHEN** a user navigates to `/import`
- **THEN** the standalone page no longer exists and import is reached via the [Impor ▾] control on `/students` and `/teachers`

### Requirement: Media upload surfaces SHALL offer a delete action

The web app SHALL provide a "Hapus" delete affordance on the photo-upload (student/teacher), avatar-upload, and school-logo surfaces that calls the matching hard-delete endpoint. The delete action SHALL confirm before executing (destructive, non-reversible) and SHALL invalidate the relevant media queries on success so the UI reverts to the placeholder.

#### Scenario: Deleting a photo reverts the UI to the placeholder

- **WHEN** a user confirms deletion of a student photo
- **THEN** the delete endpoint is called, the media query is invalidated,
  and the placeholder icon is shown

### Requirement: Image uploads SHALL be compressed client-side

Before uploading, the web client SHALL downscale and re-encode the selected
image (longest edge capped, JPEG/WebP re-encode) so that the compressed
output targets the 512 KB server limit. The compressed blob is what is sent
to the backend; the original oversized file is never uploaded uncompressed.

#### Scenario: A phone photo is compressed before upload

- **WHEN** a user selects a multi-megapixel phone photo
- **THEN** the client compresses it before upload and the request stays within the 512 KB server limit

### Requirement: The upload size limit SHALL be centralized

The 512 KB maximum and its user-facing hint text SHALL be defined in a single shared location and consumed by the avatar, logo, and student/teacher photo upload surfaces, so the limit cannot drift between components.

#### Scenario: Shared constant is consumed by all upload surfaces

- **WHEN** the upload limit needs to be referenced in the UI
- **THEN** all surfaces retrieve the centralized 512 KB limit and hint text from a source of truth

