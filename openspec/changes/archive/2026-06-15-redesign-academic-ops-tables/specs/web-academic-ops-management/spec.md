## ADDED Requirements

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
