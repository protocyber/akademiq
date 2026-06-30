## ADDED Requirements

### Requirement: IAM SHALL serve avatars with their stored content type

The iam service SHALL serve avatar media via `GET /api/v1/iam/media/:media_id`
returning the `content_type` recorded on the `media_asset` row, so that
`next/image` and browsers treat the response as an image rather than a generic
binary download.

#### Scenario: Avatar served as an image

- **WHEN** a client requests an existing avatar media id
- **THEN** the service responds 200 with the stored image content type (e.g. `image/jpeg`) and the avatar bytes

#### Scenario: Avatar renders through the image optimizer

- **WHEN** the web app loads a user's resolved `avatar_url` through `next/image`
- **THEN** the optimizer accepts the response content type and the avatar renders
