## ADDED Requirements

### Requirement: The Kelola Evaluasi entry point SHALL be gated by grade.evaluation.manage

The `/grading/entry` screen MUST show the "Kelola Evaluasi" action only when the
signed-in user's access token carries the `grade.evaluation.manage` permission, in
addition to the existing conditions (write entitlement, a fully selected scope,
and — for non-admins — being an assigned teacher of the subject). When the user
lacks the permission, the action MUST NOT be rendered.

#### Scenario: Authorized user sees the action

- **WHEN** an assigned teacher whose token carries `grade.evaluation.manage` opens `/grading/entry` with a class and subject selected
- **THEN** the "Kelola Evaluasi" action is shown

#### Scenario: User without the permission does not see the action

- **WHEN** a user whose token does not carry `grade.evaluation.manage` opens `/grading/entry`
- **THEN** the "Kelola Evaluasi" action is not rendered

### Requirement: The grade-entry screen SHALL preserve URL filters across refresh

The `/grading/entry` screen MUST keep its `homeroom_id` and `subject_id` URL
query parameters when the browser is refreshed. It MUST clear those parameters
only on a genuine academic-year change — when the active year transitions from one
defined value to a different defined value — and MUST NOT clear them during the
initial hydration of the academic scope (an `undefined → value` transition).

#### Scenario: Refreshing keeps the selected class and subject

- **WHEN** the user reloads `/grading/entry?homeroom_id=...&subject_id=...`
- **THEN** the screen stays on that class and subject and does not redirect to bare `/grading/entry`

#### Scenario: Changing the academic year clears the filters

- **WHEN** the user changes the active academic year from one year to a different year
- **THEN** the `homeroom_id` and `subject_id` parameters are cleared

### Requirement: Deleting an evaluation SHALL NOT freeze the page

Deleting an evaluation from the Kelola Evaluasi modal MUST NOT leave the page in
an unclickable state. The delete-confirmation dialog and the Kelola Evaluasi
dialog MUST coexist without leaving a stale `pointer-events`/`aria-hidden` guard
on the document, whether the user confirms or cancels the deletion.

#### Scenario: Page stays interactive after canceling a delete

- **WHEN** the user clicks the delete (trash) action for an evaluation and then closes the confirmation without deleting
- **THEN** the page remains fully interactive and all controls respond to clicks

#### Scenario: Page stays interactive after confirming a delete

- **WHEN** the user confirms deletion of an evaluation
- **THEN** the delete request is sent, the dialogs close, and the page remains fully interactive

### Requirement: The grade-entry grid SHALL show a row-number column

The `/grading/entry` grid MUST render a leading row-number column showing the
1-based ordinal of each student row.

#### Scenario: Row numbers are shown

- **WHEN** the grid renders a roster of students
- **THEN** the first column shows sequential row numbers starting at 1
