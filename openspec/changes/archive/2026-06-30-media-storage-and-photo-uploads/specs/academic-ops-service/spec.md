## ADDED Requirements

### Requirement: Academic Ops SHALL store and serve student and teacher photos

The academic-ops service SHALL accept photo uploads for students and teachers
through `POST /api/v1/academic-ops/media`, store the bytes via the shared
`common-media` library, record a `media_asset` row, and reflect the new active
asset onto the owning entity's `photo_media_id` in the same transaction. It MUST
expose `GET /api/v1/academic-ops/media/:media_id` to serve the stored bytes with
their recorded content type. Stored references MUST use the shared library's URL
scheme and MUST NOT be debug-formatted paths.

#### Scenario: Upload a student photo

- **WHEN** an admin uploads a valid image for a student
- **THEN** the photo is stored, `student.photo_media_id` is set to the new asset, and the previous active asset for that student is deactivated

#### Scenario: Serve a stored photo

- **WHEN** a client requests an existing academic-ops media id
- **THEN** the service responds 200 with the stored content type and the file bytes

#### Scenario: Stored reference is a usable URL

- **WHEN** a photo is stored
- **THEN** the recorded `file_url` is a valid media URI (not `file://"…"` debug output) that resolves to the serve endpoint
