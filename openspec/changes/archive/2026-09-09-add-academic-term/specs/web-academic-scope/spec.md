## MODIFIED Requirements

### Requirement: The global academic scope SHALL include a term dimension

The global academic-scope context (year + curriculum) MUST be extended to also
hold the currently selected `termId`. The scope MUST be persisted in
`localStorage` under the existing tenant-scoped key and exposed via the existing
React Context alongside `yearId` and `curriculumId`.

#### Scenario: Term is part of the persisted scope

- **WHEN** a user selects a year, a term, and a curriculum version in the header
- **THEN** the `localStorage` entry for that tenant contains all three ids and
  they are restored on reload

### Requirement: Selecting an academic year SHALL resolve a default term

When the year changes (or on initial load), the scope MUST resolve a default
`termId` by: (1) the term with `status = Active` for that year; else (2) the
term whose `[start_date, end_date]` contains today's date; else (3) the first
term of that year. If the selected year has no `Active` term, the UI MUST
surface a visible warning prompting the operator to activate a term.

#### Scenario: Default term is the active one

- **WHEN** a user selects a year that has one `Active` term
- **THEN** the term selector defaults to that `Active` term and no warning is
  shown

#### Scenario: Warning when no active term exists

- **WHEN** the selected year is `Active` but none of its terms is `Active`
- **THEN** the header shows a warning (e.g. "Tidak ada semester aktif") and the
  term selector defaults per the fallback rules above

### Requirement: The header SHALL expose a term selector

The header MUST render a term `<Select>` beside the academic-year picker, scoped
to the selected year. Changing the year MUST refresh the term options and reset
the term to the new year's default. The selector MUST be hidden or disabled when
the selected year has no terms (which, per backend invariant, should not occur,
but the UI must degrade gracefully).

#### Scenario: Changing year refreshes terms

- **WHEN** a user picks a different academic year in the header
- **THEN** the term selector is repopulated with that year's terms and the
  selected term is the default for the new year
