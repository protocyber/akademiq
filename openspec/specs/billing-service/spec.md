# billing-service Specification

## Purpose

Defines requirements for the billing-service (Tenant & Subscription Service), including plan management, tenant registration, module overrides, event emission, subscription lifecycles, and seed data.

## Requirements

### Requirement: Billing service SHALL expose tenant and plan endpoints under `/api/v1/billing`

The service MUST provide `POST /tenants/register`, `GET /plans`,
`GET /tenants/me`, and `PATCH /tenants/me/modules` under the path prefix
`/api/v1/billing`. All endpoints MUST follow the success and error
envelopes from `13_engineering_standards/03_api_conventions.md`.

#### Scenario: Plan catalog is publicly accessible

- **WHEN** an unauthenticated client GETs `/api/v1/billing/plans`
- **THEN** the response is HTTP 200 with `data: [{ plan_id, name, price_monthly, price_yearly, features: [{ feature_code, enabled }] }]` for every active plan

#### Scenario: Tenant profile is tenant-scoped

- **WHEN** a tenant admin GETs `/api/v1/billing/tenants/me` with a valid access token
- **THEN** the response is HTTP 200 with `data: { tenant_id, school_name, status, current_plan: { plan_id, name }, modules: [{ feature_code, enabled }] }` for the tenant resolved from the JWT, and never another tenant's data

### Requirement: `POST /tenants/register` SHALL be a public endpoint that creates tenant, subscription, and admin user

The handler MUST accept `{ school_name, plan_id, admin_email,
admin_password, admin_full_name }` without authentication. It MUST create
the tenant row, call IAM's internal user-creation endpoint to create the
admin user with the `tenant_admin` role, then create the subscription, all
within the same logical saga.

#### Scenario: Successful registration returns tenant id and access token

- **WHEN** a client POSTs valid registration data to `/api/v1/billing/tenants/register`
- **THEN** the response is HTTP 201 with `data: { tenant_id, user_id, access_token, refresh_token, expires_in }` so the web client can immediately enter the authenticated app

#### Scenario: Validation failure is reported per-field

- **WHEN** a client POSTs registration data missing `admin_password` or with an invalid `plan_id`
- **THEN** the response is HTTP 400 with body matching the validation contract: `{ "error": { "code": "VALIDATION_ERROR", "fields": { "admin_password": ["..."], "plan_id": ["..."] } } }`

#### Scenario: IAM user creation failure rolls back the tenant row

- **WHEN** the IAM internal call returns 409 `EMAIL_ALREADY_EXISTS` after the tenant row has been written
- **THEN** the tenant row is removed (or never committed), no subscription exists, and the response is HTTP 409 `{ "error": { "code": "EMAIL_ALREADY_EXISTS", "message": "..." } }`

#### Scenario: Saga survives Billing crash between IAM call and subscription insert

- **WHEN** Billing crashes after IAM returns 201 but before `subscription` is inserted, and the janitor runs >5 minutes later
- **THEN** the janitor calls `DELETE /api/v1/iam/internal/users/{id}` to remove the orphaned IAM user, the partial tenant row is removed, and the next registration attempt with the same email succeeds

### Requirement: Plans SHALL define feature entitlements via `plan_feature` rows

Each plan MUST have a row in `plan_feature` for every feature code in the
catalog with `enabled: true | false`. Adding a new feature SHALL require a
migration that inserts a row for every existing plan; no plan may have an
implicit default.

#### Scenario: Feature matrix is complete after seed

- **WHEN** `make seed` runs against an empty `billing_db`
- **THEN** for every `(plan_id, feature_code)` combination there is exactly one row in `plan_feature`

#### Scenario: New feature migration covers all existing plans

- **WHEN** a migration adds a new feature code
- **THEN** the same migration inserts a `plan_feature` row for that code on every existing plan or the migration fails

### Requirement: Tenant module overrides SHALL respect plan entitlements

`PATCH /api/v1/billing/tenants/me/modules` MUST accept `{ feature_code,
enabled }` and update `tenant_module` only if the tenant's current plan
has `plan_feature.enabled = true` for that code. Toggling a module that
the plan does not entitle MUST return HTTP 403 `FEATURE_NOT_AVAILABLE`
per `13_engineering_standards/15_feature_entitlement.md`.

#### Scenario: Entitled module is toggled off and on

- **WHEN** a tenant admin on the Premium plan PATCHes `{ feature_code: "attendance", enabled: false }` and then PATCHes the same with `enabled: true`
- **THEN** both calls return HTTP 200 and `tenant_module.enabled` reflects the latest write

#### Scenario: Non-entitled module is rejected

- **WHEN** a tenant admin on the Starter plan PATCHes `{ feature_code: "promotion", enabled: true }` and Starter does not entitle `promotion`
- **THEN** the response is HTTP 403 `{ "error": { "code": "FEATURE_NOT_AVAILABLE", "message": "..." } }` and no row is written

### Requirement: Billing SHALL emit `tenant.registered` and `subscription.activated` events on successful registration

After the registration saga commits, Billing MUST publish two events to
RabbitMQ in the standard envelope from `13_engineering_standards/04_event_standards.md`.
The events MUST be published in the same transaction or via a transactional
outbox so a successful HTTP response implies the events will eventually
fire.

#### Scenario: Both events fire after registration

- **WHEN** a tenant successfully registers
- **THEN** the RabbitMQ exchange has received exactly one `tenant.registered` and one `subscription.activated` event referencing the new `tenant_id` and `subscription_id`

#### Scenario: Event envelope matches the standard

- **WHEN** a consumer reads either event
- **THEN** the message body has top-level fields `event_id` (UUID), `event_type` (e.g. `tenant.registered`), `occurred_at` (RFC3339), and `payload` (object with at least `tenant_id`)

### Requirement: Subscriptions SHALL track lifecycle status

The `subscription` table MUST include a `status` column with values
`active`, `expired`, `cancelled`. New subscriptions are `active`. A
nightly job (or query-time check) SHALL transition expired subscriptions
to `expired` so feature checks reject them.

#### Scenario: Active subscription gates feature access

- **WHEN** a tenant's subscription is `active` and the requested feature is entitled
- **THEN** middleware allows the request through

#### Scenario: Expired subscription blocks feature access

- **WHEN** a tenant's subscription has `status = expired`
- **THEN** any feature-gated endpoint returns HTTP 403 `SUBSCRIPTION_EXPIRED` regardless of the plan's feature matrix

### Requirement: Billing SHALL ship seed data for three plans

The seed binary MUST insert plans `Starter`, `Standard`, and `Premium`
with the following feature matrix: Starter = `academic_config`,
`academic_ops`; Standard = Starter + `attendance` + `grading`;
Premium = Standard + `promotion` + `notification` + `file`. The matrix
SHALL also be encoded in `features.toml` to keep the seed and the
documentation aligned.

#### Scenario: Seed produces the three plans

- **WHEN** `make seed` runs against an empty `billing_db`
- **THEN** the `plan` table contains exactly three rows with names `Starter`, `Standard`, `Premium` and `plan_feature` rows match the documented matrix
