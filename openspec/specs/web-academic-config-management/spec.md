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
listing subjects in a shadcn data table with multi-select, sortable columns
(Nama, Kode, KKM), a per-row actions dropdown (Edit / Hapus), and a bulk-delete
flow. The screen MUST provide two cascading filter dropdowns at the top —
**Tahun Ajaran** then **Versi Kurikulum** — where the version options depend on
the selected year and the subjects table is empty until a curriculum version is
selected. The selected year and version MUST be reflected in the browser URL.

Creating and editing subjects MUST use a Dialog modal (name, code, passing
grade). Bulk delete MUST be confirmed via AlertDialog/ConfirmDialog and MUST
surface the server `SUBJECT_IN_USE` guard.

#### Scenario: Subjects require a selected curriculum version

- **WHEN** an admin opens the subjects screen without selecting a curriculum version
- **THEN** the table prompts the admin to pick a year and version and lists no subjects until a version is selected

#### Scenario: Bulk delete blocked by an in-use subject

- **WHEN** an admin selects several subjects including one referenced by a teaching assignment and confirms bulk delete
- **THEN** the UI surfaces `SUBJECT_IN_USE` and none of the selected subjects are removed

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

The academic settings nav MUST list **Tahun Ajaran**, **Semester**,
**Mata Pelajaran**, and **Template Kelas**. The standalone **Kebijakan Nilai**
and **Kurikulum** tabs MUST be removed; their management lives inside the
academic-year modal (Kebijakan Nilai and Versi Kurikulum tabs) and the subjects
screen. The **Semester** entry MUST link to `/settings/academic/terms`.

#### Scenario: Grading-policy page is gone

- **WHEN** an admin navigates to `/settings/academic/grading-policy`
- **THEN** the standalone page no longer exists and grading policy is managed inside the academic-year modal

#### Scenario: Semester tab is present in the academic settings nav

- **WHEN** an admin views the academic settings navigation
- **THEN** a **Semester** tab is listed and links to `/settings/academic/terms`

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

