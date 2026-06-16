## Why

The academic year (and, for some pages, the curriculum version) is selected separately on
every page that needs it: grade entry has its own year picker, the report board has another,
teaching assignments keeps it in a URL param, and so on. Users must re-pick the same context
repeatedly, and the pickers drift out of sync between pages. There is no single source of
truth for "which academic year am I working in". This change introduces one global academic
scope (year + curriculum) chosen once in the header and consumed everywhere.

## What Changes

- Add a global academic-scope selector to the console header: an academic-year picker and,
  beside it, a curriculum-version picker. The curriculum list depends on the selected year
  (curriculum versions are fetched per year), so changing the year refreshes the curriculum
  options.
- Default the year to the tenant's `Active` year and the curriculum to the newest version of
  that year. If there is no `Active` year, leave the scope empty and prompt the user to pick
  one; pages that need a year show an empty state until a year is chosen.
- Persist the selected scope in `localStorage` and expose it via a React Context so all pages
  read the same value across reloads.
- **BREAKING (UX)** Remove the per-page academic-year and curriculum-version selectors from
  every page and form; those pages read the year/curriculum from the global scope instead.

## Capabilities

### New Capabilities
- `web-academic-scope`: The global academic-scope context (year + curriculum), its header
  selectors, default-resolution and empty-state rules, `localStorage` persistence, and the
  removal of per-page selectors in favor of the shared scope.

### Modified Capabilities
- `web-grading-entry`: The grade-entry screen reads the year (and curriculum) from the global
  scope instead of its own pickers.
- `web-report-cards`: The report board reads the year from the global scope instead of its own
  year selector.
- `web-academic-ops-management`: Screens that filter by academic year (e.g. teaching
  assignments, homerooms) read the year from the global scope instead of a local/URL picker.

## Impact

- **apps/web**: new `AcademicScopeProvider` (Context + `localStorage`), header selector
  components, and a `useAcademicScope()` hook. Edits across grade entry, report board,
  teaching assignments, homerooms, and any other page with a year/curriculum picker to consume
  the scope and drop local pickers.
- **Data**: relies on existing queries `useAcademicYears`, `useCurriculumVersions(yearId)`; no
  backend changes.
- **Interplay**: complements `rbac-read-and-menu-restructure` (the header gains the scope
  selector alongside the restructured nav) but is independent of it.
