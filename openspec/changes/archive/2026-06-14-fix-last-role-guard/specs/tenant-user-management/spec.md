## MODIFIED Requirements

### Requirement: Tenant admins SHALL assign one or more roles per user

Role assignment MUST manage a set of roles per user. The service MUST provide
add and remove operations (e.g. `POST /tenants/me/users/{id}/roles/{roleId}` and
`DELETE /tenants/me/users/{id}/roles/{roleId}`), gated on the `user.role.assign`
permission. The assignable set MUST include the tenant's built-in assignable
roles and its custom roles. Removing a role MUST be refused when it would leave
the user with zero roles in the tenant, because tenant membership is expressed
solely through `user_tenant_role` rows and dropping the last role would silently
un-enroll the user. Role changes MUST NOT require the user to log out; updated
roles MUST be reflected the next time an access token is issued via
refresh-token rotation, and MUST emit `tenant_user.role_changed`.

#### Scenario: Admin adds a role to a user

- **WHEN** an admin with `user.role.assign` adds a role to a user
- **THEN** the user holds that role in addition to any existing roles, and HTTP
  204 is returned

#### Scenario: Admin removes one of several roles

- **WHEN** an admin removes one role from a user holding multiple roles
- **THEN** the user retains the remaining roles

#### Scenario: Removing a user's last role is refused

- **WHEN** an admin removes the only role a user holds in the tenant
- **THEN** the response is HTTP 409 `LAST_ROLE`, the role is retained, and the
  user remains a member of the tenant

#### Scenario: Non-privileged caller cannot assign roles

- **WHEN** a caller without `user.role.assign` attempts to add or remove a role
- **THEN** the response is `403`

#### Scenario: New role appears after token refresh

- **WHEN** an admin changes a user's role set and that user subsequently refreshes their access token
- **THEN** the newly issued access token carries the updated roles and a `tenant_user.role_changed` event was published
</content>
