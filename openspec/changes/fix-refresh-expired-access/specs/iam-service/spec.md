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
