## ADDED Requirements

### Requirement: The term edit form SHALL NOT transition status on save

The `TermInfoSection` "Simpan" button (`term-form-modal.tsx`) MUST only call
the term update mutation (`useUpdateAcademicTerm`) with
`{ name, start_date, end_date }`. It MUST NOT call the transition mutation.
Status changes MUST happen exclusively through the dedicated "Ubah Status"
button, which opens `StatusConfirmDialog` and calls the transition mutation
with the user-supplied reason.

#### Scenario: Editing term name does not change status

- **WHEN** a user edits a term's name/dates and clicks "Simpan"
- **THEN** only the update request is sent; no status transition request is
  sent; the term's status remains unchanged

#### Scenario: Status change requires explicit button click

- **WHEN** a user wants to change a term's status
- **THEN** they MUST click "Ubah Status", which opens the confirmation dialog;
  the transition request is sent only after dialog confirmation

### Requirement: The year edit form SHALL provide a save button

The `IdentitySection` in `years/page.tsx` MUST render a "Simpan" button in
edit mode that calls `useUpdateAcademicYear` with
`{ name, start_date, end_date }`. The button MUST be disabled while the update
is pending. On success, the form reflects the saved values and the year list
refreshes.

#### Scenario: Save year edits

- **WHEN** a user edits a year's name/dates in edit mode and clicks "Simpan"
- **THEN** the update request is sent to `PATCH /academic-years/:id`; on
  success the year list refreshes with the updated values and the status is
  unchanged

### Requirement: The status confirm dialog SHALL make reason optional for forward transitions

`StatusConfirmDialog` MUST render the reason field with an "opsional"
indicator for the `forward` tier. The submit button MUST NOT be disabled by
an empty or short reason when the tier is `forward`. For `backward` and
`archived` tiers, the reason field MUST remain required (≥ 10 characters) and
the submit button MUST remain disabled until the reason is valid.

#### Scenario: Forward transition submits without reason

- **WHEN** a user performs a forward transition (e.g. Draft→Active) and
  leaves the reason field empty
- **THEN** the submit button is enabled and the transition request is sent
  with no reason (or an empty reason is omitted from the payload)

#### Scenario: Backward transition requires reason

- **WHEN** a user performs a backward transition (e.g. Active→Draft) and
  leaves the reason field empty or < 10 characters
- **THEN** the submit button is disabled until a valid reason (≥ 10 chars)
  is entered

### Requirement: The UI SHALL refresh all dependent data after a status transition

The UI MUST refresh all dependent data after a successful year or term status transition. The mutation's `onSuccess` MUST invalidate the primary list query key AND all identified dependent query keys (academic scope context, dashboard KPIs that depend on year/term status) so that the UI reflects the new status without requiring a manual page refresh.

#### Scenario: UI updates after term status change

- **WHEN** a term status transition succeeds
- **THEN** the term list, year list (if affected), and academic scope context
  all refresh to reflect the new status
