## ADDED Requirements

### Requirement: The grade-entry screen SHALL present grades as an evaluation-column grid

The `/grading/entry` screen MUST let the user pick Tahun, Kelas, and Mapel, then
render a grid whose rows are the class roster and whose columns are the
evaluations defined for that class+subject+year, in `position` order. Each cell
holds one student's score for one evaluation.

#### Scenario: Columns reflect the class+subject evaluations

- **WHEN** the user has selected a year, class, and subject that has evaluations UH1, UH2, UTS
- **THEN** the grid shows one column per evaluation in order, and each roster row shows that student's score per column (blank when unrecorded)

#### Scenario: No evaluations yet

- **WHEN** the selected class+subject has no evaluations defined
- **THEN** the grid shows an empty-columns hint prompting the user to add an evaluation, and no score cells are editable

### Requirement: Grade cells SHALL auto-save inline without an Update button

Each score cell MUST save on its own — on blur or debounced change — when the
value is valid (0–100) and differs from the stored value. There MUST be no
per-row or per-cell Update button. Each cell MUST show its own status: idle,
saving, saved, or error. On error the entered value is retained with a retry
affordance; invalid input is shown inline and does not trigger a save.

#### Scenario: Editing a cell saves automatically

- **WHEN** the user types a valid score into a cell and moves focus away
- **THEN** the cell shows a saving then saved status and the grade is persisted for that `(student, evaluation)` without any button press

#### Scenario: Invalid score is not saved

- **WHEN** the user enters a value outside 0–100 or non-numeric
- **THEN** the cell shows an inline validation state and no save request is sent

#### Scenario: Save failure is recoverable

- **WHEN** a cell's save request fails
- **THEN** the cell shows an error status, keeps the entered value, and offers a retry

### Requirement: The screen SHALL manage evaluations via a modal gated on class+subject selection

A **[Kelola Evaluasi]** control MUST appear only after both a class and a
subject are selected. It MUST open a modal that lists the evaluations for that
class+subject+year in a small table and supports add, edit, delete, and reorder.
Changes MUST be reflected in the grid columns on close.

#### Scenario: Manage button is hidden until class and subject are chosen

- **WHEN** the user has not yet selected both a class and a subject
- **THEN** the [Kelola Evaluasi] control is not shown

#### Scenario: Adding an evaluation adds a grid column

- **WHEN** the user adds an evaluation in the modal and closes it
- **THEN** the grid shows a new column for that evaluation in its `position` order

#### Scenario: Deleting an evaluation warns about grade loss

- **WHEN** the user deletes an evaluation that has recorded grades
- **THEN** the modal confirms the deletion will remove those grades before proceeding
