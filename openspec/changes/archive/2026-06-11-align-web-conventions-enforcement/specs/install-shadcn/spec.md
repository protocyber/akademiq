## ADDED Requirements

### Requirement: Select primitive available
The system SHALL provide a shadcn/ui `Select` component under
`apps/web/src/components/ui/select.tsx`, so that all dropdown selection in
`src/app/`, `src/components/features/`, and `src/components/pages/` is
composed from the shadcn primitive rather than a native `<select>` element.

#### Scenario: Dropdown composed from shadcn Select
- **WHEN** a page or feature renders a selection dropdown
- **THEN** it imports `Select` (and its parts) from `@/components/ui/select`
- **AND** no native `<select>` element exists in `src/app/`,
  `src/components/features/`, or `src/components/pages/`
- **AND** `pnpm lint` reports zero `react/forbid-elements` violations for
  the `select` element

### Requirement: Textarea primitive available
The system SHALL provide a shadcn/ui `Textarea` component under
`apps/web/src/components/ui/textarea.tsx`, so that the
`react/forbid-elements` guidance referencing `<Textarea>` resolves to a real
installed primitive and multi-line input is composed from shadcn.

#### Scenario: ESLint guidance resolves to an installed component
- **WHEN** the `react/forbid-elements` rule blocks a native `<textarea>`
- **THEN** the suggested `@/components/ui/textarea` import exists and compiles
- **AND** `pnpm typecheck` succeeds with the new component present

### Requirement: Checkbox primitive available
The system SHALL provide a shadcn/ui `Checkbox` component under
`apps/web/src/components/ui/checkbox.tsx`, so that boolean toggles are composed
from the shadcn primitive rather than a native `<input type="checkbox">`.

#### Scenario: Checkbox composed from shadcn Checkbox
- **WHEN** a page renders a boolean toggle (e.g. the login "remember device" control)
- **THEN** it uses `Checkbox` from `@/components/ui/checkbox` with a shadcn `Label`
- **AND** no native `<input type="checkbox">` exists in `src/app/`,
  `src/components/features/`, or `src/components/pages/`

### Requirement: DatePicker primitive available
The system SHALL provide a shadcn/ui `DatePicker` (Popover + Calendar) under
`apps/web/src/components/ui/`, so that date selection is composed from the
shadcn primitive rather than a native `<input type="date">`. The DatePicker
SHALL accept and emit the form value as a `YYYY-MM-DD` string, converting to
and from `Date` internally.

#### Scenario: Date selected through shadcn DatePicker
- **WHEN** a user picks a date on a form that stores a `z.string()` date field
- **THEN** the value submitted to the mutation is a `YYYY-MM-DD` string
- **AND** no `<input type="date">` exists in `src/app/`,
  `src/components/features/`, or `src/components/pages/`
- **AND** the form schema's date field type is unchanged

### Requirement: Query-bound selects indicate loading
A select whose options are populated from a TanStack Query SHALL surface the
query's loading and empty states through a single shared wrapper, so the
behavior is not re-implemented per call site.

#### Scenario: Select shows a spinner while its query loads
- **WHEN** the backing query `isLoading` is true
- **THEN** the select trigger renders a circular `<Spinner size="sm" />` and is disabled

#### Scenario: Select shows an empty state when the query returns no rows
- **WHEN** the backing query has resolved with an empty result set
- **THEN** the select trigger shows an empty-state label and is disabled

#### Scenario: Select is interactive once data is present
- **WHEN** the backing query has resolved with one or more rows
- **THEN** the select is enabled and renders the rows as options
