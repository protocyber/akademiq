## ADDED Requirements

### Requirement: The Tambah Penugasan dialog dropdowns SHALL not be clipped

The multi-select dropdowns in the "Tambah Penugasan" dialog (teacher, subject, homeroom selectors) SHALL render their option popover fully visible, not clipped by the dialog's scroll/overflow container. The popover MUST render via a Portal
so it escapes the dialog's `overflow` bounds, while preserving keyboard focus and
typing in the embedded search input (the behavior the Portal was previously
removed to protect).

#### Scenario: Opening a multi-select shows all options

- **WHEN** an admin opens the teacher, subject, or homeroom multi-select inside the Tambah Penugasan dialog
- **THEN** the option list is fully visible and not cut off by the dialog edges

#### Scenario: Search input remains usable

- **WHEN** the multi-select popover is open inside the dialog
- **THEN** the user can focus the search field and type to filter options
