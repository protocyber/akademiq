## ADDED Requirements

### Requirement: The app SHALL provide a reusable DataTable page layout component

The web app MUST provide a composable layout component (e.g.
`DataTableCard`) that encapsulates the canonical pattern: a `Card` with a
`CardHeader` (title, description, primary actions) and a `CardContent`
containing a toolbar row (bulk-action menu, search input, filter slots),
the `DataTable`, and an optional pagination row. Pages compose this
component by passing slot props rather than hand-rolling the Card structure.

#### Scenario: Page uses the canonical layout

- **WHEN** any DataTable-based page is rendered
- **THEN** the page composes `DataTableCard` (or an equivalent shared
  layout) rather than manually assembling Card + CardHeader + CardContent +
  toolbar

### Requirement: Bulk selection SHALL use the shared page-scoped hook

All pages that support bulk row selection MUST use the
`useSelectWithinPage` hook (or its successor) for selection state.
Ad-hoc manual checkbox columns with local `rowSelection` state and raw
TanStack `toggleAllPageRowsSelected` calls MUST NOT be used.

#### Scenario: Bulk selection is consistent

- **WHEN** a user selects rows on any DataTable page that supports bulk
  actions
- **THEN** the selection behavior (select-all, indeterminate state,
  selected-ids tracking) is provided by `useSelectWithinPage` and behaves
  identically across pages

### Requirement: Search and filters SHALL live in the CardContent toolbar

The search input and any facet filter controls MUST be rendered in the
`CardContent` toolbar row, NOT in the `CardHeader`. The `CardHeader` MUST
contain only the title, description, and primary action buttons (Create,
Invite, etc.).

#### Scenario: Toolbar placement is consistent

- **WHEN** any DataTable page is rendered
- **THEN** the search input and filters appear in a toolbar row inside
  CardContent, below the CardHeader

## MODIFIED Requirements

### Requirement: The academic years and terms pages SHALL NOT paginate

The `/settings/academic/years` and `/settings/academic/terms` pages MUST
render all rows without pagination controls. The full list is displayed in
the DataTable.

#### Scenario: Years page has no pagination

- **WHEN** a user views `/settings/academic/years`
- **THEN** all academic years are rendered; no "Halaman X dari Y" or
  prev/next controls appear

#### Scenario: Terms page has no pagination

- **WHEN** a user views `/settings/academic/terms`
- **THEN** all terms for the selected year are rendered; no pagination
  controls appear
