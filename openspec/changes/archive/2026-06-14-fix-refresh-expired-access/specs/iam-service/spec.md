## MODIFIED Requirements

### Requirement: Token refresh SHALL depend only on a valid refresh token

`POST /api/v1/iam/auth/refresh` MUST authenticate the request using the supplied
**refresh token alone** and MUST NOT require a non-expired access token. The
service MUST resolve the owning user from the refresh token (whose format embeds
its `jti`), then MUST reject the request if the refresh-token row is missing,
revoked, or expired, and MUST verify the presented secret against the stored
hash before rotating. On success it MUST revoke the old refresh token and issue a
new tenant-scoped access + refresh pair bound to the same tenant.

#### Scenario: Refresh succeeds after the access token has expired

- **WHEN** a client calls `/auth/refresh` with an expired (or omitted) access
  token and a valid, unrevoked refresh token
- **THEN** the service returns a new access + refresh pair and the user is not
  logged out

#### Scenario: Refresh is refused for an invalid refresh token

- **WHEN** the presented refresh token is unknown, revoked, or expired
- **THEN** the service responds `401` and issues no new tokens

#### Scenario: Refresh rotates and revokes within the bound tenant

- **WHEN** a valid refresh token is presented
- **THEN** the new access token carries the same `tenant_id`, and the old refresh
  token row is revoked

### Requirement: Logout SHALL revoke the refresh token regardless of access-token expiry

`POST /api/v1/iam/auth/logout` MUST revoke the supplied refresh token even when
the access token presented (if any) has expired. Logout MUST NOT require a live
access token.

#### Scenario: Logout works with an expired access token

- **WHEN** a client calls `/auth/logout` with an expired access token and a valid
  refresh token
- **THEN** the refresh token is revoked and the response is `204`

### Requirement: `/me` SHALL authenticate with either an identity or a tenant-scoped access token

`GET /api/v1/iam/me` (and `GET /api/v1/iam/my-tenants`) MUST resolve the caller's
`user_id` from **either** a valid identity token (`typ:"identity"`) **or** a valid
tenant-scoped access token (`typ:"access"`). Requiring the identity token alone
forced a logout once it expired: the identity token has a short TTL and is
**non-refreshable**, whereas after tenant entry the client holds a tenant-scoped
access token that is silently renewable via the refresh token for the full
refresh-token lifetime. Accepting the access token lets the session survive
identity-token expiry.

#### Scenario: `/me` succeeds with a tenant-scoped access token

- **WHEN** a client calls `/me` with a valid tenant-scoped access token and no
  identity token
- **THEN** the service returns the caller's profile with `200`

#### Scenario: `/me` succeeds with an identity token (pre-tenant-entry)

- **WHEN** a client calls `/me` with a valid identity token
- **THEN** the service returns the caller's profile with `200`

#### Scenario: `/me` surfaces `EXPIRED_ACCESS_TOKEN` for an expired access token

- **WHEN** a client calls `/me` with an expired tenant-scoped access token
- **THEN** the service responds `401` with code `EXPIRED_ACCESS_TOKEN` so the web
  client recognizes it and triggers a silent refresh instead of logging out
