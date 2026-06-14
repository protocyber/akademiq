## ADDED Requirements

### Requirement: Admins SHALL manage academic years in a server-driven data table

The web app MUST provide an academic-year screen at `/settings/academic/years`
that lists years in a shadcn data table (TanStack Table) with a header/row
multi-select checkbox column, sortable columns, and a per-row actions dropdown
(Edit / Hapus). The screen MUST provide a search box and MUST keep search, sort,
and pagination synchronized to the browser URL so refresh, bookmark, and share
reproduce the same view. List data, sorting, and pagination MUST be server-driven
via the `GET /academic-years` query parameters and `{ data, meta }` envelope.

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

The academic settings nav MUST list **Tahun Ajaran**, **Mata Pelajaran**, and
**Template Kelas**. The standalone **Kebijakan Nilai** and **Kurikulum** tabs
MUST be removed; their management lives inside the academic-year modal
(Kebijakan Nilai and Versi Kurikulum sections) and the subjects screen.

#### Scenario: Grading-policy page is gone

- **WHEN** an admin navigates to `/settings/academic/grading-policy`
- **THEN** the standalone page no longer exists and grading policy is managed inside the academic-year modal
