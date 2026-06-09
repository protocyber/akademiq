## ADDED Requirements

### Requirement: Tenant admins SHALL invite tenant-scoped users by email and role

The service MUST provide `POST /api/v1/iam/tenants/me/invitations` restricted
to `tenant_admin`, accepting an email and a role from the assignable set
(`teacher`, `homeroom_teacher`, `principal`, `parent`, `student`). It MUST
store only a hash of the activation token and emit `tenant_user.invited`.

#### Scenario: Admin invites a teacher

- **WHEN** a tenant admin POSTs `{ email, role: "teacher" }` to `/tenants/me/invitations`
- **THEN** the response is HTTP 201 with a pending invitation and an activation link, and a `tenant_user.invited` event is published

#### Scenario: Non-admin cannot invite

- **WHEN** a user without the `tenant_admin` role POSTs to `/tenants/me/invitations`
- **THEN** the response is HTTP 403

### Requirement: Invitation tokens SHALL be single-use and time-bound

Accepting an invitation MUST create the user and `user_tenant_role` and mark
the invitation accepted within one transaction. A token MUST NOT be redeemable
more than once, MUST be rejected after expiry, and MUST be rejected if revoked.

#### Scenario: Successful acceptance creates an authenticated user

- **WHEN** an invitee POSTs `{ token, password, full_name }` to `/invitations/accept` with a valid, unexpired token
- **THEN** the response is HTTP 201 with access + refresh tokens, the user has the invited role in the tenant, and a `tenant_user.activated` event is published

#### Scenario: Reused token is rejected

- **WHEN** an already-accepted invitation token is submitted again
- **THEN** the response is HTTP 409 `INVITATION_ALREADY_USED` and no new user is created

#### Scenario: Expired token is rejected

- **WHEN** a token is submitted after its `expires_at`
- **THEN** the response is HTTP 410 `INVITATION_EXPIRED`

### Requirement: The service SHALL seed a `principal` role

IAM MUST seed a `principal` role with a stable `role.code` matching a
`ROLE_PRINCIPAL` constant in `common-auth`, so the report-card approval chain
has a final approver.

#### Scenario: Principal role exists and is assignable

- **WHEN** a tenant admin invites a user with role `principal`
- **THEN** the invitation succeeds and, after acceptance, the user's access token carries the `principal` role

### Requirement: Role changes SHALL take effect on the next access token

Changing a tenant user's role MUST NOT require the user to log out. The new
role MUST be reflected the next time an access token is issued via refresh-token
rotation, and MUST emit `tenant_user.role_changed`.

#### Scenario: New role appears after token refresh

- **WHEN** an admin changes a user's role and that user subsequently refreshes their access token
- **THEN** the newly issued access token carries the new role and a `tenant_user.role_changed` event was published

### Requirement: Admins SHALL disable and re-enable tenant accounts

The service MUST allow a tenant admin to disable an account (blocking login)
and re-enable it, emitting `tenant_user.disabled` on disable.

#### Scenario: Disabled account cannot log in

- **WHEN** an admin disables a user and that user attempts to log in
- **THEN** the login is rejected and a `tenant_user.disabled` event was published

#### Scenario: Re-enabled account can log in

- **WHEN** an admin re-enables a previously disabled user
- **THEN** that user can log in again
