# iam-service Specification

## Purpose

Defines authentication and identity requirements for the iam-service (Identity & Access Management Service), including tenant-less identity tokens issued at login, public self-registration, tenant entry/listing, tenant-scoped access and refresh tokens, the built-in role and permission vocabulary, custom tenant roles, multi-role membership, and effective-permission resolution.
## Requirements
### Requirement: IAM SHALL seed the built-in role set

IAM MUST seed the platform's built-in roles with stable `role.code` values
that match the `ROLE_*` constants in `common-auth`. The seeded set MUST
include `super_admin`, `tenant_admin`, `teacher`, `homeroom_teacher`,
`principal`, `student`, and `parent`. The `principal` role is the final
academic approver in the report-card workflow.

#### Scenario: Principal is part of the seeded role set

- **WHEN** IAM migrations run against an empty database
- **THEN** the `role` table contains a `principal` row whose code matches `ROLE_PRINCIPAL` in `common-auth`, alongside the other six built-in roles

#### Scenario: Role codes match auth constants

- **WHEN** a contributor compares seeded `role.code` values to the `ROLE_*` constants in `common-auth`
- **THEN** every seeded code has a corresponding constant and vice versa

### Requirement: Authorization SHALL be decided by permissions, not role names

The platform MUST define a fixed, seeded `permission` vocabulary of action codes
(e.g. `user.invite`, `user.disable`, `user.role.assign`, `role.manage`,
`billing.view`, `billing.manage`, `academic.config.write`, `report.generate`,
`report.transition`, `grade.record`). Each built-in role MUST be seeded with a
`role_permission` set that reproduces its current behavior. Service authorization
checks MUST be expressed as permission checks (`require_permission`) rather than
role-name comparisons. The permission vocabulary MUST NOT be editable by tenants.

#### Scenario: A held permission authorizes an action

- **WHEN** a caller's access token carries `perms` containing `user.invite`
- **THEN** `POST /tenants/me/invitations` is authorized regardless of which role
  granted that permission

#### Scenario: A missing permission is refused

- **WHEN** a caller's token does not contain `user.invite`
- **THEN** the request is refused with `403 FORBIDDEN`

#### Scenario: Built-in roles preserve prior behavior

- **WHEN** a user holds the built-in `tenant_admin` role after migration
- **THEN** the user is allowed exactly the actions `tenant_admin` could perform
  before this change, now expressed as permissions

### Requirement: Tenant admins SHALL define custom roles from a permission palette

The service MUST expose role-management endpoints gated on the `role.manage`
permission: `GET/POST /tenants/me/roles`, `GET/PATCH/DELETE
/tenants/me/roles/{id}`, `POST /tenants/me/roles/bulk/delete`, and
`GET /tenants/me/permissions` returning the assignable palette. A tenant role
MUST be stored with the tenant's `tenant_id` and a `code` unique within that
tenant that MUST NOT collide with any built-in role code. Built-in roles
(`tenant_id = NULL`) MUST be immutable; customization is achieved by creating a
new role or cloning a built-in.

`GET /tenants/me/roles` MUST accept the query parameters `search` (matches role
name or code, case-insensitive), `sort` (one of `name`, `-name`, `type`,
`-type`, `users`, `-users`), `page`, and `page_size`, and MUST return a
`{ data, meta }` envelope where `meta` carries `page`, `page_size`, and the total
matching `total`. The default sort MUST list built-in roles before custom roles,
then by code. Each role view in `data` MUST include a `user_count` field: the
number of users **in the calling tenant** holding that role (derived from
`user_tenant_role`), computed per-tenant even for built-in roles.

#### Scenario: Admin creates a custom role

- **WHEN** an admin with `role.manage` POSTs `{ code, name, permissions: [...] }`
  to `/tenants/me/roles`
- **THEN** a tenant-scoped role is created with that permission set and HTTP 201

#### Scenario: Built-in role cannot be edited

- **WHEN** a PATCH or DELETE targets a built-in role (`tenant_id = NULL`)
- **THEN** the service responds `403` (or `409`) and the built-in is unchanged

#### Scenario: Custom code cannot shadow a built-in

- **WHEN** an admin creates a role whose `code` equals a built-in code (e.g.
  `principal`)
- **THEN** the request is rejected with a validation error

#### Scenario: Role list is searchable, sortable, and paginated

- **WHEN** an admin GETs `/tenants/me/roles?search=kurikulum&sort=-users&page=1&page_size=25`
- **THEN** the response contains only roles whose name or code matches
  `kurikulum`, ordered by descending `user_count`, and `meta` reports `page`,
  `page_size`, and the total match count

#### Scenario: Role view reports per-tenant usage count

- **WHEN** three users in the calling tenant hold the `teacher` role
- **THEN** that role's view in the list response has `user_count` equal to `3`,
  counting only users in the calling tenant

### Requirement: Admins SHALL delete multiple custom roles in one all-or-nothing request

The service MUST expose `POST /tenants/me/roles/bulk/delete`, gated on
`role.manage`, accepting a list of role ids. The endpoint MUST be
all-or-nothing: it MUST pre-validate every id and, if **any** id is a built-in
role, a role still assigned to one or more users, or not a custom role of the
calling tenant, it MUST reject the entire request without deleting anything. Only
when every id passes MUST it delete all of them in a single transaction, emitting
one `role.deleted` event per deleted role (the same event the single-role delete
emits).

#### Scenario: Bulk delete succeeds for all-custom unused selection

- **WHEN** an admin POSTs ids of two custom roles, neither assigned to any user,
  to `/tenants/me/roles/bulk/delete`
- **THEN** both roles are deleted in one transaction, two `role.deleted` events
  are emitted, and the response is success

#### Scenario: Bulk delete is refused whole if any role is built-in

- **WHEN** the payload includes a built-in role id alongside custom role ids
- **THEN** the request is refused with `403 BUILT_IN_ROLE_IMMUTABLE` and **no**
  role is deleted

#### Scenario: Bulk delete is refused whole if any role is in use

- **WHEN** the payload includes a custom role that is still assigned to at least
  one user
- **THEN** the request is refused with `409 ROLE_IN_USE` and **no** role is
  deleted

### Requirement: Role authoring SHALL NOT escalate privilege

When creating or editing a role, the service MUST reject any permission the
calling admin does not currently hold in their own effective permission set.

#### Scenario: Admin cannot grant a permission they lack

- **WHEN** an admin without `billing.view` attempts to create a role that
  includes `billing.view`
- **THEN** the request is rejected with `403 PRIVILEGE_ESCALATION` and no role is
  created

### Requirement: A user SHALL hold multiple roles within a tenant

`user_tenant_role` MUST permit several rows per `(user_id, tenant_id)`, keyed by
`UNIQUE(user_id, tenant_id, role_id)`. The service MUST provide endpoints to add
and remove a role from a user (gated on `user.role.assign`), replacing the
single-role swap. Removing a role MUST NOT be allowed to leave the tenant with
zero users holding `user.role.assign`.

#### Scenario: A user is granted a second role

- **WHEN** an admin adds `homeroom_teacher` to a user who already holds `teacher`
- **THEN** the user holds both roles in that tenant

#### Scenario: The last administrator cannot be stripped

- **WHEN** removing a role would leave no user in the tenant holding
  `user.role.assign`
- **THEN** the removal is refused with `409 LAST_ADMIN`

### Requirement: Effective permissions SHALL be the union of all the user's roles

The service MUST, when issuing a tenant-scoped access token (at
`/tenants/{id}/enter` and `/auth/refresh`), resolve **all** of the user's roles
in that tenant, set `roles` to the list of role codes held, and set `perms` to
the deduplicated union of those roles' permissions.

#### Scenario: Permissions union across roles

- **WHEN** a user holds two roles granting `{grade.record}` and
  `{report.transition}`
- **THEN** the issued token's `perms` contains both `grade.record` and
  `report.transition`, and `roles` lists both role codes

### Requirement: The access token SHALL carry roles and permissions

The tenant-scoped access token claims MUST be
`{ sub, tenant_id, roles: [code…], perms: [code…], typ: "access", iat, exp, jti }`.
The `roles` array carries role identity for workflow and display; the `perms`
array is the authority used by guards. The single `role: String` claim is
removed after a one-release dual-read compatibility window during which
extractors MUST accept both the legacy `role` claim and the new
`roles`/`perms` claims.

#### Scenario: New token shape is issued

- **WHEN** a user enters a tenant
- **THEN** the access token contains `roles` and `perms` arrays and no scalar
  `role` claim

#### Scenario: Legacy token still verifies during the compatibility window

- **WHEN** a service receives an access token carrying only the legacy
  `role: String` claim during the dual-read window
- **THEN** the extractor accepts it, treating `roles` as `[role]` and resolving
  `perms` from that built-in role's seeded permission set

### Requirement: Custom role codes SHALL NOT drive service workflows

Service state machines (e.g. the report-card approval workflow) MUST match only
built-in role codes (`ROLE_*` constants) when deriving workflow identity. Custom
role codes MAY appear in `roles` for display and audit but MUST NOT be
interpreted as a workflow step.

#### Scenario: Custom role does not gain workflow authority

- **WHEN** a user holds a custom role whose code is not a built-in `ROLE_*`
- **THEN** the report-card workflow does not treat that code as SubjectTeacher,
  HomeroomTeacher, or Principal; workflow authority comes only from held
  permissions and built-in role identity

### Requirement: Login SHALL issue a tenant-less identity token

On successful authentication, `POST /auth/login` MUST issue an **identity token**
whose claims are `{ sub, typ: "identity", iat, exp, jti }` with no `tenant_id` and
no `role`. The identity token MUST be short-lived (default 10 minutes) and MUST
NOT have an associated refresh token. It authorizes only tenant-less endpoints
(`GET /me`, `GET /my-tenants`, `POST /tenants/{id}/enter`, invitation acceptance).

#### Scenario: Login yields an identity token

- **WHEN** a user authenticates successfully via any login method
- **THEN** IAM returns an identity token carrying `typ:"identity"` and no
  `tenant_id`/`role` claim

#### Scenario: Identity token is rejected on tenant-scoped routes

- **WHEN** an identity token is presented to an endpoint that requires tenant
  scope
- **THEN** IAM rejects the request as unauthenticated for that route

### Requirement: Users SHALL list and enter their tenants

IAM MUST expose `GET /my-tenants`, authenticated by an identity token, returning
the caller's memberships as `[{ tenant_id, tenant_name, role_code }]` (empty when
the user belongs to no tenant). IAM MUST expose `POST /tenants/{id}/enter`,
authenticated by an identity token, which verifies the caller is a member of
`{id}` via `user_tenant_role` and then issues a **tenant-scoped** access token
(`{ sub, tenant_id, role, typ:"access" }`) plus a tenant-scoped refresh token.
`/enter` is the only endpoint that mints a tenant-scoped token.

#### Scenario: Member enters a tenant

- **WHEN** a user with membership in tenant `T` calls `POST /tenants/T/enter`
  with a valid identity token
- **THEN** IAM returns a tenant-scoped token envelope with `tenant_id = T` and the
  user's role in `T`

#### Scenario: Non-member is refused

- **WHEN** a user without membership in tenant `T` calls `POST /tenants/T/enter`
- **THEN** IAM responds `403 FORBIDDEN` and issues no token

#### Scenario: Zero-tenant user lists no memberships

- **WHEN** a user who belongs to no tenant calls `GET /my-tenants`
- **THEN** IAM returns an empty array and the user remains on an identity token

### Requirement: Anyone SHALL be able to self-register an account

IAM MUST expose a public, rate-limited `POST /auth/register` that creates a
`"user"` from email + password (and an optional username, auto-generated when
absent) with **no** tenant membership, and returns an identity token. Account
existence MUST NOT require a tenant. The account is created with
`email_verified=false`; a verification email is sent when an email provider is
configured, and the account is usable before verification (verify-later).

#### Scenario: Public signup creates a tenant-less account

- **WHEN** a visitor submits a valid email + password to `POST /auth/register`
- **THEN** IAM creates a user with no `user_tenant_role` rows and returns an
  identity token

#### Scenario: Duplicate email is rejected

- **WHEN** registration is attempted with an email that already exists
  (case-insensitive)
- **THEN** IAM responds `EMAIL_ALREADY_EXISTS` (409) and creates no account

### Requirement: Refresh tokens SHALL be scoped to a tenant

A refresh token MUST be bound to `(user_id, jti, tenant_id)`. `POST /auth/refresh`
MUST re-issue a tenant-scoped access token for the refresh token's bound tenant
and MUST NOT change the tenant. Switching tenants is performed by
`POST /tenants/{id}/enter`, which mints a new tenant-scoped refresh token rather
than mutating an existing one.

#### Scenario: Refresh stays within its tenant

- **WHEN** a refresh token bound to tenant `T` is used at `POST /auth/refresh`
- **THEN** IAM issues a new access token scoped to `T` and rotates the refresh
  token within `T`

#### Scenario: Switching tenants requires re-entering

- **WHEN** a user holding a token scoped to tenant `T` wants to act in tenant `U`
- **THEN** the user must call `POST /tenants/U/enter` (with an identity token) to
  obtain a `U`-scoped token; refresh alone cannot cross from `T` to `U`

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

### Requirement: GET /me SHALL work without a tenant and tolerate a null email

`GET /me` MUST be reachable with an identity token (no tenant entered) and MUST
return the user's profile and memberships. The `email` field MAY be `null` for
users without an email.

#### Scenario: Me under an identity token

- **WHEN** a user calls `GET /me` with an identity token
- **THEN** IAM returns their profile and membership list without requiring a
  tenant scope

#### Scenario: Me for an email-less user

- **WHEN** a user without an email calls `GET /me`
- **THEN** the response includes `email: null` and the rest of the profile

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

### Requirement: Invitations SHALL grant membership to an account that may already exist

Accepting an invitation MUST grant the invited roles and tenant membership. When
the invited email already has an account, acceptance attaches the membership to
that account without requiring a password. When the invited email has **no**
account, acceptance MUST create a new account and attach membership; creating
that account MUST NOT require the invitee to choose a password at accept time.
The invitee MUST be signed in (scoped token pair) upon acceptance in both cases.

#### Scenario: Existing account accepts without a password

- **WHEN** the invited email already has an account and the invitation is accepted
- **THEN** the membership and roles are attached and a scoped session is issued,
  with no password input required

#### Scenario: New account is created without a password

- **WHEN** the invited email has no account and the invitation is accepted with
  only the token
- **THEN** a new account is created in a no-password state, membership and roles
  are granted, and a scoped session is issued

#### Scenario: Name falls back when not provided

- **WHEN** a new account is created from a button-only accept with no name input
- **THEN** the account's name is taken from the invitation record (or a
  placeholder the user can edit later), and acceptance still succeeds

### Requirement: The service SHALL support accounts that have not yet set a password

The service MUST allow an account to exist without a password. Password login
against such an account MUST be rejected with the standard invalid-credentials
error (`INVALID_CREDENTIALS`) — the same code and message returned for a wrong
password — so that the response does **not** reveal whether the account exists
in a no-password state. Non-password authentication (e.g. OAuth) MUST be
unaffected. The distinct `PASSWORD_NOT_SET` code is removed from the login path;
detection of a no-password account for routing purposes is the client's
responsibility, driven by the `password_set` flag on `GET /me`.

#### Scenario: Password login against a no-password account returns invalid credentials

- **WHEN** a user attempts password login on an account with no password set
- **THEN** the response carries the `INVALID_CREDENTIALS` code (not a distinct
  no-password code) and no session is issued

#### Scenario: OAuth login is unaffected by password state

- **WHEN** a no-password account authenticates via OAuth
- **THEN** the login succeeds and is not blocked by the absence of a password

### Requirement: The service SHALL issue a single-use, time-bound set-password token

When a no-password account is created (or on request), the service MUST issue a
single-use, time-bound set-password token bound to that user. The token MUST be
rejected after it is consumed once or after it expires.

#### Scenario: Token is single-use

- **WHEN** a set-password token is used successfully and then presented again
- **THEN** the second use is rejected

#### Scenario: Token expires

- **WHEN** a set-password token is presented after its expiry
- **THEN** it is rejected

### Requirement: Users SHALL set their password via a self-service endpoint

The service MUST provide a self-service set-password endpoint that accepts either
a valid set-password token or an authenticated session belonging to a no-password
account, validates the new password (same strength rules as today, min 8 chars),
persists it, and marks the account as having a password set. After success,
password login MUST work normally.

#### Scenario: Set password with a valid token

- **WHEN** a user submits a new valid password with a valid set-password token
- **THEN** the password is set, the token is consumed, and password login
  subsequently succeeds

#### Scenario: Set password from an authenticated no-password session

- **WHEN** a signed-in no-password user submits a valid new password
- **THEN** the password is set and password login subsequently succeeds

#### Scenario: Weak password rejected

- **WHEN** a submitted password is shorter than the minimum length
- **THEN** the request is rejected with a validation error and no password is set

### Requirement: IAM GET endpoints SHALL require read permissions

The IAM tenant-scoped GET endpoints SHALL enforce read permissions:

- `GET /api/v1/iam/tenants/me/users` (list tenant users) MUST require `user.read`.
- `GET /api/v1/iam/tenants/me/permissions` MUST be callable by any authenticated
  tenant member (it is how the client learns its own permissions); it MUST NOT require
  a read permission.
- `GET /api/v1/iam/tenants/me/roles` (list roles) and `GET .../roles/{id}` MUST require
  `role.read`.

Callers without the required permission MUST receive HTTP 403 with code `FORBIDDEN`.
`tenant_id` MUST continue to be resolved from the JWT.

#### Scenario: Listing users without user.read is forbidden

- **WHEN** a caller without `user.read` calls `GET /tenants/me/users`
- **THEN** the response is HTTP 403

#### Scenario: Listing roles with role.read succeeds

- **WHEN** a caller holding `role.read` calls `GET /tenants/me/roles`
- **THEN** the response is HTTP 200 with the role list

### Requirement: IAM SHALL seed the grade.evaluation.manage permission

IAM MUST add `grade.evaluation.manage` to the fixed, seeded `permission`
vocabulary, describing the authority to create, update, and delete concrete
grading evaluations for a teaching assignment. The permission MUST be seeded
idempotently and MUST NOT be editable by tenants. The built-in roles
`tenant_admin`, `teacher`, and `homeroom_teacher` MUST be granted this permission
via `role_permission`, so their issued access tokens carry it in `perms`.

#### Scenario: The permission exists in the vocabulary

- **WHEN** the IAM permission seed has run
- **THEN** a permission with code `grade.evaluation.manage` exists and is not tenant-editable

#### Scenario: Built-in roles carry the permission

- **WHEN** a user holding the built-in `teacher`, `homeroom_teacher`, or `tenant_admin` role obtains a tenant-scoped access token
- **THEN** the token's `perms` includes `grade.evaluation.manage`

#### Scenario: Seed is idempotent

- **WHEN** the permission and role-permission seed migrations run more than once
- **THEN** no duplicate permission or role-permission rows are created

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

### Requirement: Avatar upload SHALL garbage-collect the previous object

When an IAM user uploads a new avatar, the service SHALL delete the previous
avatar object (at `avatar/{previous_media_id}`) from storage before the new
avatar becomes active. IAM uses a single `avatar_url` column (no
`media_asset` table), so the previous object is identified by parsing the
existing `avatar_url`. If no previous avatar exists, no deletion is
performed.

#### Scenario: Replacing an avatar removes the old object

- **WHEN** a user with an existing avatar uploads a new one
- **THEN** the previous avatar object is deleted from storage and the new
  object is stored at `avatar/{new_media_id}`

#### Scenario: First avatar upload deletes nothing

- **WHEN** a user with no avatar uploads one
- **THEN** no previous-object deletion occurs

### Requirement: Avatar deletion SHALL remove stored bytes

The `DELETE /api/v1/iam/me/avatar` endpoint SHALL delete the stored avatar
object at `avatar/{media_id}` and set `avatar_url` to NULL. This resolves
the prior behavior that only nulled the column and orphaned the bytes.
Deletion is idempotent.

#### Scenario: Deleting an avatar removes bytes and clears the column

- **WHEN** a user deletes their avatar
- **THEN** the avatar object is removed from storage and `avatar_url` is
  set to NULL

### Requirement: Credential rotation SHALL revoke all active sessions

`admin_reset_password`, the token-based `set_password`, and the session-based
`set_password_authenticated` MUST revoke **all** of the target user's refresh
tokens after persisting the new password hash, by calling the same
`revoke_all_for_user` mechanism used by `change_password`. This guarantees that
any refresh token minted before the credential change can no longer rotate into
a new access token. For the session-based set-password path, the caller's own
refresh token is also revoked, requiring re-authentication after the password is
set.

#### Scenario: Admin reset invalidates prior sessions

- **WHEN** an admin resets a user's password and that user holds a valid refresh
  token from before the reset
- **THEN** the next `POST /auth/refresh` with that refresh token is rejected as
  revoked, and no new access token is issued

#### Scenario: Self-service set-password invalidates the calling session

- **WHEN** a signed-in no-password user sets a password via the authenticated
  set-password path
- **THEN** all of that user's refresh tokens (including the one backing the
  current session) are revoked, and the client must re-authenticate to continue

#### Scenario: Token-based set-password invalidates prior sessions

- **WHEN** a user sets a password using a single-use set-password token and that
  user also holds a refresh token from a prior session
- **THEN** the prior refresh token is revoked and can no longer mint access
  tokens

### Requirement: Users SHALL be able to request a fresh set-password token

The service MUST provide `POST /api/v1/iam/auth/set-password/resend` to support
recovery for no-password accounts. The endpoint accepts either (a) an
authenticated identity/session request, resolving the caller directly, or (b) an
unauthenticated request carrying an account identifier (email or username). It
MUST look up the account; if the account has no password, it MUST revoke any
prior unconsumed set-password tokens for that user and issue a fresh single-use,
time-bound token (reusing `issue_set_password_token`). If the account already
has a password, or no account matches, the endpoint MUST return the same generic
success-like response to avoid account enumeration. The endpoint MUST be
rate-limited per identifier and per source address.

#### Scenario: No-password user requests and receives a fresh token

- **WHEN** a request identifies a no-password account (by session or by
  identifier)
- **THEN** any prior unconsumed set-password tokens for that user are revoked, a
  new single-use token is issued, and the response indicates success

#### Scenario: Account with a password does not receive a token

- **WHEN** a request identifies an account that already has a password set
- **THEN** no set-password token is issued, and the response is the same generic
  shape as a successful request (no enumeration leak)

#### Scenario: Unknown identifier does not leak existence

- **WHEN** a request carries an identifier that matches no account
- **THEN** the response is identical to the success shape and no token is issued

#### Scenario: Prior token is invalidated on resend

- **WHEN** a no-password user requests a resend and then attempts to use the
  previously-issued (now-superseded) set-password token
- **THEN** the superseded token is rejected as invalid or already used

