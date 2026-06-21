# Tasks: unify-datatable-page-layout

Web submodule `apps/web`. No backend changes.

## 1. Extract shared layout primitives

- [x] 1.1 Extract `DataTableCard` (or `DataTablePageLayout`) from the
      existing `/settings/users` structure. Slots: title, description,
      primaryActions, toolbar (search + filters + bulk menu), table,
      pagination (optional).
- [x] 1.2 Extract `DataTableToolbar` (the CardContent toolbar row: select-all
      checkbox, BulkActionMenu, search input, filter slot).
- [x] 1.3 Ensure `useSelectWithinPage` supports all patterns needed across
      pages (extend if needed for grouped/nested cases).
- [x] 1.4 Document the canonical pattern in `apps/web/CONVENTIONS.md`.

## 2. Refactor reference page

- [x] 2.1 Refactor `/settings/users` to use the new `DataTableCard`.
- [x] 2.2 Verify no regression: search, role/status filters, bulk selection,
      bulk actions, export, pagination all work.

## 3. Migrate pages (simplest first)

### 3a. terms (remove pagination + standardize)
- [x] 3a.1 Remove pagination from `/settings/academic/terms`.
- [x] 3a.2 Migrate to `DataTableCard` + standard toolbar placement.

### 3b. roles
- [x] 3b.1 Migrate `/settings/roles` to `DataTableCard`.
- [x] 3b.2 Replace manual checkbox column with `useSelectWithinPage`.
- [x] 3b.3 Replace `BulkActionBar` with `BulkActionMenu`.
- [x] 3b.4 Move search from CardHeader to CardContent toolbar.

### 3c. class-templates
- [x] 3c.1 Migrate `/settings/academic/class-templates` to `DataTableCard`.
- [x] 3c.2 Replace manual checkbox + inline div bulk bar with
      `useSelectWithinPage` + `BulkActionMenu`.
- [x] 3c.3 Move search to CardContent toolbar.

### 3d. years (remove pagination + standardize)
- [x] 3d.1 Remove pagination from `/settings/academic/years`.
- [x] 3d.2 Migrate to `DataTableCard` + standard toolbar.
- [x] 3d.3 Replace manual checkbox column with `useSelectWithinPage`.
- [x] 3d.4 Replace `BulkActionBar` with `BulkActionMenu`.

### 3e. report-cards
- [x] 3e.1 Evaluate dataset size: keep client-side pagination, migrate to
      URL-driven, or remove.
- [x] 3e.2 Migrate `/grading/report-cards` to `DataTableCard` + standard
      toolbar.
- [x] 3e.3 Replace TanStack built-in selection with `useSelectWithinPage`.
- [x] 3e.4 Standardize filter Selects placement in CardContent toolbar.

### 3f. subjects (keep grouped layout — Option B confirmed)
- [x] 3f.1 Standardize the outer Card structure (search/filter/create
      placement in CardContent toolbar, not CardHeader).
- [x] 3f.2 Standardize inner per-group toolbar: replace manual/grouped
      checkbox selection with `useSelectWithinPage` (adapt for grouped
      selection if needed).
- [x] 3f.3 Keep nested Cards per subject group (Option B — confirmed).

## 4. Verification

- [x] 4.1 `make test` (web) green; lint + typecheck pass.
- [ ] 4.2 Visual pass: every DataTable page matches the canonical structure
      (Card header has title + actions only; toolbar has search + filters +
      bulk menu; pagination where applicable).
- [ ] 4.3 Functional pass: search, filters, bulk selection, bulk actions,
      pagination all work on every migrated page.
