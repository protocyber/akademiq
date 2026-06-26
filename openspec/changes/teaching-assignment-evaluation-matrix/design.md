## Context

The `/teaching-assignments` table (`teaching-assignments-screen.tsx`) is a flat
roster of teacher × subject × homeroom rows with a delete action. The evaluation
+ weight data for each assignment lives behind `/grading/entry`'s "Kelola
Evaluasi" modal, which renders a `WeightMatrix` (evaluations × report types).
There is no way for an admin to audit, across assignments, which evaluations
exist and whether weights sum to 100% without opening each assignment.

The existing `WeightMatrix` component (`grading/entry/page.tsx:1033`) already
fetches `useReportTypes` and `useReportFormulasForTypes` and renders the grid.
The evaluation list comes from `useEvaluations(homeroomId, subjectId, yearId,
termId)`. All three queries are keyed by the assignment's ids and already exist.

## Goals / Non-Goals

**Goals:**
- Let an admin monitor evaluations + weights per assignment without leaving
  `/teaching-assignments`.
- Provide a one-click deep link into grade entry for editing.
- Avoid eager-fetching evaluations for every row on the page.

**Non-Goals:**
- Editing evaluations or weights from the teaching-assignments page (read-only
  here; editing stays in `/grading/entry`).
- Changing the teaching-assignments table's filters, search, or pagination.
- Backend changes.

## Decisions

### D1: Read-only WeightMatrix variant, lifted from grade entry

Extract the matrix rendering from `WeightMatrix` into a reusable presentational
component (or a `readOnly` prop) that accepts evaluations + weights + report
types and renders the grid without save buttons or local state. The editable
`WeightMatrix` in `/grading/entry` and the read-only view here both use it.

*Alternative:* copy the table markup. Rejected — duplicates the grid and drifts.

### D2: Lazy fetch on expand

Evaluations (`useEvaluations`) and formulas (`useReportFormulasForTypes`) are
fetched only when a row's [Expand] is toggled on, keyed by that assignment's
`(homeroomId, subjectId, yearId, termId)`. TanStack Query dedupes and caches
per key, so re-expanding the same row is instant and overlapping assignments
that share keys reuse the cache.

*Alternative:* eager fetch for all page rows. Rejected — a page of 50 rows × 2
queries is a query storm for a view most rows will never be expanded.

### D3: Deep link to grade entry

The expanded panel shows an "Atur di Entri Nilai" link to
`/grading/entry?homeroom_id=<homeroom_id>&subject_id=<subject_id>`. The grade
entry page already parses these params (`parseGradingEntryParams`), so no change
is needed on the target page.

## Risks / Trade-offs

- **Many expanded rows** → each expanded row holds its own query. Acceptable:
  expansion is user-driven and queries are cached; the table is paginated.
- **Read-only drift from editable form** → mitigated by D1 (shared component).
- **Term ambiguity** → the matrix is term-scoped. The active term comes from
  `useAcademicScope`, matching how grade entry scopes evaluations. If no term is
  active, the panel shows an empty state with guidance.

## Migration Plan

Frontend-only. No backend or migration changes. Rollback is reverting the web
commit.
