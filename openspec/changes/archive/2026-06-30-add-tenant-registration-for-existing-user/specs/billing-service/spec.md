## ADDED Requirements

### Requirement: The service SHALL register a tenant for an existing authenticated user

billing MUST expose `POST /api/v1/billing/tenants/register-for-user` that
accepts an identity bearer token and `{ school_name, plan_id }`. The handler
MUST extract the `user_id` from the token (not from the request body),
validate the plan, create the tenant + subscription (Active), emit
`tenant.registered` and `subscription.activated` outbox events, and call IAM
to attach a `tenant_admin` membership to the existing `user_id`. The handler
MUST NOT create a new IAM user.

#### Scenario: Existing user registers a new tenant

- **WHEN** an authenticated tenant-less user sends
  `POST /register-for-user` with valid `{ school_name, plan_id }` and a
  valid identity bearer token
- **THEN** a new tenant and Active subscription are created, a
  `tenant_admin` membership is attached to the caller's `user_id`, and the
  response returns `{ tenant_id, user_id, subscription_id }`

#### Scenario: No identity token

- **WHEN** the request has no `Authorization` header
- **THEN** the response is HTTP 401

#### Scenario: IAM membership attach fails

- **WHEN** the IAM `attach_membership` call fails after the tenant is created
- **THEN** the handler MUST compensate by deleting (or marking failed) the
  tenant and subscription, and return an error

## MODIFIED Requirements

### Requirement: The IAM client SHALL support attaching a membership to an existing user

The `iam_client` in billing-service MUST expose an
`attach_membership(user_id, tenant_id, role_code)` method that calls the IAM
internal endpoint. This is used by `register_tenant_for_user` as a
replacement for `create_user` when the admin already exists.

#### Scenario: attach_membership succeeds

- **WHEN** billing calls `attach_membership(user_id, tenant_id,
  "tenant_admin")` with a valid service token
- **THEN** IAM inserts a `user_tenant_role` row and billing receives a
  success response
