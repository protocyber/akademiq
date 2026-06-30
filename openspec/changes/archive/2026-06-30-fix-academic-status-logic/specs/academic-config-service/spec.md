## ADDED Requirements

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
