## ADDED Requirements

### Requirement: Academic Config service SHALL expose year-scoped academic structure under `/api/v1/academic-config`

The service MUST provide endpoints for academic years, curriculum versions,
subjects, grading policy, and class templates under the path prefix
`/api/v1/academic-config`, all following the success/error envelopes from
`13_engineering_standards/03_api_conventions.md`. Every resource MUST be
scoped to the tenant resolved from the JWT and MUST NOT read `tenant_id` from
the request body.

#### Scenario: Academic year creation is tenant-scoped

- **WHEN** a tenant admin POSTs `{ name, start_date, end_date }` to `/api/v1/academic-config/academic-years` with a valid access token
- **THEN** the response is HTTP 201 with `data: { academic_year_id, name, start_date, end_date, status: "Planning" }` and the row is owned by the tenant from the JWT

#### Scenario: Listing returns only the caller's tenant data

- **WHEN** a tenant admin GETs `/api/v1/academic-config/academic-years`
- **THEN** the response contains only academic years owned by the tenant resolved from the JWT and never another tenant's years

#### Scenario: Subject carries a passing grade validated on input

- **WHEN** a tenant admin POSTs a subject with `passing_grade` outside the allowed range to `/curriculum-versions/{id}/subjects`
- **THEN** the response is HTTP 400 with `{ "error": { "code": "VALIDATION_ERROR", "fields": { "passing_grade": ["..."] } } }`

### Requirement: Academic year status SHALL follow the documented lifecycle

The service MUST enforce the academic-year lifecycle from
`09_states/AkademiQ_State_Academic_Year_Lifecycle.md`
(`Planning → Configuration → Active → Locked → Finalizing → Closed → Archived`).
Illegal transitions MUST be rejected. A tenant MUST NOT have more than one
academic year in `Active` status at a time.

#### Scenario: Legal transition succeeds

- **WHEN** a tenant admin PATCHes `/academic-years/{id}/status` from `Configuration` to `Active`
- **THEN** the response is HTTP 200 and the year's status is `Active`

#### Scenario: Illegal transition is rejected

- **WHEN** a tenant admin PATCHes a year's status from `Planning` directly to `Closed`
- **THEN** the response is HTTP 409 `{ "error": { "code": "INVALID_STATE_TRANSITION" } }` and the status is unchanged

#### Scenario: Only one active year per tenant

- **WHEN** a tenant already has an `Active` academic year and transitions a second year to `Active`
- **THEN** the response is HTTP 409 `{ "error": { "code": "ACTIVE_YEAR_EXISTS" } }`

### Requirement: Academic year creation SHALL require an active subscription

The service MUST consume the `subscription.activated` event and maintain a
local projection of each tenant's subscription state. Creating an academic
year MUST be gated behind both the `academic_config` feature entitlement and
an active subscription.

#### Scenario: Tenant without active subscription cannot create a year

- **WHEN** a tenant whose subscription projection is absent or inactive POSTs to `/academic-years`
- **THEN** the response is HTTP 403 with code `SUBSCRIPTION_INACTIVE`

#### Scenario: Non-entitled tenant is blocked by the feature gate

- **WHEN** a tenant whose plan does not entitle `academic_config` POSTs to `/academic-years`
- **THEN** the response is HTTP 403 with code `FEATURE_NOT_AVAILABLE`

#### Scenario: After consuming subscription.activated the tenant can create a year

- **WHEN** the service has consumed `subscription.activated` for a tenant whose plan entitles `academic_config`
- **THEN** that tenant's POST to `/academic-years` succeeds with HTTP 201

### Requirement: Grading policy SHALL be a single upserted record per academic year

The service MUST expose `PUT /academic-years/{id}/grading-policy` accepting
`{ minimum_passing_score, grading_scale }`, storing exactly one policy per
academic year, and `GET` returning the current policy. `grading_scale` MUST be
validated against a fixed allowlist and `minimum_passing_score` MUST be within
`[0, 100]`.

#### Scenario: Upserting the policy twice keeps one row

- **WHEN** a tenant admin PUTs a grading policy for a year, then PUTs a different policy for the same year
- **THEN** `GET /academic-years/{id}/grading-policy` returns the latest values and there is exactly one policy row for that year

#### Scenario: Invalid grading scale is rejected

- **WHEN** a tenant admin PUTs a grading policy with a `grading_scale` not in the allowlist
- **THEN** the response is HTTP 400 with code `VALIDATION_ERROR` and a `grading_scale` field error

### Requirement: The service SHALL emit `academic_year.created`

On successful academic-year creation the service MUST enqueue an
`academic_year.created` event through the outbox using the envelope from
`13_engineering_standards/04_event_standards.md`, and the payload MUST be
documented under `docs/internal/11_integration_contracts/events/`.

#### Scenario: Event is published after year creation

- **WHEN** an academic year is created successfully
- **THEN** an `academic_year.created` event carrying `{ tenant_id, academic_year_id, name, start_date, end_date }` is published to RabbitMQ exactly once per creation in `event_id` order
