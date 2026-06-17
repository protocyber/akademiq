## MODIFIED Requirements

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

### Requirement: Academic year creation SHALL emit status `Draft`

On creation the service MUST set the academic year's status to `Draft`. The
`academic_year.created` event payload is otherwise unchanged.

#### Scenario: New year starts in Draft

- **WHEN** a tenant admin creates a new academic year
- **THEN** the response is HTTP 201 with `data: { ..., status: "Draft" }`

## ADDED Requirements

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
