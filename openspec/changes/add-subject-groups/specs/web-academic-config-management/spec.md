## MODIFIED Requirements

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
