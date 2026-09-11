## Purpose

Define the academic configuration service contract for tenant-scoped academic years, curriculum versions, subjects, grading policies, class templates, lifecycle rules, subscription gating, and related events.
## Requirements
### Requirement: Academic Config service SHALL expose year-scoped academic structure under `/api/v1/academic-config`

The service MUST provide endpoints for academic years, curriculum versions,
subject groups, subjects, grading policy, and class templates under the path
prefix `/api/v1/academic-config`, all following the success/error envelopes from
`13_engineering_standards/03_api_conventions.md`. Every resource MUST be
scoped to the tenant resolved from the JWT and MUST NOT read `tenant_id` from
the request body.

List endpoints for academic years, curriculum versions, subject groups,
subjects, and class templates MUST accept `search`, `sort`, `page`, and
`page_size` query parameters and MUST return a `{ data, meta: { page, page_size, total } }`
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

The service MUST enforce a 4-status academic-year lifecycle:
`Draft → Active → Closed → Archived`. Transitions between `Draft`, `Active`,
and `Closed` MUST be allowed in both directions (undo). Transitions out of
`Archived` MUST be rejected. `Draft → Closed`, `Draft → Archived`, and
`Active → Archived` skip transitions MUST be rejected — a year MUST pass
through `Closed` before it can be `Archived`. A no-op transition (requesting
the year's current status) MUST be rejected.

A tenant MUST NOT have more than one academic year in `Active` status at a
time; this invariant MUST hold across undo paths (e.g. transitioning a second
year to `Active` is rejected even if another year was previously moved out of
`Active`).

Every transition request MUST include a non-empty `reason` string of at least
10 characters (after trimming). The service MUST persist the `reason`,
`previous_status`, `new_status`, actor, and timestamp for each transition. The
`reason` MUST be included in the emitted `academic_year.status_changed` event
payload.

#### Scenario: Forward transition succeeds

- **WHEN** a tenant admin PATCHes `/academic-years/{id}/status` with `{ status: "Active", reason: "Tahun ajaran dimulai hari ini" }` from `Draft`
- **THEN** the response is HTTP 200, the year's status is `Active`, and a transition record with the reason is persisted

#### Scenario: Backward transition (undo) succeeds

- **WHEN** a tenant admin PATCHes a year's status from `Closed` to `Active` with a valid `reason`
- **THEN** the response is HTTP 200 and the year's status is `Active`

#### Scenario: Transition out of Archived is rejected

- **WHEN** a tenant admin PATCHes an `Archived` year's status to any other value
- **THEN** the response is HTTP 409 `{ "error": { "code": "INVALID_STATE_TRANSITION" } }` and the status is unchanged

#### Scenario: Skip transition to Archived is rejected

- **WHEN** a tenant admin PATCHes an `Active` year's status directly to `Archived`
- **THEN** the response is HTTP 409 `{ "error": { "code": "INVALID_STATE_TRANSITION" } }` and the status is unchanged

#### Scenario: Missing or too-short reason is rejected

- **WHEN** a tenant admin PATCHes a year's status with `{ status: "Active" }` (no `reason`) or with a `reason` shorter than 10 characters
- **THEN** the response is HTTP 400 `{ "error": { "code": "VALIDATION_ERROR", "fields": { "reason": ["..."] } } }` and no transition occurs

#### Scenario: Only one active year per tenant

- **WHEN** a tenant already has an `Active` academic year and transitions a second year to `Active`
- **THEN** the response is HTTP 409 `{ "error": { "code": "ACTIVE_YEAR_EXISTS" } }`

#### Scenario: Transition event carries the reason

- **WHEN** a transition succeeds
- **THEN** an `academic_year.status_changed` event is published with a payload that includes `previous_status`, `status`, and `reason`

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
academic years, curriculum versions, subject groups, subjects, and class
templates, all tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing:
it MUST pre-validate every id and, on the first violation, reject the entire
request with no deletions.

- Academic year: `DELETE /academic-years/{id}` MUST be rejected with HTTP 409
  `ACTIVE_YEAR_IMMUTABLE` when the year is `Active`, and HTTP 409 `YEAR_IN_USE`
  when homerooms or teaching assignments reference it. The reference check uses
  a local usage projection built from the academic-ops `homeroom.created` and
  `teacher.assigned` events (see "Cross-service usage projection" below).
- Curriculum version: `PATCH /curriculum-versions/{id}` MUST update name and
  description; `DELETE` MUST be rejected with HTTP 409 `CURRICULUM_IN_USE` when
  the version still has subjects.
- Subject group: `PATCH /subject-groups/{id}` MUST update name, code, and
  position; `DELETE` MUST be rejected with HTTP 409 `SUBJECT_GROUP_IN_USE` when
  the group still has subjects.
- Subject: `PATCH /subjects/{id}` MUST update name, code, passing grade, and
  `subject_group_id`; `DELETE` MUST be rejected with HTTP 409 `SUBJECT_IN_USE`
  when a teaching assignment references it (same usage projection).
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
each projection row keys idempotently. The `SUBJECT_GROUP_IN_USE` guard uses a
direct in-database subject count, not a projection.

#### Scenario: Editing a curriculum version updates it in place

- **WHEN** a tenant admin PATCHes `/curriculum-versions/{id}` with a new `{ name, description }`
- **THEN** the response is HTTP 200 with the updated version and a subsequent list reflects the new values

#### Scenario: Deleting an active academic year is rejected

- **WHEN** a tenant admin DELETEs an academic year whose status is `Active`
- **THEN** the response is HTTP 409 `ACTIVE_YEAR_IMMUTABLE` and the year is unchanged

#### Scenario: Deleting a curriculum version that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a curriculum version that has one or more subjects
- **THEN** the response is HTTP 409 `CURRICULUM_IN_USE` and the version and its subjects are unchanged

#### Scenario: Deleting a subject group that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a subject group that has one or more subjects
- **THEN** the response is HTTP 409 `SUBJECT_GROUP_IN_USE` and the group is unchanged

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

### Requirement: Academic year creation SHALL emit status `Draft`

On creation the service MUST set the academic year's status to `Draft`. The
`academic_year.created` event payload is otherwise unchanged.

#### Scenario: New year starts in Draft

- **WHEN** a tenant admin creates a new academic year
- **THEN** the response is HTTP 201 with `data: { ..., status: "Draft" }`

### Requirement: Status transitions SHALL be persisted to a transition log

The service MUST record every successful status transition in an
`academic_year_status_transition` log with at minimum: `transition_id`,
`academic_year_id`, `tenant_id`, `from_status`, `to_status`, `reason`,
`actor_user_id`, and `occurred_at`. This log is the interim audit store; when
the `tenant-audit-log` capability lands, the write target MUST move there
without changing the transition command contract.

#### Scenario: Undo transition is logged

- **WHEN** a tenant admin transitions a year from `Closed` back to `Active` with reason "Salah klik close"
- **THEN** a row exists in `academic_year_status_transition` with `from_status = 'Closed'`, `to_status = 'Active'`, and the given reason

### Requirement: An academic year SHALL own one or more academic terms

The service MUST store an `academic_term` entity for each subdivision of an
academic year. An academic term MUST carry: `term_id`, `academic_year_id`
(referencing an existing academic year, cascade-deleted with it), `tenant_id`,
`name`, `start_date`, `end_date`, `status`, and timestamps. The combination
`(tenant_id, academic_year_id, name)` MUST be unique. A term's `status` MUST be
one of `Draft`, `Active`, `Closed`, `Archived` (default `Draft`). A tenant's
academic year MUST NOT have more than one term in `Active` status at a time.

A term's `start_date` MUST be on or after its academic year's `start_date`, and
its `end_date` MUST be on or before its academic year's `end_date`. Two terms
within the same academic year MUST NOT have overlapping date ranges (a gap
between consecutive terms is allowed).

#### Scenario: Create a term within the parent year

- **WHEN** a tenant admin POSTs `/academic-years/{year_id}/terms` with
  `{ name: "Semester 2", start_date: <within year>, end_date: <within year> }`
- **THEN** the response is HTTP 201 with `data: { ..., status: "Draft" }` and an
  `academic_term.created` event is published

#### Scenario: Term dates must fall within the year

- **WHEN** a tenant admin creates a term whose `start_date` or `end_date` falls
  outside the parent academic year's date range
- **THEN** the response is HTTP 400
  `{ "error": { "code": "VALIDATION_ERROR", "fields": { "start_date|end_date": ["..."] } } }`

#### Scenario: Overlapping terms are rejected

- **WHEN** a tenant admin creates a term whose date range overlaps an existing
  term in the same academic year
- **THEN** the response is HTTP 409 `{ "error": { "code": "TERM_OVERLAP" } }`

#### Scenario: Duplicate term name within a year is rejected

- **WHEN** a tenant admin creates a term whose `name` already exists in the same
  academic year
- **THEN** the response is HTTP 409 `{ "error": { "code": "TERM_NAME_EXISTS" } }`

#### Scenario: Only one active term per year

- **WHEN** a tenant already has an `Active` term for an academic year and
  transitions a second term in that year to `Active`
- **THEN** the response is HTTP 409 `{ "error": { "code": "ACTIVE_TERM_EXISTS" } }`

### Requirement: Creating an academic year SHALL seed a default term

On creation of an academic year the service MUST, in the same transaction,
create exactly one child term with `name` equal to the backend default
(`"Semester 1"`), `start_date`/`end_date` copied from the new year, and
`status` `Draft`. An `academic_term.created` event MUST be enqueued in the same
transactional outbox as the `academic_year.created` event.

#### Scenario: New academic year has one default term

- **WHEN** a tenant admin creates a new academic year
- **THEN** the response is HTTP 201 for the year, and a subsequent
  `GET /academic-years/{id}/terms` returns exactly one term with
  `name: "Semester 1"` and `status: "Draft"`

### Requirement: Academic term status SHALL follow a 4-state lifecycle

The service MUST enforce a term lifecycle `Draft ⇄ Active ⇄ Closed → Archived`
with the same transition matrix as the academic year: `Draft↔Active`,
`Active↔Closed`, `Closed→Archived`; skips (`Draft→Closed`, `Draft→Archived`,
`Active→Archived`) and any transition out of `Archived` MUST be rejected.
Every transition MUST include a non-empty `reason` of at least 10 characters
that is persisted (interim local store) and included in the
`academic_term.status_changed` payload.

#### Scenario: Forward term transition succeeds

- **WHEN** a tenant admin PATCHes `/academic-terms/{id}/status` with
  `{ status: "Active", reason: "Semester dimulai" }` from `Draft`
- **THEN** the response is HTTP 200, the term's status is `Active`, and a
  transition record with the reason is persisted

#### Scenario: Term skip transition is rejected

- **WHEN** a tenant admin PATCHes a `Draft` term directly to `Closed`
- **THEN** the response is HTTP 409
  `{ "error": { "code": "INVALID_STATE_TRANSITION" } }`

### Requirement: Year closure SHALL require all terms closed

Transitioning an academic year to `Closed` MUST be rejected while any of its
terms is in `Active` status. Transitioning to `Active` has no term-status
requirement. Transitioning to `Archived` is only reachable via `Closed` (year
matrix) and therefore implies all terms were closed first.

#### Scenario: Closing a year with an active term is rejected

- **WHEN** a tenant admin PATCHes a year to `Closed` while one of its terms is
  `Active`
- **THEN** the response is HTTP 409 `{ "error": { "code": "TERM_STILL_ACTIVE" } }`
  and the year status is unchanged

#### Scenario: Activating a year with only draft terms succeeds

- **WHEN** a tenant admin PATCHes a year to `Active` while all its terms are
  `Draft`
- **THEN** the response is HTTP 200 and the year's status is `Active`

### Requirement: Academic term events SHALL be published

The service MUST publish `academic_term.created` (with `tenant_id`, `term_id`,
`academic_year_id`, `name`, `start_date`, `end_date`, `status`) on creation and
`academic_term.status_changed` (with `tenant_id`, `term_id`, `academic_year_id`,
`previous_status`, `status`, `reason`) on every successful transition. Events
MUST be emitted via the transactional outbox in the same transaction as the
write they describe.

#### Scenario: Created event is published atomically

- **WHEN** a term is created
- **THEN** an `academic_term.created` event is committed in the same database
  transaction as the term row

### Requirement: Academic year creation emits status `Draft`

On creation the service MUST set the academic year's status to `Draft` and MUST
also create a default child term in the same transaction (see the added
requirement above). The `academic_year.created` event payload is otherwise
unchanged.

#### Scenario: New year starts in Draft and seeds a term

- **WHEN** a tenant admin creates a new academic year
- **THEN** the response is HTTP 201 with `data: { ..., status: "Draft" }` and
  exactly one default term exists for that year

### Requirement: The service SHALL republish `academic_term.created` for existing terms

academic-config MUST provide an operation that enqueues an
`academic_term.created` event through the transactional outbox for every existing
`academic_term` row, carrying the real `{ tenant_id, term_id, academic_year_id,
name, start_date, end_date, status }`. The operation supports the one-time heal
that populates downstream projections (e.g. grading's `valid_term`) with real
term ids. It MUST be safe to run more than once.

#### Scenario: Republish enqueues an event per existing term

- **WHEN** the republish operation runs for a tenant with existing terms
- **THEN** one `academic_term.created` event carrying the term's real `term_id`
  is enqueued through the outbox for each existing term

#### Scenario: Republish is idempotent for downstream consumers

- **WHEN** the republish operation runs twice
- **THEN** downstream projection consumers upsert the same `valid_term` rows
  without duplication or corruption (the events carry stable real `term_id`s)

### Requirement: A subject SHALL belong to exactly one subject group

The `subject` table MUST carry a non-null `subject_group_id` referencing a
`subject_group` in the same curriculum version. `POST /subjects` and
`PATCH /subjects/{id}` MUST accept `subject_group_id`; creating a subject
without it MUST be rejected with HTTP 400 `VALIDATION_ERROR` and a
`subject_group_id` field error. Moving a subject between groups via `PATCH`
MUST succeed when the target group belongs to the same curriculum version and
tenant; otherwise the response is HTTP 400 `VALIDATION_ERROR`.

Subject list and detail responses MUST include `subject_group_id` plus a group
summary `{ name, code, position }` so clients can group subjects without a
second round-trip.

#### Scenario: Creating a subject requires a group

- **WHEN** a tenant admin POSTs a subject without `subject_group_id`
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` with a `subject_group_id` field error and no subject is created

#### Scenario: Subject response carries its group

- **WHEN** a tenant admin GETs `/curriculum-versions/{id}/subjects`
- **THEN** each subject in `data` includes `subject_group_id` and a `subject_group` summary with `name`, `code`, and `position`

#### Scenario: Moving a subject to a group in another curriculum version is rejected

- **WHEN** a tenant admin PATCHes a subject with a `subject_group_id` from a different curriculum version
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` and the subject's group is unchanged

