## MODIFIED Requirements

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
