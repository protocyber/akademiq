## MODIFIED Requirements

### Requirement: The per-class board SHALL present status tabs with a student datatable and a detail modal

`/grading/report-cards` MUST show the five workflow statuses (Draft, Review
Wali Kelas, Persetujuan Kepala Sekolah, Terbit, Arsip) as **tabs with
per-status counts**. Each tab MUST render a student **datatable** sourced from
the **full homeroom roster**, not only from generated report cards. A student
in the roster who has no `ReportCard` MUST appear in the **Draft** tab with a
disabled [Detail] action. The datatable MUST provide multiselect checkboxes and
a per-row **[Detail]** action. [Detail] MUST open a large **modal** containing
the report-card detail, with a control to open the
`/grading/report-cards/[id]/print` route. The board MUST provide a
**[Generate Draft]** action for the `(report_type, classroom)`.

Each row MUST also show: an **average score** (or `—` when no card exists) and
a **progress chip** `X/Y` where `Y` is the number of distinct subjects assigned
to the homeroom for the active academic year and `X` is the number of those
subjects with a present final score on the student's card. A row where `X < Y`
MUST display an incomplete flag.

#### Scenario: Tabs show counts and the roster-merged datatable

- **WHEN** the user opens the per-class board
- **THEN** five status tabs are shown with counts and the active tab lists every roster student in a datatable with checkboxes, an average score, a progress chip, and a [Detail] action

#### Scenario: Students without a card appear in Draft

- **WHEN** a roster student has no generated report card
- **THEN** that student is listed in the Draft tab with an `0/Y` progress chip, an average of `—`, and a disabled [Detail] action

#### Scenario: Detail opens in a modal

- **WHEN** the user clicks [Detail] on a student row that has a card
- **THEN** a large modal opens with that card's detail and a link to the print route, without navigating to a separate detail page

### Requirement: The per-class board SHALL expose per-subject final scores via a global expand toggle

Each datatable row MUST provide an **[Expand]** action that toggles a global
column set: when expanded, the table widens to the right with one read-only
column per subject assigned to the homeroom+year, titled by subject name. Each
cell MUST show the student's final score for that subject (from
`ReportCard.summary.subjects`) or `—` when no score exists. The expand toggle
MUST apply to the whole table (all rows gain the columns simultaneously), not
to a single row's sub-table. The [Expand] action MUST be collapsible back to
the compact column set.

#### Scenario: Expanding adds subject columns across all rows

- **WHEN** the user clicks [Expand] on any row
- **THEN** one read-only final-score column per assigned subject appears across every row, each showing the score or `—`, and the table scrolls horizontally if needed

#### Scenario: Collapsing returns to the compact view

- **WHEN** the user clicks the collapse control
- **THEN** the per-subject columns are removed and the table returns to the compact column set

## ADDED Requirements

### Requirement: The board SHALL provide a bulk-print action for checked report cards

The per-class board MUST provide a **"Cetak Terpilih"** bulk action that is
enabled when one or more report cards are checked. Activating it MUST open a
single print document containing every checked card, each rendered as a
full A4 page separated from the next by a CSS page break. The checked report
card IDs MUST be passed to the print route via `localStorage`. The single-card
print route (`/grading/report-cards/[reportTypeId]/print`) MUST remain available
for the detail-modal print link.

#### Scenario: Bulk print opens a multi-card document

- **WHEN** the user checks three report cards and activates "Cetak Terpilih"
- **THEN** a single print document opens containing all three cards, each on its own A4 page with a page break between them

#### Scenario: Single-card print still works from the modal

- **WHEN** the user opens the detail modal and clicks the print link
- **THEN** the single-card print route opens for that one card as before

### Requirement: The A4 print layout SHALL fit a physical A4 page without clipping

The print route MUST use `@page` margins and a container width that fit the
content within a physical A4 page (210mm × 297mm). Each per-kelompok score
table MUST NOT split across pages (it MUST keep its rows together). No content
MUST be clipped or overflow the printable area. In bulk mode, each card MUST
start on a new page.

#### Scenario: A single card fits on one A4 page

- **WHEN** a report card with several kelompok groups is printed
- **THEN** all content fits within the A4 printable area and no kelompok table is split across pages

#### Scenario: Cards in bulk mode start on fresh pages

- **WHEN** multiple cards are printed in bulk mode
- **THEN** each card begins on a new A4 page, separated by a page break
