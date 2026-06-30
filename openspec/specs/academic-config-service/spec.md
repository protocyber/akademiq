## Purpose

Define the academic configuration service contract for tenant-scoped academic years, curriculum versions, subjects, grading policies, class templates, lifecycle rules, subscription gating, and related events.
## Requirements
### Requirement: Academic Config service SHALL expose year-scoped academic structure under `/api/v1/academic-config`

The service MUST provide endpoints for academic years, curriculum versions,
subjects, grading policy, and class templates under the path prefix
`/api/v1/academic-config`, all following the success/error envelopes from
`13_engineering_standards/03_api_conventions.md`. Every resource MUST be
scoped to the tenant resolved from the JWT and MUST NOT read `tenant_id` from
the request body.

List endpoints for academic years, curriculum versions, subjects, and class
templates MUST accept `search`, `sort`, `page`, and `page_size` query
parameters and MUST return a `{ data, meta: { page, page_size, total } }`
envelope. `sort` MUST be validated against a per-resource whitelist and an
unknown value MUST be rejected with HTTP 400 `INVALID_SORT`. `search` MUST match
the resource's primary name field (and code where present) case-insensitively.

#### Scenario: Academic year creation is tenant-scoped

- **WHEN** a tenant admin POSTs `{ name, start_date, end_date }` to `/api/v1/academic-config/academic-years` with a valid access token
- **THEN** the response is HTTP 201 with `data: { academic_year_id, name, start_date, end_date, status: "Planning" }` and the row is owned by the tenant from the JWT

#### Scenario: Listing returns only the caller's tenant data

- **WHEN** a tenant admin GETs `/api/v1/academic-config/academic-years`
- **THEN** the response contains only academic years owned by the tenant resolved from the JWT and never another tenant's years

#### Scenario: List returns a paginated envelope

- **WHEN** a tenant admin GETs `/api/v1/academic-config/academic-years?search=2026&sort=-name&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-config list endpoint with `sort=` set to a value outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

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

### Requirement: Academic years, curriculum versions, subjects, and class templates SHALL support edit and delete

The service MUST expose update (PATCH) and delete (single + bulk) endpoints for
academic years, curriculum versions, subjects, and class templates, all
tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing: it MUST
pre-validate every id and, on the first violation, reject the entire request
with no deletions.

- Academic year: `DELETE /academic-years/{id}` MUST be rejected with HTTP 409
  `ACTIVE_YEAR_IMMUTABLE` when the year is `Active`, and HTTP 409 `YEAR_IN_USE`
  when homerooms or teaching assignments reference it. The reference check uses
  a local usage projection built from the academic-ops `homeroom.created` and
  `teacher.assigned` events (see "Cross-service usage projection" below).
- Curriculum version: `PATCH /curriculum-versions/{id}` MUST update name and
  description; `DELETE` MUST be rejected with HTTP 409 `CURRICULUM_IN_USE` when
  the version still has subjects.
- Subject: `PATCH /subjects/{id}` MUST update name, code, and passing grade;
  `DELETE` MUST be rejected with HTTP 409 `SUBJECT_IN_USE` when a teaching
  assignment references it (same usage projection).
- Class template: `PATCH /class-templates/{id}` MUST update grade level and
  default capacity; `DELETE` MUST always succeed (templates are advisory).

#### Cross-service usage projection

The `YEAR_IN_USE` and `SUBJECT_IN_USE` guards depend on `homeroom` and
`teaching_assignment` data owned by the academic-ops service in a separate
database. Academic-config MUST consume the academic-ops `homeroom.created` and
`teacher.assigned` events into local `year_usage_ref` / `subject_usage_ref`
projection tables (idempotent on the source id) and the delete guards MUST
query those projections. Academic-ops MUST emit `homeroom.created`
(`tenant_id`, `homeroom_id`, `academic_year_id`) from its create-homeroom
command and MUST include `assignment_id` in the `teacher.assigned` payload so
each projection row keys idempotently.

#### Scenario: Editing a curriculum version updates it in place

- **WHEN** a tenant admin PATCHes `/curriculum-versions/{id}` with a new `{ name, description }`
- **THEN** the response is HTTP 200 with the updated version and a subsequent list reflects the new values

#### Scenario: Deleting an active academic year is rejected

- **WHEN** a tenant admin DELETEs an academic year whose status is `Active`
- **THEN** the response is HTTP 409 `ACTIVE_YEAR_IMMUTABLE` and the year is unchanged

#### Scenario: Deleting a curriculum version that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a curriculum version that has one or more subjects
- **THEN** the response is HTTP 409 `CURRICULUM_IN_USE` and the version and its subjects are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of subject ids where one is referenced by a teaching assignment
- **THEN** the response rejects the whole request with HTTP 409 `SUBJECT_IN_USE` and none of the subjects in the set are deleted

#### Scenario: Bulk delete of all-deletable ids succeeds

- **WHEN** a tenant admin bulk-deletes class templates that all exist and belong to the tenant
- **THEN** the response is HTTP 200 and every template in the set is deleted in one transaction

### Requirement: Academic Config GET endpoints SHALL require academic.config.read

The tenant-scoped GET endpoints of the Academic Config service MUST require
`academic.config.read` in addition to the existing feature entitlement. This covers
academic years (list/get), curriculum versions (list), subjects (list), grading policy
(get), and class templates (list). Callers without the permission MUST receive HTTP 403
with code `FORBIDDEN`.

#### Scenario: Listing academic years without the read permission

- **WHEN** a caller without `academic.config.read` calls `GET /api/v1/academic-config/academic-years`
- **THEN** the response is HTTP 403

#### Scenario: Reading with the permission succeeds

- **WHEN** a caller holding `academic.config.read` calls the same endpoint
- **THEN** the response is HTTP 200 with the year list

### Requirement: The service SHALL provide a PATCH endpoint to update academic year identity fields

academic-config MUST expose `PATCH /api/v1/academic-config/academic-years/:id`
accepting `{ name, start_date, end_date }`. The handler MUST preserve the
existing `status` field (never assign it). The handler MUST reject updates to
an Archived year with `YEAR_NOT_EDITABLE`. The handler MUST validate date
ordering and overlap rules within the tenant, consistent with create.

#### Scenario: Update academic year name and dates

- **WHEN** a tenant admin sends `PATCH /academic-years/:id` with valid
  `{ name, start_date, end_date }` for a non-Archived year
- **THEN** the year is updated and the response returns the full year object
  with its `status` unchanged

#### Scenario: Update academic year preserves status

- **WHEN** a PATCH is sent for an Active year
- **THEN** the response `status` field equals `"Active"` (the PATCH never
  transitions status)

#### Scenario: Archived year is not editable

- **WHEN** a PATCH is sent for an Archived year
- **THEN** the response is HTTP 409/422 with code `YEAR_NOT_EDITABLE`

### Requirement: Status transitions SHALL require a reason only for backward and archived transitions

The `transition_year_status` and `transition_term_status` handlers MUST accept
`reason` as an optional field (`Option<String>`). For forward transitions
(`Draft→Active`, `Active→Closed`, `Closed→Archived`), `reason` MAY be absent
or present; if present, it MUST be ≥ 10 characters. For backward transitions
(`Active→Draft`, `Closed→Active`, `Closed→Draft`) and archived transitions
(`→Archived`), `reason` MUST be present and ≥ 10 characters, else the handler
returns `VALIDATION_ERROR`.

The transition log tables (`academic_year_status_transition`,
`academic_term_status_transition`) MUST store `reason` as nullable; a null
reason is valid only for forward transitions.

#### Scenario: Forward transition without reason succeeds

- **WHEN** a transition from `Draft` to `Active` is submitted with no `reason`
  field
- **THEN** the transition succeeds and the log row stores `reason = NULL`

#### Scenario: Forward transition with a reason succeeds

- **WHEN** a transition from `Draft` to `Active` is submitted with
  `reason = "Aktivasi tahun ajaran baru"` (≥ 10 chars)
- **THEN** the transition succeeds and the log row stores the provided reason

#### Scenario: Backward transition without reason fails

- **WHEN** a transition from `Active` to `Draft` is submitted with no `reason`
- **THEN** the response is `VALIDATION_ERROR` with field `reason` indicating
  it is required for backward transitions

#### Scenario: Archived transition without reason fails

- **WHEN** a transition to `Archived` is submitted with no `reason`
- **THEN** the response is `VALIDATION_ERROR` with field `reason` indicating
  it is required for archived transitions

