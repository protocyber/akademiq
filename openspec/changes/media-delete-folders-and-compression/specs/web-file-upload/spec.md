## ADDED Requirements

### Requirement: Media upload surfaces SHALL offer a delete action

The photo-upload (student/teacher), avatar-upload, and school-logo surfaces
SHALL each provide a "Hapus" delete affordance that calls the matching
hard-delete endpoint. The delete action SHALL confirm before executing
(destructive, non-reversible) and SHALL invalidate the relevant media
queries on success so the UI reverts to the placeholder.

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
- **THEN** the client compresses it before upload and the request stays
  within the 512 KB server limit

### Requirement: The upload size limit SHALL be centralized

The 512 KB maximum and its user-facing hint text SHALL be defined in a
single shared location and consumed by the avatar, logo, and student/teacher
photo upload surfaces, so the limit cannot drift between components.

## MODIFIED Requirements

### Requirement: File uploads SHALL use the shared FileDropzone with a single image constraint

> Modified: the enforced maximum is now 512 KB (was 2 MB) and client-side
> compression is applied before upload (see ADDED requirements above). The
> accept constraint (`image/jpeg|png|webp`) is unchanged.
