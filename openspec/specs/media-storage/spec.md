# media-storage Specification

## Purpose

Defines shared backend media storage behavior for uploaded files, including storage abstraction, backend selection, content validation, media serving, and response URL resolution.
## Requirements
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

### Requirement: The storage backend SHALL be selectable between local disk and Cloudflare R2 via environment

The shared library SHALL select its storage backend from environment
configuration (`MEDIA_BACKEND=local|r2`, defaulting to `local`). The `r2`
backend MUST use an S3-compatible client configured from environment variables
for account, credentials, bucket, and endpoint. Switching the backend MUST NOT
require code changes, and credentials MUST NOT be logged or printed.

#### Scenario: Local backend selected

- **WHEN** `MEDIA_BACKEND` is unset or `local`
- **THEN** media bytes are written to and read from the configured local storage directory

#### Scenario: R2 backend selected

- **WHEN** `MEDIA_BACKEND=r2` and R2 credentials are configured
- **THEN** media bytes are written to and read from the configured R2 bucket via the S3-compatible client

#### Scenario: Secrets are not exposed

- **WHEN** the service logs startup or upload activity
- **THEN** no R2 secret access key or other credential value appears in the logs

### Requirement: Each media-owning service SHALL serve media through a backend proxy endpoint with the correct content type

Each service that owns media SHALL expose `GET /api/v1/<service>/media/:media_id`
that streams the stored bytes and returns the `content_type` recorded on the
`media_asset` row (never a generic `application/octet-stream` for known image
types). The response SHALL set a long-lived immutable cache header. Serving MUST
work identically whether the bytes live on local disk or in R2.

#### Scenario: Image is served with its stored content type

- **WHEN** a client requests an existing media id
- **THEN** the service responds 200 with the stored content type (e.g. `image/png`) and the file bytes

#### Scenario: Missing media returns not found

- **WHEN** a client requests a media id with no stored bytes
- **THEN** the service responds with a not-found error

### Requirement: Media API responses SHALL resolve storage URIs to servable HTTP paths

Services SHALL NOT return raw `media://…` or `file://…` strings to clients. Any
API response that exposes a media reference MUST resolve it to the service's
`GET /api/v1/<service>/media/:media_id` path (or return the `media_id` for the
client to build that path).

#### Scenario: Logo list resolves to a servable path

- **WHEN** the school media list is returned
- **THEN** each active asset exposes a resolvable HTTP media path, not a raw `media://` URI

#### Scenario: Avatar resolves to a servable path

- **WHEN** `/me` returns a user with an avatar
- **THEN** `avatar_url` is a resolvable HTTP media path, not a raw `media://` URI

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

