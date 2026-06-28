## ADDED Requirements

### Requirement: Storage keys SHALL be prefixed by owner type

The shared media library SHALL derive the physical storage key from the
media owner type and media id as `"{owner_type}/{media_id}"`, and IAM
avatars SHALL use a fixed `avatar/{media_id}` prefix. Keys MUST be
reconstructed at runtime from the owner type already recorded on the media
asset (or the known avatar kind for IAM); the library MUST NOT require a
persisted `storage_key` column. Any code path that produces a storage key
MUST read the owner type first. The `/` is a prefix delimiter only — the
backing store (R2/local) remains a flat namespace.

#### Scenario: Student photo is stored under its owner-type prefix

- **WHEN** a student photo is uploaded
- **THEN** the object is stored at `student/{media_id}` and served/deleted
  by reconstructing that key from the row's `owner_type`

#### Scenario: Avatar is stored under the avatar prefix

- **WHEN** an IAM user uploads an avatar
- **THEN** the object is stored at `avatar/{media_id}` using IAM's hardcoded
  prefix

### Requirement: Media SHALL support hard deletion of stored objects

The shared library's `StorageBackend::delete` SHALL be used by media-owning
services to permanently remove stored bytes. Deletion MUST be idempotent:
deleting a key whose object is already absent MUST NOT error (local ignores
`NotFound`; R2/S3 `delete_object` is idempotent). A hard delete removes both
the database row(s) and the backing-store object(s) for the affected keys.

#### Scenario: Deleting an already-removed object succeeds

- **WHEN** a delete is issued for a key with no backing object
- **THEN** the operation completes without error

## MODIFIED Requirements

### Requirement: Media storage SHALL be provided by a shared backend library

The backend SHALL provide a shared `common-media` library that all
media-owning services use for storing, retrieving, and deleting uploaded
media. The library MUST define a `StorageBackend` abstraction with at least
`put`, `get` (returning bytes and content type), and `delete` operations,
and MUST centralize media validation (maximum size and allowed content
types). Services MUST NOT implement their own ad-hoc byte storage or URL
construction.

> Modified: maximum upload size lowered from 2 MB to 512 KB; key derivation
> and delete usage are now normative (see the two ADDED requirements above).

#### Scenario: Oversized file is rejected

- **WHEN** an upload exceeds 512 KB
- **THEN** the shared validation rejects it with a `FILE_TOO_LARGE` error
  and no bytes are stored

#### Scenario: Disallowed content type is rejected

- **WHEN** an upload is not one of `image/jpeg`, `image/png`, or `image/webp`
- **THEN** the shared validation rejects it with an `INVALID_FILE_TYPE`
  error and no bytes are stored
