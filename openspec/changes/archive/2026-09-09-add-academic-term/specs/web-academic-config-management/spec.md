## ADDED Requirements

### Requirement: Operators SHALL manage academic terms per year

The web console MUST provide a term-management surface scoped to an academic
year (as a section/sub-page of the year management area) that lists the year's
terms and allows creating, editing, and deleting a term, and transitioning a
term's status. Term status transitions MUST reuse the confirmation UX pattern
(type-to-confirm + cooldown for backward/`→ Archived` transitions) established
for academic-year transitions.

#### Scenario: Create a term

- **WHEN** a tenant admin opens a year and creates a term "Semester 2" with
  dates within the year
- **THEN** the term appears in the list with status `Draft`

#### Scenario: Transition a term with confirmation

- **WHEN** a tenant admin transitions a term from `Active` back to `Draft`
- **THEN** a type-to-confirm dialog with a 5-second cooldown is shown before the
  request is sent

### Requirement: Deleting a term SHALL be guarded

Deleting a term MUST be rejected by the backend when the term is referenced by
evaluations, report types, or grades (the UI surfaces the resulting error). The
UI MUST confirm a delete with the operator before issuing the request.

#### Scenario: Delete a term with dependent data shows an error

- **WHEN** a tenant admin attempts to delete a term that has evaluations and
  confirms the dialog
- **THEN** the UI surfaces the backend error (e.g. `TERM_IN_USE`) and the term
  is not removed

### Requirement: The UI SHALL warn when an active year has no active term

The web console MUST show a visible warning in the year/term management area when
the selected academic year is `Active` but none of its terms is `Active`,
prompting the operator to activate a term. This warning MUST be consistent with
the header warning specified in `web-academic-scope`.

#### Scenario: Warning is shown on the management page

- **GIVEN** the selected year is `Active` and all its terms are `Draft`
- **WHEN** the tenant admin opens the term management area
- **THEN** a warning is displayed prompting term activation

### Requirement: Academic-config management pages SHALL respect read permission

The web console MUST gate every academic-config management page — years,
curriculum, subjects, class templates, and the new term-management surface — on
`academic.config.read` (introduced by `rbac-read-and-menu-restructure`) for
viewing, and on `academic.config.write` for create/edit/delete/status
transitions.

#### Scenario: Term management is visible to readers

- **WHEN** a role holding `academic.config.read` opens the academic-config area
- **THEN** the term-management surface is visible; create/edit/delete/status
  controls are disabled unless the role also holds `academic.config.write`
