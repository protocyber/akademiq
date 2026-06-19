## ADDED Requirements

### Requirement: Admins SHALL manage academic terms on a standalone page

The web app MUST provide a term-management page at `/settings/academic/terms`,
registered as the **Semester** tab in the academic-config shell. The page MUST
list the terms of the year currently in academic scope using a server-driven
`DataTable` (URL search params `search`, `page`, `page_size`, `sort`; default
sort `start_date`, page size 10) matching the layout of the Tahun Ajaran page:
search input, create button in the top-right, sortable columns, and pagination
controls. The page MUST support creating, editing, deleting, and transitioning a
term's status. Per-row actions MUST be a visible `Edit` button plus an
icon-only (`⋮`) dropdown containing `Delete`. Term status transitions MUST reuse
the type-to-confirm + cooldown UX established for academic-year transitions and
MUST be performed from the edit modal's Info tab. The page MUST be gated on
`academic.config.read` for viewing and `academic.config.write` for mutations.

#### Scenario: Terms list for the scoped year

- **WHEN** an admin opens `/settings/academic/terms` with a year selected in the
  academic scope
- **THEN** the page lists that year's terms in a `DataTable` with their status

#### Scenario: Server-side search and pagination

- **WHEN** an admin types in the search input or changes page/sort
- **THEN** the query is reflected in URL params and the backend returns the
  matching page of terms

#### Scenario: Row actions

- **WHEN** an admin views a term row
- **THEN** it shows a visible `Edit` button and an icon-only `⋮` dropdown with
  `Delete`

#### Scenario: Create a term

- **WHEN** an admin creates a term "Semester 2" with dates within the scoped year
- **THEN** the term appears in the list with status `Draft`

#### Scenario: Transition a term with confirmation

- **WHEN** an admin transitions a term from `Active` back to `Draft` via the
  edit modal's Info tab
- **THEN** a type-to-confirm dialog with a cooldown is shown before the request
  is sent

#### Scenario: Read-only role cannot mutate

- **WHEN** a role holding only `academic.config.read` opens the page
- **THEN** the term list is visible and create/edit/delete/transition controls
  are disabled

### Requirement: The term create/edit form SHALL be a tabbed modal

The web app MUST use a single `TermFormModal` for both create and edit. **Create
mode** MUST render only an Info tab (name, dates, optional report-type copy
selector). **Edit mode** MUST render two real shadcn `Tabs`: **Info** (name,
dates, status transition + an explicit Simpan button) and **Rapor** (the
term-scoped report type list with add/edit/delete/reorder). The report-type tab
label MUST be "Rapor". After a successful create, the modal MUST reopen in edit
mode on the `Rapor` tab for the newly created term.

#### Scenario: Create form has only Info

- **WHEN** an admin opens the create modal
- **THEN** only the Info tab is visible

#### Scenario: Edit form exposes Info and Rapor tabs

- **WHEN** an admin opens the edit modal for a term
- **THEN** it shows shadcn `Tabs` with Info and Rapor

#### Scenario: Info Simpan persists identity and status

- **WHEN** an admin edits name/dates and changes status in the Info tab then
  presses Simpan
- **THEN** the update is sent and, if the status changed, the transition is run

#### Scenario: Report type is created against the term

- **WHEN** an admin adds a report type "Rapor Tengah Semester" on the Rapor tab
  of a term
- **THEN** the report type is created scoped to that term's `term_id`

### Requirement: Admins SHALL copy report types between semesters

The web app MUST let an admin copy report-type definitions from another semester
within the same academic year: (a) during term create via an optional selector,
and (b) from the Rapor tab via a "Salin dari semester lain" action that opens a
source-term picker dialog. Copy MUST copy definitions only (`code`, `name`,
relative `position`) and skip report types whose code already exists in the
target term. The source-term selector MUST be limited to terms in the same
academic year, excluding the target term, and MUST be disabled when no source
term has report types. On success the UI MUST show how many were copied vs
skipped.

#### Scenario: Copy during create

- **WHEN** an admin checks "Salin daftar rapor dari semester lain" and selects a
  source semester while creating a term
- **THEN** after the term is created, report types are copied from the source
  and the modal reopens on the Rapor tab

#### Scenario: Copy from the Rapor tab

- **WHEN** an admin clicks "Salin dari semester lain" on the Rapor tab and
  picks a source semester
- **THEN** report types are copied and a toast reports `X disalin, Y dilewati`

### Requirement: The report board empty state SHALL reference the semester form

The report-card board MUST NOT instruct users to add report types from
"Pengaturan → Tahun Ajaran". When a term has no report types, the empty state
MUST direct the operator to the semester edit form (Rapor tab) for the selected
term.

#### Scenario: Corrected empty-state guidance

- **WHEN** the report board has no report types for the selected term
- **THEN** the empty-state message references managing report types on the
  semester form, not the year settings page
