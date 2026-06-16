## ADDED Requirements

### Requirement: The report screen SHALL list report batches in a datatable

The `/grading/report-cards` screen MUST let the user pick Tahun and Kelas, then
list that class+year's report batches in a datatable with a **[+ Tambah Rapor]**
control to create a new named batch. Each row MUST expose **[Atur Bobot]** and
**[Buka]** actions and summarize the batch's progress (e.g. draft count).

#### Scenario: Creating a batch adds a row

- **WHEN** the user clicks [+ Tambah Rapor], names it "Rapor Akhir", and confirms
- **THEN** a new batch row appears for the selected class+year

#### Scenario: Batches are listed per class and year

- **WHEN** the user selects a year and class that have two batches
- **THEN** both batches are listed, each with its progress summary and row actions

### Requirement: The screen SHALL set per-subject weights in a modal enforcing an exact 100% total

**[Atur Bobot]** MUST open a modal listing the class's subjects, each with weight
inputs over that subject's evaluations. A subject row counts as configured only
when its weights total **exactly 100%**; a row that is empty or ≠ 100% MUST be
shown as "belum diatur" and will be skipped at compute. The modal MUST surface
the running total per subject.

#### Scenario: Exact-100 row is marked valid

- **WHEN** the user enters weights summing to exactly 100 for a subject
- **THEN** the row shows a valid (100%) state and will be included in compute

#### Scenario: Non-100 row is flagged and skipped

- **WHEN** a subject's weights sum to more or less than 100
- **THEN** the row shows it is not configured and will be skipped, and its total is displayed for correction

### Requirement: The screen SHALL trigger class-wide compute and report results

The modal MUST provide a **[Hitung Nilai]** action that computes frozen scores
for all valid subjects across every student in the class and reports how many
subjects were computed versus skipped. Compute MUST be explicit (not automatic
on grade edits).

#### Scenario: Compute reports computed and skipped counts

- **WHEN** the user clicks [Hitung Nilai] with some subjects valid and some not
- **THEN** the valid subjects are computed for all students and the result reports the computed and skipped subject counts

### Requirement: The approval board SHALL open per batch using the existing workflow

**[Buka]** MUST open the existing 5-status approval board scoped to the selected
batch. Per-card transitions and role gates MUST behave exactly as before
batching; only the card set is filtered to the batch.

#### Scenario: Opening a batch shows its cards on the workflow board

- **WHEN** the user clicks [Buka] on a batch
- **THEN** the approval board shows only that batch's cards, grouped by status, with the same per-card transition actions as before
