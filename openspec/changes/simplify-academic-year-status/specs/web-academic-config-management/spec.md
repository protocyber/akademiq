## MODIFIED Requirements

### Requirement: Admins SHALL manage academic years in a server-driven data table

The web app MUST provide an academic-year screen at `/settings/academic/years`
that lists years in a shadcn data table (TanStack Table) with a header/row
multi-select checkbox column, sortable columns, and a per-row actions dropdown
(Edit / Hapus). The screen MUST provide a search box and MUST keep search, sort,
and pagination synchronized to the browser URL so refresh, bookmark, and share
reproduce the same view. List data, sorting, and pagination MUST be server-driven
via the `GET /academic-years` query parameters and `{ data, meta }` envelope.

The academic-year status set MUST be exactly four values: `Draft`, `Active`,
`Closed`, `Archived`. The status lifecycle control MUST allow transitions per
the backend rules: bidirectional between `Draft`, `Active`, and `Closed`, and
`Closed → Archived` as the sole forward-only irreversible step.

The create/edit modal MUST be a single scrolling sectioned form containing
**Identitas** (name, start/end dates, and status with its lifecycle transition
control), **Kebijakan Nilai** (minimum passing score and grading scale, persisted
via the grading-policy upsert), and **Versi Kurikulum** (an inline list of the
year's curriculum versions with add and delete). On the create flow the Kebijakan
Nilai and Versi Kurikulum sections MAY be disabled until the year exists; on edit
they MUST be editable.

Deleting a year MUST be confirmed via a reusable AlertDialog/ConfirmDialog, and
the screen MUST surface server guards (`ACTIVE_YEAR_IMMUTABLE`, `YEAR_IN_USE`) as
readable errors rather than failing silently.

#### Scenario: Year list is URL-synced and server-driven

- **WHEN** an admin sorts the year table by name and navigates to page 2
- **THEN** the browser URL carries the sort and page params, the table shows the server-provided page, and reloading the URL reproduces the same sorted page

#### Scenario: Grading policy is edited inside the year modal

- **WHEN** an admin opens the edit modal for an existing year and saves a new minimum passing score in the Kebijakan Nilai section
- **THEN** the grading-policy upsert is called for that year and the saved values are shown on reopening the modal

#### Scenario: Deleting an active year is blocked with a readable message

- **WHEN** an admin attempts to delete a year whose status is `Active`
- **THEN** the UI shows the server `ACTIVE_YEAR_IMMUTABLE` guard as a readable error and the year remains in the table

## ADDED Requirements

### Requirement: Status transitions SHALL require a tights confirmation flow with a reason

Every academic-year status change initiated from the UI MUST open a confirmation
dialog that requires a non-empty `reason` (min 10 chars) and whose strictness
scales with the transition's risk:

- Forward transitions to `Active` or `Closed` MUST show an impact summary and a
  reason field.
- Backward transitions (`Active → Draft`, `Closed → Active`, `Closed → Draft`)
  MUST additionally require type-to-confirm (the admin types the target status
  label exactly) and MUST keep the submit button disabled for a 5-second
  cooldown after the dialog opens.
- The `Closed → Archived` transition MUST show an extra prominent,
  non-dismissable warning that it is irreversible and that published report
  cards for the year will be archived, in addition to type-to-confirm and the
  5-second cooldown.

The dialog MUST send `{ status, reason }` to `PATCH /academic-years/{id}/status`
and MUST surface server errors (`INVALID_STATE_TRANSITION`,
`ACTIVE_YEAR_EXISTS`, `VALIDATION_ERROR` on `reason`) as readable messages.

#### Scenario: Forward transition confirms with reason only

- **WHEN** an admin transitions a `Draft` year to `Active` and enters a valid reason
- **THEN** the submit button is enabled without a cooldown and the PATCH is sent with the reason

#### Scenario: Backward transition requires type-to-confirm and cooldown

- **WHEN** an admin transitions a `Closed` year back to `Active`
- **THEN** the dialog requires the admin to type "Active" exactly and keeps the submit button disabled for 5 seconds after opening

#### Scenario: Archived transition shows the irreversible warning

- **WHEN** an admin transitions a `Closed` year to `Archived`
- **THEN** the dialog shows a prominent warning that the action is irreversible and will archive published report cards, requires typing "Archived", and enforces the 5-second cooldown

#### Scenario: Missing reason blocks submission

- **WHEN** an admin opens a status-change dialog and attempts to submit without a reason (or a reason under 10 characters)
- **THEN** the submit button remains disabled and a validation message is shown

#### Scenario: Server validation error on reason is surfaced

- **WHEN** the backend rejects a transition with `VALIDATION_ERROR` on the `reason` field
- **THEN** the UI shows the field error inline and the year's status is unchanged
