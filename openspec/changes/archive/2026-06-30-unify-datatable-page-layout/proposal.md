## Why

Seven pages in the web app use `<DataTable>` but each implements its own
ad-hoc structure for the surrounding card, toolbar, search, filters, bulk
selection, and pagination. The divergence is wide:

- **Search** lives in the CardHeader on 5 pages, in a CardContent toolbar on
  `/settings/users` (the reference), and doesn't exist on `/report-cards`.
- **Bulk selection** has **three** different implementations: the shared
  `useSelectWithinPage` hook (users only), manual checkbox columns with local
  state (roles, years, class-templates, subjects), and TanStack's built-in
  `toggleAllPageRowsSelected` (report-cards).
- **Bulk action UI** is a dropdown `BulkActionMenu` on 2 pages, a bar-style
  `BulkActionBar` on 2 pages, and an inline `div` on 2 pages.
- **Pagination** is URL-driven on 5 pages, client-side `useState`+`slice()`
  on report-cards, and absent on subjects. Two specific pages (years, terms)
  have pagination that should be removed per product request.
- **Filters** exist only on users (role+status Selects) and report-cards
  (type+homeroom Selects).

This makes the codebase harder to maintain (every new page reinvents the
pattern), makes the UI inconsistent for users, and makes it difficult to
evolve features (e.g. adding a new bulk action requires touching N pages).

## What Changes

- **Establish `/settings/users` as the canonical pattern.** Its structure
  becomes the reference template: `Card > CardHeader(title + primary
  actions) > CardContent(toolbar: bulk-action menu + search + facet filters)
  > DataTable > pagination`. Bulk selection uses the shared
  `useSelectWithinPage` hook.
- **Migrate 6 pages to the canonical pattern:**
  - `/settings/roles`
  - `/settings/academic/years` (also: remove pagination)
  - `/settings/academic/terms` (also: remove pagination)
  - `/settings/academic/class-templates`
  - `/settings/academic/subjects` (largest divergence: grouped layout → flat)
  - `/grading/report-cards` (also: move from client-side to URL-driven
    pagination if pagination is retained)
- **Extract shared primitives** where the canonical pattern repeats:
  - `DataTableCard` (or `DataTablePageLayout`): a composable wrapper that
    renders the Card + toolbar scaffolding.
  - `DataTableToolbar`: the toolbar row (search + filter slots + bulk menu).
  - Standardize bulk selection to always use `useSelectWithinPage`.
- **Remove pagination** from `/settings/academic/years` and
  `/settings/academic/terms` (product request — these lists are small enough
  to render without pagination).

## Capabilities

### New Capabilities
- `web-datatable-layout`: a standardized, reusable page layout for
  DataTable-based pages, with a Card + toolbar + bulk-selection + search
  pattern derived from `/settings/users`.

### Modified Capabilities
- All 6 non-reference DataTable pages adopt the canonical layout.
- `useSelectWithinPage` becomes the sole bulk-selection mechanism.

## Impact

- **Web** (`apps/web`): significant refactoring of 6 page files; extraction
  of 1-2 new layout components; no backend changes.
- **Pages affected:** `settings/roles`, `settings/academic/years`,
  `settings/academic/terms`, `settings/academic/class-templates`,
  `settings/academic/subjects`, `grading/report-cards`.
- **New components:** `DataTableCard` / `DataTableToolbar` (or similar
  names, to be determined during implementation).
- **`/settings/academic/subjects`** is the highest-risk refactor: it
  currently uses a grouped nested-card layout. Flattening it changes the
  visual information architecture. This should be validated with the user
  before implementing.
- **`/grading/report-cards`** may keep its client-side pagination if the
  dataset is small; the standardization focuses on the Card/toolbar/
  selection structure, not forcing URL-driven pagination where it doesn't
  fit.
- **No backend changes.**
