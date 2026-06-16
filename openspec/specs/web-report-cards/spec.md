# web-report-cards Specification

## Purpose
Defines requirements for the frontend web interface to manage academic year report types, set subject evaluation weights via the evaluation matrix, view live report scores, and view/approve report cards via the per-classroom report board.

## Requirements

### Requirement: Report types SHALL be managed from the academic-year edit form

The Edit Tahun Ajaran form MUST include a `§ Jenis Rapor` section (beside the
grading-policy and curriculum sections) that lists the year's report types and
lets the user add one with a **code** ("Rapor UTS") and **name** ("Rapor Tengah
Semester"). The section MUST be gated on a saved `academic_year_id`, like the
other sections, and MUST allow deleting a report type.

#### Scenario: Adding a report type from the year form

- **WHEN** the user opens Edit Tahun Ajaran, fills the Jenis Rapor code and name, and confirms
- **THEN** the new report type appears in the section's list for that year

#### Scenario: Section is gated before the year exists

- **WHEN** the year is being created and has no id yet
- **THEN** the Jenis Rapor controls are disabled with a hint that they are available after the year is created

### Requirement: The grade-entry grid SHALL show a read-only report-score column per report type

The `/grading/entry` grid MUST render, to the right of the editable evaluation
columns, one read-only column per report type of the selected year, each titled
by the report type's `code`. Each cell MUST show the student's live
`subject_report_score` for that report type and update after a grade is saved.
Evaluation column headers MUST NOT display a weight number.

#### Scenario: Report-score columns appear and update

- **WHEN** the user views the grid for a year with two report types and saves an evaluation grade
- **THEN** two read-only report-score columns (titled by code) are shown and the affected cells refresh to the recomputed values

#### Scenario: Evaluation headers carry no weight

- **WHEN** the grid is shown
- **THEN** each evaluation column header shows only its code/name, not a weight percentage

### Requirement: Per-report-type weights SHALL be set via a matrix in the Kelola Evaluasi modal

The Kelola Evaluasi modal MUST provide a weight matrix for the selected subject:
rows are the subject's evaluations and columns are the year's report types, each
cell a weight percent. Each report-type column MUST display its running total and
MUST require an exact 100% total to save. The add-evaluation form MUST remain
code/name only (no inline weight field).

#### Scenario: Column total enforces exactly 100%

- **WHEN** the user enters weights whose total for a report-type column is not 100
- **THEN** that column is flagged and cannot be saved until it totals exactly 100%

#### Scenario: Saving a valid column stores the formula

- **WHEN** a report-type column totals exactly 100%
- **THEN** saving persists the `(report_type, evaluation)` weights for that subject

### Requirement: The report board SHALL list report types for a chosen year and route into a per-class board

`/grading/report-cards` MUST provide a year selector and list that year's report
types (code, name, count) with a **[Buka Rapor]** action per row. There MUST be
no class picker on this screen. [Buka Rapor] MUST navigate to
`/grading/report-cards/<report_type_id>/classroom`, which lets the user pick a
class and navigate to
`/grading/report-cards/<report_type_id>/classroom/<classroom_id>`.

#### Scenario: Year list shows report types with open action

- **WHEN** the user selects a year that has report types
- **THEN** each report type is listed with its code, name, and a [Buka Rapor] action, and no class picker is shown

#### Scenario: Opening routes through classroom selection

- **WHEN** the user clicks [Buka Rapor] then picks a class
- **THEN** the app navigates to `/grading/report-cards/<report_type_id>/classroom/<classroom_id>`

### Requirement: The per-class board SHALL present status tabs with a student datatable and a detail modal

`/grading/report-cards/<report_type_id>/classroom/<classroom_id>` MUST show the
five workflow statuses (Draft, Review Wali Kelas, Persetujuan Kepala Sekolah,
Terbit, Arsip) as **tabs with per-status counts**. Each tab MUST render a student
**datatable** with multiselect checkboxes and a per-row **[Detail]** icon button.
[Detail] MUST open a large **modal** containing the report-card detail (the former
`/grading/report-cards/[id]` content), with a control to open the kept
`/grading/report-cards/[id]/print` route. The board MUST provide a
**[Generate Draft]** action for the `(report_type, classroom)`.

#### Scenario: Tabs show counts and the datatable

- **WHEN** the user opens the per-class board
- **THEN** five status tabs are shown with counts and the active tab lists its students in a datatable with checkboxes and a [Detail] action

#### Scenario: Detail opens in a modal

- **WHEN** the user clicks [Detail] on a student row
- **THEN** a large modal opens with that card's detail and a link to the print route, without navigating to a separate detail page

### Requirement: The student/parent portal SHALL NOT accept a free-text student id

The published report-card portal page (`/portal/report-card`) MUST NOT render a
free-text `student_id` input. Instead it MUST call the server-scoped
`GET /api/v1/grading/me/report-cards` endpoint to obtain the set of students the
signed-in user may view (self and/or linked children) and present them as a
server-controlled selector ("Pilih anak"). The page MUST request a specific card via
the ownership-validated `GET /api/v1/grading/me/report-cards/{student_id}` endpoint,
never by sending an arbitrary id the user typed. A `?student_id=` deep link MAY be
honored only after the backend confirms ownership.

#### Scenario: Portal shows only the caller's students

- **WHEN** a guardian opens `/portal/report-card`
- **THEN** the page lists only their linked children in a selector and shows no free-text student id input

#### Scenario: Selecting a child loads its report card

- **WHEN** the guardian selects a child and an academic year
- **THEN** the page fetches and displays that child's published report card via the `me/report-cards/{student_id}` endpoint

#### Scenario: A non-owned deep link is rejected

- **WHEN** the user opens `/portal/report-card?student_id=<not-their-child>`
- **THEN** the page shows a not-available/forbidden state and does not render another student's card
