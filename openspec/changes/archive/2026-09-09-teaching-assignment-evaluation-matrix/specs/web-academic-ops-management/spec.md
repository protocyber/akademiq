## ADDED Requirements

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
