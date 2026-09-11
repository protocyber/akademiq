# web-academic-config-management Specification

## Purpose
TBD - created by archiving change redesign-academic-config-tables. Update Purpose after archive.
## Requirements
### Requirement: Admins SHALL manage academic years in a server-driven data table

The web app MUST provide an academic-year screen at `/settings/academic/years`
that lists years in a shadcn data table (TanStack Table) with a header/row
multi-select checkbox column, sortable columns, and a per-row actions dropdown
(Edit / Hapus). The screen MUST provide a search box and MUST keep search, sort,
and pagination synchronized to the browser URL so refresh, bookmark, and share
reproduce the same view. List data, sorting, and pagination MUST be server-driven
via the `GET /academic-years` query parameters and `{ data, meta }` envelope.

The create/edit modal MUST use shadcn `Tabs` (not styled buttons) with exactly
three tabs — **Info** (name, start/end dates, and status with its lifecycle
transition control), **Kebijakan Nilai** (minimum passing score and grading
scale, persisted via the grading-policy upsert), and **Versi Kurikulum** (an
inline list of the year's curriculum versions with add and delete) — and MUST
provide an explicit **Simpan** action for the Info tab. On the create flow the
Kebijakan Nilai and Versi Kurikulum tabs MAY be disabled until the year exists;
on edit they MUST be editable. The modal MUST NOT contain Semester or Jenis Rapor
sections (terms are managed on `/settings/academic/terms`; report types on the
semester edit form).

Deleting a year MUST be confirmed via a reusable AlertDialog/ConfirmDialog, and
the screen MUST surface server guards (`ACTIVE_YEAR_IMMUTABLE`, `YEAR_IN_USE`) as
readable errors rather than failing silently.

#### Scenario: Year list is URL-synced and server-driven

- **WHEN** an admin sorts the year table by name and navigates to page 2
- **THEN** the browser URL carries the sort and page params, the table shows the server-provided page, and reloading the URL reproduces the same sorted page

#### Scenario: Year modal uses three real tabs with a save button

- **WHEN** an admin opens the year edit modal
- **THEN** it shows shadcn `Tabs` with Info / Kebijakan Nilai / Versi Kurikulum, an explicit Simpan button on Info, and no Semester or Jenis Rapor section

#### Scenario: Grading policy is edited inside the year modal

- **WHEN** an admin opens the edit modal for an existing year and saves a new minimum passing score in the Kebijakan Nilai tab
- **THEN** the grading-policy upsert is called for that year and the saved values are shown on reopening the modal

#### Scenario: Deleting an active year is blocked with a readable message

- **WHEN** an admin attempts to delete a year whose status is `Active`
- **THEN** the UI shows the server `ACTIVE_YEAR_IMMUTABLE` guard as a readable error and the year remains in the table

### Requirement: Admins SHALL manage subjects in a filtered data table

The web app MUST provide a subjects screen at `/settings/academic/subjects`
listing subjects grouped by **Kelompok Mata Pelajaran**, where each kelompok
is a collapsible section rendered above its subjects. The screen MUST provide
two cascading filter dropdowns at the top — **Tahun Ajaran** then **Versi
Kurikulum** — where the version options depend on the selected year and the
subjects table is empty until a curriculum version is selected. The selected
year and version MUST be reflected in the browser URL.

Within a selected curriculum version the screen MUST also allow managing the
kelompok: add (name, optional code, position), edit, delete, and reorder
(position), scoped to that curriculum version. Groups MUST be listed in
`position` order; subjects within a group MUST be listed by name.

Creating and editing subjects MUST use a Dialog modal (name, code, passing
grade, and a **Kelompok** selector defaulting to the first group). Bulk delete
of subjects MUST be confirmed via AlertDialog/ConfirmDialog and MUST surface
the server `SUBJECT_IN_USE` guard. Deleting a kelompok that still has subjects
MUST surface the server `SUBJECT_GROUP_IN_USE` guard as a readable error.

#### Scenario: Subjects require a selected curriculum version

- **WHEN** an admin opens the subjects screen without selecting a curriculum version
- **THEN** the table prompts the admin to pick a year and version and lists no subjects until a version is selected

#### Scenario: Subjects are rendered grouped by kelompok

- **WHEN** an admin selects a curriculum version that has two kelompok each with subjects
- **THEN** the screen renders two group sections in position order, each listing its subjects, rather than a single flat table

#### Scenario: Creating a kelompok scoped to the selected curriculum version

- **WHEN** an admin adds a kelompok named "Muatan Lokal" with position 3 for the selected curriculum version
- **THEN** the new kelompok section appears in position order and is empty until subjects are added to it

#### Scenario: Bulk delete blocked by an in-use subject

- **WHEN** an admin selects several subjects including one referenced by a teaching assignment and confirms bulk delete
- **THEN** the UI surfaces `SUBJECT_IN_USE` and none of the selected subjects are removed

#### Scenario: Deleting a non-empty kelompok is blocked

- **WHEN** an admin attempts to delete a kelompok that still has subjects
- **THEN** the UI surfaces `SUBJECT_GROUP_IN_USE` as a readable error and the kelompok remains

### Requirement: Admins SHALL manage class templates in a filtered data table

The web app MUST rebuild `/settings/academic/class-templates` as a shadcn data
table filtered by **Tahun Ajaran**, with multi-select, sortable columns, a
per-row actions dropdown (Edit / Hapus), a bulk-delete flow, and a Dialog modal
for create/edit (grade level, default capacity). The selected year MUST be
reflected in the browser URL.

#### Scenario: Class templates are scoped to the selected year

- **WHEN** an admin selects a year in the class-templates filter
- **THEN** the table lists only that year's templates and the selected year is carried in the URL

### Requirement: The academic settings navigation SHALL reflect the new structure

The academic settings nav MUST list **Tahun Ajaran**, **Mata Pelajaran**, and
**Template Kelas**. Kelompok management lives inside the Mata Pelajaran screen
(once a curriculum version is selected), not as a separate nav entry. The
standalone **Kebijakan Nilai** and **Kurikulum** tabs MUST be removed; their
management lives inside the academic-year modal (Kebijakan Nilai and Versi
Kurikulum sections).

#### Scenario: Grading-policy page is gone

- **WHEN** an admin navigates to `/settings/academic/grading-policy`
- **THEN** the standalone page no longer exists and grading policy is managed inside the academic-year modal

#### Scenario: Kelompok is managed inside the Mata Pelajaran screen

- **WHEN** an admin selects a curriculum version on the Mata Pelajaran screen
- **THEN** kelompok add/edit/delete/reorder controls appear on that screen and there is no separate Kelompok nav entry

### Requirement: The term edit form SHALL provide an Evaluasi tab after the Rapor tab

The term (semester) edit form at `/settings/academic/terms` MUST present its tabs in the order **Info, Status, Rapor, Evaluasi**. The Evaluasi tab MUST appear after the Rapor tab because its weight matrix columns are the report types managed in the Rapor tab. The Evaluasi tab MUST reuse the "Kelola Evaluasi" experience: a template evaluation list (add, edit, delete, reorder) plus a weight matrix whose columns are the term's report types. The tab MUST be available only to admins permitted to manage academic configuration.

#### Scenario: Evaluasi tab is shown after Rapor

- **WHEN** an admin opens the edit form for a term
- **THEN** the tabs read Info, Status, Rapor, Evaluasi in that order

#### Scenario: Editing template evaluations

- **WHEN** the admin adds a template evaluation on the Evaluasi tab and saves
- **THEN** the template evaluation is persisted for that term and appears in the list in `position` order

#### Scenario: Weight matrix columns are the term's report types

- **WHEN** the admin opens the Evaluasi tab for a term that has report types defined on the Rapor tab
- **THEN** the weight matrix shows one column per report type and accepts weights that must total 100% per report type before saving

### Requirement: The term edit form SHALL let admins apply the template to existing assignments

The Evaluasi tab MUST provide an action to apply the term's template (evaluations and weights) to all teaching assignments in the term that have no evaluations yet. The action MUST report how many assignments were filled and MUST be safe to invoke repeatedly. The tab MUST surface a nudge when assignments in the term still lack evaluations.

#### Scenario: Apply button fills assignments lacking evaluations

- **WHEN** the admin clicks "Terapkan daftar evaluasi ini untuk semua penugasan" for a term with template entries
- **THEN** assignments without evaluations receive the template's evaluations and the admin sees how many were filled

#### Scenario: Nudge reflects remaining work

- **WHEN** the term has assignments without evaluations
- **THEN** the Evaluasi tab shows a count of assignments that still need the template applied

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

### Requirement: Operators SHALL manage academic terms per year

The web console MUST provide a term-management surface scoped to an academic
year (as a section/sub-page of the year management area) that lists the year's
terms and allows creating, editing, and deleting a term, and transitioning a
term's status. Term status transitions MUST reuse the confirmation UX pattern
(type-to-confirm + cooldown for backward/`→ Archived` transitions) established
for academic-year transitions.

#### Scenario: Create a term

- **WHEN** a tenant admin opens a year and creates a term "Semester 2" with
  dates within the year
- **THEN** the term appears in the list with status `Draft`

#### Scenario: Transition a term with confirmation

- **WHEN** a tenant admin transitions a term from `Active` back to `Draft`
- **THEN** a type-to-confirm dialog with a 5-second cooldown is shown before the
  request is sent

### Requirement: Deleting a term SHALL be guarded

Deleting a term MUST be rejected by the backend when the term is referenced by
evaluations, report types, or grades (the UI surfaces the resulting error). The
UI MUST confirm a delete with the operator before issuing the request.

#### Scenario: Delete a term with dependent data shows an error

- **WHEN** a tenant admin attempts to delete a term that has evaluations and
  confirms the dialog
- **THEN** the UI surfaces the backend error (e.g. `TERM_IN_USE`) and the term
  is not removed

### Requirement: The UI SHALL warn when an active year has no active term

The web console MUST show a visible warning in the year/term management area when
the selected academic year is `Active` but none of its terms is `Active`,
prompting the operator to activate a term. This warning MUST be consistent with
the header warning specified in `web-academic-scope`.

#### Scenario: Warning is shown on the management page

- **GIVEN** the selected year is `Active` and all its terms are `Draft`
- **WHEN** the tenant admin opens the term management area
- **THEN** a warning is displayed prompting term activation

### Requirement: Academic-config management pages SHALL respect read permission

The web console MUST gate every academic-config management page — years,
curriculum, subjects, class templates, and the new term-management surface — on
`academic.config.read` (introduced by `rbac-read-and-menu-restructure`) for
viewing, and on `academic.config.write` for create/edit/delete/status
transitions.

#### Scenario: Term management is visible to readers

- **WHEN** a role holding `academic.config.read` opens the academic-config area
- **THEN** the term-management surface is visible; create/edit/delete/status
  controls are disabled unless the role also holds `academic.config.write`

