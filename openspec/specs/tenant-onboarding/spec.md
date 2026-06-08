# tenant-onboarding Specification

## Purpose

Outlines requirements for the tenant onboarding flow, specifying single-request registration logic, validation formatting, rabbitmq integration event contracts, immediate client login behavior, and tenant isolation restrictions.

## Requirements

### Requirement: Tenant onboarding SHALL be a single web-initiated flow that completes in one round trip

A new school SHALL be able to complete the registration form on the web
app, see either a successful redirect to the authenticated dashboard or a
field-level validation error, and never need to retry the form because of
partial state on the server.

#### Scenario: Happy path completes without manual intervention

- **WHEN** a new school submits the registration form with valid school name, plan id, admin email, admin password, and admin full name
- **THEN** the web app receives HTTP 201 from `/api/v1/billing/tenants/register`, stores the access and refresh tokens, and redirects the user to `/dashboard` authenticated as the new tenant admin

#### Scenario: Server-side failure leaves no orphaned state visible to the user

- **WHEN** the saga fails midway (IAM creates the user but Billing's subscription insert fails)
- **THEN** the user receives a single HTTP error response with a non-`VALIDATION_ERROR` code, can re-submit the same email after the janitor reaps the orphan, and never sees a "user already exists but tenant doesn't" state in the UI

### Requirement: Onboarding errors SHALL conform to the validation contract

When the user supplies invalid data, the response MUST follow
`13_engineering_standards/14_validation_contract.md`: HTTP 400 with body
`{ "error": { "code": "VALIDATION_ERROR", "fields": { ... } } }`. Field
keys MUST match the form field names so the web client can render errors
inline.

#### Scenario: Missing required field surfaces under that field

- **WHEN** the form submits with `admin_email` empty
- **THEN** the response body contains `error.fields.admin_email` with at least one human-readable message and no other fields are reported

#### Scenario: Multiple invalid fields each surface independently

- **WHEN** the form submits with `admin_password` shorter than the minimum and `plan_id` not matching any plan
- **THEN** `error.fields.admin_password` and `error.fields.plan_id` both appear with their own messages in a single response

### Requirement: Onboarding SHALL emit `tenant.registered` and `subscription.activated` events with stable payloads

Onboarding MUST publish `tenant.registered` and `subscription.activated`
events on every successful registration. Phase 2's Academic Configuration
service will subscribe to `subscription.activated` to gate academic year
creation, so the payload contract MUST be documented in
`docs/internal/11_integration_contracts/events/` before this change is
archived.

#### Scenario: `tenant.registered` payload is documented

- **WHEN** a contributor reads `docs/internal/11_integration_contracts/events/tenant.registered.md`
- **THEN** the file specifies `event_id`, `event_type = "tenant.registered"`, `occurred_at`, and a `payload` schema including at least `tenant_id`, `school_name`, and `created_by_user_id`

#### Scenario: `subscription.activated` payload is documented

- **WHEN** a contributor reads `docs/internal/11_integration_contracts/events/subscription.activated.md`
- **THEN** the file specifies `event_id`, `event_type = "subscription.activated"`, `occurred_at`, and a `payload` schema including at least `tenant_id`, `subscription_id`, `plan_id`, `start_date`, `end_date`, and `payment_method`

#### Scenario: Events fire in the documented order

- **WHEN** a tenant registers successfully
- **THEN** `tenant.registered` is published before `subscription.activated`, allowing future consumers to assume the tenant exists when they handle the subscription event

### Requirement: The web client SHALL log the new admin in immediately after registration

The registration response MUST include access and refresh tokens. The
web client MUST persist them and use them on the next request without
requiring a separate login submission.

#### Scenario: Tokens from registration are usable

- **WHEN** the web client receives a 201 from registration and immediately calls `GET /api/v1/iam/me` with the access token from the response
- **THEN** the call returns HTTP 200 with the new admin's profile

### Requirement: Onboarding SHALL never accept a `tenant_id` from the client

The registration handler MUST allocate `tenant_id` server-side. Any
`tenant_id` sent in the request body MUST be ignored. Subsequent
authenticated requests MUST resolve `tenant_id` from the JWT only.

#### Scenario: Client-supplied tenant_id is rejected during registration

- **WHEN** a client submits `POST /tenants/register` with a `tenant_id` field in the body
- **THEN** the field is ignored, the server-allocated `tenant_id` is returned in the response, and the e2e test asserts the two values differ when the client supplied a UUID

#### Scenario: Client-supplied tenant_id is ignored after authentication

- **WHEN** a tenant admin PATCHes `/tenants/me/modules` with a different `tenant_id` field in the body
- **THEN** the handler updates the tenant identified by the JWT only, and the body field has no effect
