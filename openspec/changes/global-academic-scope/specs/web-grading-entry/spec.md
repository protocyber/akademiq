## ADDED Requirements

### Requirement: Grade entry SHALL use the global academic scope

The `/grading/entry` screen SHALL obtain the academic year and curriculum version from the
global academic scope instead of rendering its own year picker. The class and subject
selectors remain on the page, filtered by the scoped year/curriculum.

#### Scenario: Grade entry reflects the header scope

- **WHEN** the user opens `/grading/entry` with a year selected in the header
- **THEN** the grid uses that year (and its curriculum) without showing a separate year picker

#### Scenario: Grade entry shows an empty state without a scoped year

- **WHEN** no year is selected in the global scope
- **THEN** `/grading/entry` shows an empty state prompting the user to pick a year in the header
