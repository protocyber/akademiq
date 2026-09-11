## Why

Filter selections on the grading pages are not reliably reflected in the URL, so they cannot be shared, bookmarked, or restored with the back button. `/grading/entry` keeps its class and subject selections in local `useState` with no URL params at all (selections vanish on refresh or navigation). `/grading/report-cards` seeds from the URL once into local state and writes changes back via an effect, but local state remains the source of truth — back/forward and deep links do not round-trip cleanly. The `teaching-assignments` page already implements the correct pattern (`parseTeachingAssignmentsParams`/`serializeTeachingAssignmentsParams` + `router.replace`), and these two grading pages should adopt it.

## What Changes

- **`/grading/entry` filters move to URL params.** The homeroom and subject selections MUST be read from and written to URL search params (`homeroom_id`, `subject_id`) using the established parse/serialize + `router.replace` pattern, so the selection is shareable, bookmarkable, and survives refresh/back. *(Frontend.)*
- **`/grading/report-cards` filters become URL-as-source-of-truth.** The report-type and class selections MUST use the parse/serialize pattern (replacing the seed-into-`useState` + write-back-effect approach), so the URL is the single source of truth and back/forward navigation round-trips correctly. *(Frontend.)*
- **Shared param helpers.** Add `lib/schemas/grading-entry-params.ts` and `lib/schemas/report-cards-params.ts` (or a shared `grading-filters-params` module) following the `teaching-assignments-params.ts` shape: typed params, defaults, parse, serialize, and a query-key helper. *(Frontend.)*

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `web-grading-entry`: class and subject filter selections are reflected in URL search params (shareable/bookmarkable/back-button-restorable)

## Impact

- **Frontend (`apps/web`)**: `app/grading/entry/page.tsx` (replace local `useState` for homeroom/subject with URL-derived params + `onParamsChange` via `router.replace`); `app/grading/report-cards/page.tsx` (replace seed+effect with parse/serialize single-source); new `lib/schemas/grading-entry-params.ts` and `lib/schemas/report-cards-params.ts`.
- **No backend changes.** No data or API impact.
- **Pattern reference**: `teaching-assignments-params.ts` and `teaching-assignments-screen.tsx` (`onParamsChange` → `router.replace`) are the established shape to mirror.
- **Tests**: unit tests for the new parse/serialize helpers (like `teaching-assignments-params` coverage); optionally a page test asserting URL reflects a filter change.
- **Note**: the academic-year context (`useAcademicScope`) stays out of the URL (it is a global header selection, not a page filter), consistent with the teaching-assignments page.
