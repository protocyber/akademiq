## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Academic year creation emits status `Draft`

On creation the service MUST set the academic year's status to `Draft` and MUST
also create a default child term in the same transaction (see the added
requirement above). The `academic_year.created` event payload is otherwise
unchanged.

#### Scenario: New year starts in Draft and seeds a term

- **WHEN** a tenant admin creates a new academic year
- **THEN** the response is HTTP 201 with `data: { ..., status: "Draft" }` and
  exactly one default term exists for that year
