# web-academic-ops-management Specification

## Purpose

Defines web management screens for academic operations tables, including server-driven students, teachers, homerooms, rosters, teaching assignments, account-link readiness, and guarded delete flows.
## Requirements
### Requirement: Operational screens SHALL be server-driven data tables

The web app MUST render `/students`, `/teachers`, `/homerooms`, and
`/teaching-assignments` as shadcn data tables (TanStack Table), each with a
header/row multi-select checkbox column, sortable columns, a per-row actions
dropdown, a search box, and a bulk-delete flow confirmed via a reusable
AlertDialog/ConfirmDialog. Search, sort, and pagination MUST be synchronized to
the browser URL and MUST be server-driven via each list endpoint's query
parameters and `{ data, meta }` envelope. Create and edit MUST use Dialog modals.
Server referential-integrity guards (`STUDENT_ENROLLED`, `TEACHER_ASSIGNED`,
`HOMEROOM_NOT_EMPTY`) MUST be surfaced as readable errors.

#### Scenario: Student table is URL-synced and server-driven

- **WHEN** an admin searches and sorts the students table and moves to page 2
- **THEN** the URL carries search/sort/page params, the table shows the server-provided page, and reloading the URL reproduces the same view

#### Scenario: Deleting an enrolled student shows a readable guard

- **WHEN** an admin attempts to delete a student who has an active enrollment
- **THEN** the UI surfaces `STUDENT_ENROLLED` as a readable error and the student remains in the table

### Requirement: The teacher screen SHALL show account-link readiness and manage the link from the row

The teachers table MUST include an **Akun** column showing whether the teacher is
linked to a login account (Terhubung / Belum terhubung). Linking a teacher to a
login account MUST be available as a **"Hubungkan akun"** action in the per-row
actions dropdown that opens a modal to pick a teacher-role user. The teacher
master record and the login account remain distinct: a teacher MAY exist without
a login account, and deleting a teacher MUST NOT delete the linked user.

#### Scenario: Account link is performed from the row dropdown

- **WHEN** an admin chooses "Hubungkan akun" on a teacher row and selects a user
- **THEN** the teacher is linked to that login account and the Akun column shows Terhubung

#### Scenario: Unlinked teacher is shown as not ready

- **WHEN** a teacher has no linked login account
- **THEN** the Akun column shows "Belum terhubung" as the readiness signal

### Requirement: Homeroom roster SHALL be managed in a modal

The homerooms table MUST offer a per-row **"Roster"** action that opens a modal
listing the class roster as its own table with enroll and unenroll controls.
Enroll MUST use the enrollment endpoint and unenroll MUST use the enrollment
delete endpoint.

#### Scenario: Roster modal enrolls and unenrolls

- **WHEN** an admin opens the Roster modal for a class, enrolls a student, then unenrolls another
- **THEN** the roster table reflects both changes and the underlying enrollment state matches

### Requirement: Teaching assignments SHALL be a filtered table with a modal create form

The teaching-assignments screen MUST render assignments in a data table with
filter dropdowns (Tahun Ajaran, Kurikulum, Kelas), a per-row delete action, and a
**[Tambah Penugasan]** button that opens the chained create form
(tahun → kurikulum → kelas → guru → mapel) in a Dialog modal.

#### Scenario: Filtered assignment list and modal create

- **WHEN** an admin filters by year and class and creates a new assignment via the modal
- **THEN** the new assignment appears in the filtered table and per-row delete removes it

### Requirement: The Tambah Penugasan dialog dropdowns SHALL not be clipped

The multi-select dropdowns in the "Tambah Penugasan" dialog (teacher, subject, homeroom selectors) SHALL render their option popover fully visible, not clipped by the dialog's scroll/overflow container. The popover MUST render via a Portal so it escapes the dialog's `overflow` bounds, while preserving keyboard focus and typing in the embedded search input.

#### Scenario: Opening a multi-select shows all options

- **WHEN** an admin opens the teacher, subject, or homeroom multi-select inside the Tambah Penugasan dialog
- **THEN** the option list is fully visible and not cut off by the dialog edges

#### Scenario: Search input remains usable

- **WHEN** the multi-select popover is open inside the dialog
- **THEN** the user can focus the search field and type to filter options

### Requirement: The teaching-assignments table SHALL expose an expandable read-only evaluation and weight matrix per row

Each row in `/teaching-assignments` MUST provide an **[Expand]** control that,
when toggled, reveals a read-only grid of that assignment's evaluations (rows)
against the active year's report types (columns), each cell showing the stored
weight percent. Column totals MUST be shown and MUST flag any report type whose
weights do not sum to 100%. The evaluations and weights MUST be fetched lazily
only when the row is expanded, not for the whole page on load. The expanded
view MUST NOT include edit or save controls.

#### Scenario: Expanding a row shows its evaluation matrix

- **WHEN** the admin clicks [Expand] on a teaching-assignment row
- **THEN** a read-only grid appears listing that assignment's evaluations and their per-report-type weights, with column totals

#### Scenario: An under-weighted report type is flagged

- **WHEN** the expanded matrix has a report type whose weights total less than 100%
- **THEN** that column's total is flagged so the admin can see the formula is incomplete

#### Scenario: Unexpanded rows do not fetch evaluations

- **WHEN** the teaching-assignments page loads with 50 rows and none are expanded
- **THEN** no evaluation or weight requests are issued until a row is expanded

### Requirement: The expanded matrix SHALL link to grade entry for editing

The expanded evaluation panel MUST include an **"Atur di Entri Nilai"** link that
navigates to `/grading/entry?homeroom_id=<homeroom_id>&subject_id=<subject_id>`
so the admin can edit evaluations and weights without manual navigation.

#### Scenario: Deep link opens grade entry pre-scoped

- **WHEN** the admin clicks "Atur di Entri Nilai" on an expanded assignment
- **THEN** the app navigates to `/grading/entry` with the homeroom and subject pre-selected

