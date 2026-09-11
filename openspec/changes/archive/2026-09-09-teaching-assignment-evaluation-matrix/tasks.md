## 1. Reusable read-only matrix component

- [x] 1.1 Extract the weight-grid rendering from `WeightMatrix` (in `grading/entry/page.tsx`) into a shared presentational component that takes evaluations, report types, and a weights map
- [x] 1.2 Add a `readOnly` mode (or a separate component) that renders the grid with column totals and under-100% flags but no save buttons or local input state
- [x] 1.3 Verify the editable `WeightMatrix` in grade entry still works unchanged against the shared component

## 2. Expandable row in teaching-assignments

- [x] 2.1 Add an [Expand]/[Collapse] toggle to each row in `teaching-assignments-screen.tsx`
- [x] 2.2 Track expanded rows in component state (by assignment id)
- [x] 2.3 When a row is expanded, fetch `useEvaluations(homeroomId, subjectId, yearId, termId)` and `useReportTypes`/`useReportFormulasForTypes` lazily (only for expanded rows)
- [x] 2.4 Render the read-only matrix component in the expanded panel

## 3. Deep link to grade entry

- [x] 3.1 Add an "Atur di Entri Nilai" link in the expanded panel that routes to `/grading/entry?homeroom_id=<homeroom>&subject_id=<subject>`
- [x] 3.2 Handle empty states (no evaluations, no report types, or no active term) with guidance text

## 4. Verification

- [x] 4.1 Verify expanding a row shows the correct evaluations and weights with column totals
- [x] 4.2 Verify under-weighted report types are flagged
- [x] 4.3 Verify no evaluation requests fire on page load before expanding
- [x] 4.4 Verify the deep link opens grade entry pre-scoped to the assignment
- [x] 4.5 Run web lint and typecheck (typecheck passed; lint reported 0 errors and existing warnings)
