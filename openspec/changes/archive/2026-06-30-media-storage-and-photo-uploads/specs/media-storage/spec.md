## ADDED Requirements

### Requirement: Media storage SHALL be provided by a shared backend library

The backend SHALL provide a shared `common-media` library that all
media-owning services use for storing, retrieving, and deleting uploaded media.
The library MUST define a `StorageBackend` abstraction with at least `put`,
`get` (returning bytes and content type), and `delete` operations, and MUST
centralize media validation (maximum size and allowed content types). Services
MUST NOT implement their own ad-hoc byte storage or URL construction.

#### Scenario: Service stores media through the shared library

- **WHEN** a service receives a valid image upload
- **THEN** it persists the bytes via the shared `StorageBackend` and records a `media_asset` row with the resolved `file_url`, in the same transaction as the owning-entity reflection

#### Scenario: Oversized file is rejected

- **WHEN** an upload exceeds 2MB
- **THEN** the shared validation rejects it with a `FILE_TOO_LARGE` error and no bytes are stored

#### Scenario: Disallowed content type is rejected

- **WHEN** an upload is not one of `image/jpeg`, `image/png`, or `image/webp`
- **THEN** the shared validation rejects it with an `INVALID_FILE_TYPE` error and no bytes are stored

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
