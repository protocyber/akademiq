## Why

Admins cannot see which evaluations each teacher has created and what report-type
weights they set without opening `/grading/entry` → "Kelola Evaluasi" for each
teacher × subject × class combination one at a time. There is no monitoring view
over the evaluation matrix across all teaching assignments.

## What Changes

- **Expandable evaluation matrix**: each row in `/teaching-assignments` gains an
  **[Expand]** control that reveals a read-only view of that assignment's
  evaluations and their per-report-type weights (the same grid as the Kelola
  Evaluasi `WeightMatrix`, minus the save controls).
- **Deep link to grade entry**: the expanded view includes an **"Atur di Entri
  Nilai"** link that routes to
  `/grading/entry?homeroom_id=<homeroom>&subject_id=<subject>` so the admin can
  jump straight to editing.
- **Lazy per-row fetch**: evaluations and weights are fetched only when a row is
  expanded (not eagerly for the whole page), avoiding an N+1 query storm.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `web-academic-ops-management`: the teaching-assignments table gains an
  expandable, read-only evaluation-and-weight matrix per row plus a deep link to
  grade entry.

## Impact

- **Frontend** (`apps/web`):
  - `src/components/features/academic-ops/teaching-assignments-screen.tsx` — add
    an expand state and a read-only variant of the `WeightMatrix` component
    (lifted/reused from `grading/entry/page.tsx`).
  - Reuse existing queries: `useEvaluations(homeroom, subject, year, term)` and
    `useReportFormulasForTypes` — no new endpoints.
- **Backend** (`apps/backend`): no changes.
- **Dependencies**: none added.
