## ADDED Requirements

### Requirement: Console content SHALL be full-width

Console pages SHALL use a consistent full-width content layout matching the `/users` page,
rather than per-page max-width caps (e.g. `max-w-6xl`, `max-w-7xl`).

#### Scenario: Pages render full-width

- **WHEN** the user opens the academic, grading, and settings pages
- **THEN** their content spans the same full width as the `/users` page

### Requirement: A date picker inside a modal SHALL NOT be clipped

A date picker opened within a modal/dialog SHALL render its calendar popover fully visible,
without being cut off by the modal edge, using proper portaling and collision handling.

#### Scenario: Calendar opens fully inside a modal

- **WHEN** the user opens a date picker that lives inside a modal
- **THEN** the calendar popover is fully visible and not clipped by the modal boundary

### Requirement: Confirmations SHALL use dialog components, not native confirm/alert

The web app SHALL NOT use native `window.confirm` or `window.alert` for confirmations; it
SHALL use the existing `ConfirmDialog`/dialog components. If a needed variant does not exist,
a reusable component SHALL be added under `components/`.

#### Scenario: No native confirm/alert remains

- **WHEN** the codebase is scanned for `window.confirm`/`window.alert`
- **THEN** no occurrences are used for user-facing confirmation flows
