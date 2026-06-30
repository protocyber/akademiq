# web-grading-entry Specification

## Purpose

Defines the grade-entry screen contract for teacher identity resolution, unmaterialized-assignment nudges, and weight-drift warnings.
## Requirements
### Requirement: The grade-entry screen SHALL resolve teacher identity without admin IAM endpoints

The `/grading/entry` screen MUST resolve the assigned teacher's display name and account-link status from the academic-ops teachers data it already loads, and MUST NOT call any tenant-admin-gated IAM endpoint (e.g. `GET /iam/tenants/me/users`). Linked account email/username MUST come from an academic-ops linked-user projection of the IAM user, not from the teacher biodata `teacher.email` field. Non-admin teachers MUST be able to use the screen without receiving a 403 from a user-directory lookup.

#### Scenario: Teacher info shows without an admin lookup

- **WHEN** a non-admin teacher opens `/grading/entry`
- **THEN** the assigned teacher's name and account status are shown from academic-ops data and no request is made to `/iam/tenants/me/users`

#### Scenario: No 403 for a non-admin

- **WHEN** a teacher who does not hold `user.read` loads the screen
- **THEN** no admin IAM request is issued and the screen loads without a permission error

#### Scenario: Linked teacher identity is shown from projected IAM data

- **WHEN** the grade-entry screen displays an assigned teacher with `user_id`
- **THEN** the account label uses `linked_user.email` or `linked_user.username`
- **AND** it does not use the teacher biodata `email` field to decide linked status

#### Scenario: Linked teacher without projected identity uses fallback label

- **WHEN** the grade-entry screen displays an assigned teacher with `user_id` but no `linked_user`
- **THEN** it shows a linked-account fallback label rather than `(akun belum terhubung)`

#### Scenario: Unlinked teacher shows unlinked label

- **WHEN** the grade-entry screen displays an assigned teacher with no `user_id`
- **THEN** it shows `(akun belum terhubung)`

### Requirement: The grade-entry screen SHALL surface unmaterialized-assignment and weight warnings

The screen MUST show a nudge when teaching assignments in the active term lack evaluations, using the grading service's unmaterialized-assignment count. The screen MUST show a non-blocking warning when a report type's subject weights no longer total 100% (e.g. after a teacher added an evaluation outside the template) or when no report type exists for the term. Neither condition blocks grade entry.

#### Scenario: Nudge appears when assignments lack evaluations

- **WHEN** the active term reports N assignments without evaluations
- **THEN** the screen shows a banner indicating N assignments have no evaluations

#### Scenario: Weight drift is warned, not blocked

- **WHEN** a report type's subject weights total other than 100%
- **THEN** the screen shows a warning and still allows grade entry

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

