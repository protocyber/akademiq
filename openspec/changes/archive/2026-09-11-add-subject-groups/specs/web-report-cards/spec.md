## MODIFIED Requirements

### Requirement: The per-class board SHALL present status tabs with a student datatable and a detail modal

`/grading/report-cards/<report_type_id>/classroom/<classroom_id>` MUST show the
five workflow statuses (Draft, Review Wali Kelas, Persetujuan Kepala Sekolah,
Terbit, Arsip) as **tabs with per-status counts**. Each tab MUST render a student
**datatable** with multiselect checkboxes and a per-row **[Detail]** icon button.
[Detail] MUST open a large **modal** containing the report-card detail (the former
`/grading/report-cards/[id]` content), with a control to open the kept
`/grading/report-cards/[id]/print` route. The board MUST provide a
**[Generate Draft]** action for the `(report_type, classroom)`.

The report-card detail (modal and print route) MUST render each subject's frozen
`report_subject_score` grouped under its **Kelompok Mata Pelajaran**, ordered by
`subject_group.position` ascending then by subject name. Group headers MUST
appear above their subjects; subjects whose group cannot be resolved MUST NOT be
silently dropped (render them under the group summary returned with the subject).
Scores and formulas are unchanged.

#### Scenario: Tabs show counts and the datatable

- **WHEN** the user opens the per-class board
- **THEN** five status tabs are shown with counts and the active tab lists its students in a datatable with checkboxes and a [Detail] action

#### Scenario: Detail opens in a modal

- **WHEN** the user clicks [Detail] on a student row
- **THEN** a large modal opens with that card's detail and a link to the print route, without navigating to a separate detail page

#### Scenario: Subject scores are grouped by kelompok in the detail

- **WHEN** the user opens a report-card detail for a student whose subjects span two kelompok
- **THEN** the detail renders two group headers in position order, each followed by its subjects' scores, instead of a flat subject list

### Requirement: The student/parent portal SHALL NOT accept a free-text student id

The published report-card portal page (`/portal/report-card`) MUST NOT render a
free-text `student_id` input. Instead it MUST call the server-scoped
`GET /api/v1/grading/me/report-cards` endpoint to obtain the set of students the
signed-in user may view (self and/or linked children) and present them as a
server-controlled selector ("Pilih anak"). The page MUST request a specific card via
the ownership-validated `GET /api/v1/grading/me/report-cards/{student_id}` endpoint,
never by sending an arbitrary id the user typed. A `?student_id=` deep link MAY be
honored only after the backend confirms ownership.

The portal's report-card display MUST render subject scores grouped by
**Kelompok Mata Pelajaran** (ordered by `subject_group.position` then subject
name), matching the admin report-card detail.

#### Scenario: Portal shows only the caller's students

- **WHEN** a guardian opens `/portal/report-card`
- **THEN** the page lists only their linked children in a selector and shows no free-text student id input

#### Scenario: Selecting a child loads its report card

- **WHEN** the guardian selects a child and an academic year
- **THEN** the page fetches and displays that child's published report card via the `me/report-cards/{student_id}` endpoint

#### Scenario: A non-owned deep link is rejected

- **WHEN** the user opens `/portal/report-card?student_id=<not-their-child>`
- **THEN** the page shows a not-available/forbidden state and does not render another student's card

#### Scenario: Portal report card groups subjects by kelompok

- **WHEN** the guardian views a child's published report card whose subjects span multiple kelompok
- **THEN** the portal renders group headers in position order, each followed by its subjects' scores
