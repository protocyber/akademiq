## Context

The web app has 7 DataTable-based pages. `/settings/users` is the most
mature and was identified as the reference pattern. The other 6 pages
diverged organically as each was built independently.

### Current state — structural comparison

```
┌──────────────────────────────────────────────────────────────────────┐
│ STRUCTURAL DIVERGENCE ACROSS 7 PAGES                                 │
├───────────────┬──────────────┬──────────────┬───────────┬────────────┤
│ Page          │ Search loc   │ Bulk select  │ Bulk UI    │ Pagination │
├───────────────┼──────────────┼──────────────┼───────────┼────────────┤
│ users (REF)   │ CardContent  │ useSelect... │ Menu       │ URL-driven │
│ roles         │ CardHeader   │ manual       │ Bar        │ URL-driven │
│ years         │ CardHeader   │ manual       │ Bar        │ URL-driven │
│ class-tmpl    │ CardHeader   │ manual       │ inline div │ URL-driven │
│ subjects      │ CardHeader   │ manual/group │ inline div │ NONE       │
│ terms         │ CardHeader   │ NONE         │ NONE       │ URL-driven │
│ report-cards  │ no text      │ tanstack-blt │ Menu       │ client-side│
└───────────────┴──────────────┴──────────────┴───────────┴────────────┘
```

### The canonical pattern (from /settings/users)

```
┌─ Card ─────────────────────────────────────────────────┐
│ CardHeader                                              │
│   ┌─ Title ─┐  ┌─ Primary actions (Create, Invite) ─┐  │
│                                                           │
│ CardContent                                              │
│   ┌─ Toolbar row ─────────────────────────────────────┐ │
│   │ [☑ Select all] [BulkActionMenu]  [Search] [Filter]│ │
│   └─────────────────────────────────────────────────────┘ │
│   ┌─ DataTable ────────────────────────────────────────┐ │
│   │ checkbox │ col │ col │ ... │ actions               │ │
│   └──────────────────────────────────────────────────────┘ │
│   ┌─ Pagination ───────────────────────────────────────┐ │
│   │ Halaman X dari Y · prev / next                     │ │
│   └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

Key characteristics:
1. **Search in CardContent toolbar**, not CardHeader.
2. **`useSelectWithinPage`** for bulk selection (shared hook, only users uses it today).
3. **`BulkActionMenu`** (dropdown), not a bar.
4. **Facet filters** as `Select` dropdowns in the toolbar.
5. **URL-driven pagination** (where pagination exists).

## Goals / Non-Goals

**Goals:**
- All DataTable pages share ONE structural pattern: Card + toolbar + search +
  bulk-selection + DataTable + (optional) pagination.
- Bulk selection always uses `useSelectWithinPage`; no manual checkbox
  reimplementations.
- Search and filters always live in the CardContent toolbar, never the
  CardHeader.
- Remove pagination from years and terms (small lists).
- Reduce code duplication: extract shared layout primitives.

**Non-Goals:**
- Changing what data each page displays or its columns.
- Adding new features (new filters, new bulk actions) — only structuring
  what exists.
- Changing the `DataTable` primitive itself (`@/components/ui/data-table`).
- Redesigning the visual style (colors, spacing) — only the structural
  composition.
- Forcing pages that legitimately don't need a feature (e.g. terms has no
  bulk actions) to render empty placeholders. The pattern is a template, not
  a straightjacket: if a page doesn't need bulk selection, it omits that
  slot.

## Decisions

### Decision 1: Extract a `DataTableCard` layout component

A new composable component renders the canonical structure:

```tsx
<DataTableCard
  title="..."
  description="..."
  primaryActions={<Button>Create</Button>}
  search={{ value, onChange, placeholder }}
  filters={<><SelectFilter ... /></>}
  bulkActions={<BulkActionMenu ... />}
  selection={selection}  // from useSelectWithinPage
  table={tableInstance}
  pagination={paginationProps}  // optional
/>
```

Pages compose this instead of hand-rolling Card + CardHeader + CardContent +
toolbar each time. Slots that aren't needed are simply omitted.

*Alternative rejected:* a render-prop or HOC. Rejected — composition with
slots is more flexible and matches how shadcn/ui components work.

### Decision 2: Standardize on `useSelectWithinPage` everywhere

All pages with bulk selection migrate to `useSelectWithinPage`. The manual
checkbox-column implementations (roles, years, class-templates, subjects)
and the TanStack built-in approach (report-cards) are replaced. This means:

- The select-all checkbox moves from a custom column header to the toolbar
  (or the standard DataTable header if `useSelectWithinPage` supports it).
- `selectedIds` comes from the hook, not local state.

*Alternative rejected:* standardize on TanStack's built-in selection
everywhere. Rejected — `useSelectWithinPage` is already the most mature
abstraction and handles page-scoped selection edge cases.

### Decision 3: Pagination policy

- **Remove pagination** from `years` and `terms` (product request).
- **Keep URL-driven pagination** where it already exists (roles,
  class-templates) unless the dataset is demonstrably small.
- **report-cards**: evaluate during implementation — if the dataset is small
  enough, remove pagination; if not, migrate from client-side to URL-driven.

### Decision 4: Subjects page — flatten or keep grouped?

The `subjects` page uses nested Cards per subject-group. This is the most
divergent layout. Two options:

**Option A (flatten):** render all subjects in one DataTable with a
"kelompok" column and a group filter. This matches the canonical pattern
most closely but loses the visual grouping.

**Option B (keep grouped, standardize the outer chrome):** keep nested
Cards but standardize the search/filter/create placement in the outer Card.

**Decision: Option B (confirmed by user).** The grouping is meaningful
(subjects belong to kelompok mata pelajaran) and flattening would degrade
the UX. The standardization applies to the outer Card structure (search,
filter, create placement) and the inner per-group DataTable toolbar. The
nested-card layout is preserved.

## Risks / Trade-offs

- **[Risk] Large refactor surface** — 6 pages × ~500-1000 lines each.
  *Mitigation:* do it page-by-page, validate each against the reference, and
  keep the `DataTable` primitive untouched.
- **[Risk] Subjects page grouping change** — flattening would be a
  significant UX change. *Mitigation:* keep grouped layout (Decision 4,
  Option B); confirm with user.
- **[Risk] `useSelectWithinPage` may need extension** — it was built for the
  users page and may not cover all edge cases (e.g. grouped selection in
  subjects). *Mitigation:* extend the hook as needed; it's a shared lib.
- **[Trade-off] Migration introduces churn** — large diffs for cosmetic
  consistency. Accepted: the user explicitly asked for this standardization.

## Migration Plan

1. **Extract `DataTableCard` + `DataTableToolbar`** from the existing
   `/settings/users` structure.
2. **Refactor `/settings/users`** to use the new component (validate no
   regression — this is the baseline).
3. **Migrate pages one at a time**, simplest first:
   - terms (simplest: remove pagination, add standard toolbar)
   - roles (close to reference)
   - class-templates
   - years (remove pagination too)
   - report-cards
   - subjects (most complex — last)
4. **Validate each page** after migration: search works, filters work,
   bulk selection works, pagination (if present) works.

## Open Questions

- **Subjects page**: flatten (Option A) or keep grouped (Option B)? Lean:
  keep grouped. Needs user confirmation.
- **report-cards pagination**: keep client-side, migrate to URL-driven, or
  remove if dataset is small? Needs data-size check.
- Should the `BulkActionMenu` vs `BulkActionBar` be unified to one style?
  The reference uses a menu; lean: standardize on menu.
