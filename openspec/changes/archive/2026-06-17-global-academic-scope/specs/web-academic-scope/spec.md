## ADDED Requirements

### Requirement: The header SHALL provide a global academic-scope selector

The console header SHALL render an academic-year selector and, beside it, a
curriculum-version selector. The curriculum options SHALL be the curriculum versions of the
currently selected year (curriculum depends on year); changing the year SHALL refresh the
curriculum options and reset the curriculum selection to that year's newest version.

#### Scenario: Curriculum options follow the selected year

- **WHEN** the user changes the academic-year selector to a different year
- **THEN** the curriculum selector lists that year's curriculum versions and selects its newest one

### Requirement: The scope SHALL default to the Active year and newest curriculum

On first load (no stored scope), the global scope SHALL default the year to the tenant's
`Active` academic year and the curriculum to the newest curriculum version of that year.

#### Scenario: Active year is preselected

- **WHEN** a user with an `Active` year opens the console for the first time
- **THEN** the header shows that `Active` year selected and its newest curriculum version

### Requirement: An absent Active year SHALL leave the scope empty and prompt selection

When there is no `Active` academic year, the global scope SHALL be empty and the header
SHALL prompt the user to choose a year. Pages that require a year SHALL show an empty state
until a year is selected.

#### Scenario: No active year prompts selection

- **WHEN** the tenant has no `Active` year and the user opens a page that needs a year
- **THEN** the header prompts to pick a year and the page shows an empty state instead of data

### Requirement: The scope SHALL persist across reloads via localStorage

The selected academic scope (year id and curriculum version id) SHALL be persisted in
`localStorage` and restored on reload, then exposed through a React Context consumed by all
pages.

#### Scenario: Scope survives a reload

- **WHEN** the user selects a year and curriculum, then reloads the page
- **THEN** the same year and curriculum are restored from `localStorage`

### Requirement: Pages SHALL read year and curriculum from the global scope

Pages and forms that need an academic year or curriculum version SHALL read them from the
global scope and SHALL NOT render their own year/curriculum selectors.

#### Scenario: No page-level year picker remains

- **WHEN** the user navigates to grade entry, the report board, or teaching assignments
- **THEN** none of these pages renders its own academic-year (or curriculum) selector; they use the header scope
