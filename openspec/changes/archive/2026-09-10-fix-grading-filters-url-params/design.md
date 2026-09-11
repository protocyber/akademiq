## Context

The `teaching-assignments` page established the project's filter-URL-sync pattern: a typed params module (`teaching-assignments-params.ts`) with `parse`/`serialize`/defaults/query-key, and the screen reading params from `useSearchParams` and writing via `onParamsChange` → `router.replace`. Two grading pages do not follow it:

- `/grading/entry` (`page.tsx:85-86`): `homeroomId`/`subjectId` are plain `useState("")`, reset on year change but never written to or read from the URL. Refresh or back-button loses the selection.
- `/grading/report-cards` (`page.tsx:130-139`): seeds `useState` from `searchParams.get(...)` once on mount, then an effect writes changes back with `router.replace`. Because local state is the source of truth, it is not a clean round-trip: programmatic URL changes after mount do not re-seed, and the seed-then-effect is a partial, divergent implementation of the established pattern.

The global academic-year scope (`useAcademicScope` → `yearId`/`termId`/`curriculumId`) is a header-level selection and is intentionally not part of the per-page filter URL (the teaching-assignments page treats it the same way).

## Goals / Non-Goals

**Goals:**
- Make `/grading/entry` and `/grading/report-cards` filter selections live in the URL, using the existing parse/serialize pattern.
- Share the param-helper shape with `teaching-assignments-params.ts` for consistency.
- Keep selection across refresh, back/forward, and deep links.

**Non-Goals:**
- Moving the global academic-year scope into the URL (it stays a header selection).
- Changing the server-side filter API or pagination semantics.
- Adding filters that do not already exist on these pages.

## Decisions

### Decision 1: URL as single source of truth via parse/serialize
**Choice:** Both pages derive their filter state from `useSearchParams` via a parse helper, and every change calls `router.replace` with the serialized params — no `useState` mirror. This mirrors `teaching-assignments-screen.tsx` exactly.

**Rationale:** The established pattern is already proven and tested. The seed-into-`useState` + write-back-effect on `report-cards` is a divergent reimplementation that causes the round-trip gaps; replacing it with the canonical pattern removes the divergence rather than patching it.

**Alternatives considered:**
- *Keep `report-cards` seed+effect, just add URL to `entry`.* Leaves two patterns in the codebase for the same concern; future drift. Rejected.
- *Sync hook (`useUrlState`) abstracting the pattern.* Reasonable future refactor, but out of scope; mirroring the existing per-page helper is lower risk and matches what reviewers expect today.

### Decision 2: One params module per page (matching the precedent)
**Choice:** Add `grading-entry-params.ts` (`homeroom_id`, `subject_id`) and `report-cards-params.ts` (`report_type_id`, `homeroom_id`), each with type + defaults + parse + serialize + key helper, matching `teaching-assignments-params.ts`.

**Rationale:** The precedent is one module per filterable page. A single shared "grading filters" module would couple unrelated param sets; per-page modules keep each page's contract local and testable.

### Decision 3: Year-change resets selection through the URL, not local effect
**Choice:** `/grading/entry` currently resets `homeroomId`/`subjectId` via a `useEffect` on `yearId`. Under URL-as-source, the equivalent is to clear those params from the URL when the year changes (the `onParamsChange` path), preserving the existing UX (year change → class/subject cleared).

**Rationale:** Keeps the current behavior users expect (switching academic year resets the class/subject pick) while expressing it through the URL rather than a parallel local-state effect.

## Risks / Trade-offs

- **[Back/forward now changes filters — possibly surprising]** → Desired (it is the point), but verify the DataTable/grade-grid reacts to URL-driven param changes without stale state.
- **[Effect-ordering on report-cards migration]** → Removing the seed+effect in favor of pure URL derivation changes the render timing slightly; verify the generate-draft and selection logic still gates on `bothSelected` correctly.
- **[Deep links with stale ids]** → A bookmarked homeroom id from a prior year may no longer be valid; the existing "select a class" empty handling already covers a missing/invalid selection gracefully.

## Migration Plan

1. Add the two params modules with unit tests.
2. Refactor `/grading/entry` to URL-derived params; move the year-change reset into the param-change path.
3. Refactor `/grading/report-cards` from seed+effect to parse/serialize single-source.
4. Manually verify: refresh preserves selection; back/forward round-trips; deep links apply; year-change resets class/subject.
5. Frontend-only; no backend deploy or coordination.

## Open Questions

- Whether to also reflect the `/grading/report-cards` row-selection or tab state in the URL — likely no (transient), confirm during implementation.
