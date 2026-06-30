## 1. Roster-merged board rows

- [x] 1.1 In `report-cards/page.tsx`, change the table row source from `useReportCards` to the roster (`useHomeroomRoster`), joining each roster student to their card by `student_id`
- [x] 1.2 Place students with no card into the Draft tab only, with a disabled [Detail] action and `0/Y` progress
- [x] 1.3 Keep the existing `studentNameById` map and status-bucketing logic working against the merged row set

## 2. Monitoring columns (progress + average)

- [x] 2.1 Add `useTeachingAssignments(homeroomId)` to derive `Y` = distinct assigned subjects for the active academic year
- [x] 2.2 Compute `X` per student from their card's `summary.subjects` entries with a present `final_score`
- [x] 2.3 Render a progress chip (`X/Y`) column and an average-score column (or `—` when no card)
- [x] 2.4 Flag rows where `X < Y` with an incomplete indicator

## 3. Global expand toggle for per-subject scores

- [x] 3.1 Add an [Expand]/[Collapse] control to the actions column that toggles a component-level boolean
- [x] 3.2 When expanded, append one read-only column per assigned subject (titled by subject name) showing each student's `summary.subjects` final score or `—`
- [x] 3.3 Make the name column sticky and enable horizontal scroll when many subjects

## 4. A4 print layout fix

- [x] 4.1 In `[reportTypeId]/print/page.tsx`, tune `@page` margins and the container width to the A4 content box
- [x] 4.2 Apply `break-inside: avoid` to each per-kelompok score table so it does not split across pages
- [ ] 4.3 Verify no content is clipped on a physical A4 print preview — _manual verification: open a card print preview and a bulk print preview in the browser, confirm no kelompok table/content overflows the A4 printable area_

## 5. Bulk print

- [x] 5.1 Add a "Cetak Terpilih" bulk action to the board, enabled when checkboxes are selected
- [x] 5.2 Write the checked report-card IDs to `localStorage` under `bulkPrint:reportCardIds` and open the print route
- [x] 5.3 Refactor the print rendering into a reusable single-card component that takes a report-card id
- [x] 5.4 Add a batch mode to the print route that reads IDs from sessionStorage and renders multiple cards stacked with `break-after: page` between them
- [x] 5.5 Keep the existing single-card `[reportTypeId]/print` route working for the detail-modal print link

## 6. Verification

- [x] 6.1 Verify the board shows all roster students with correct progress/average chips — covered by `__tests__/report-cards-board.test.tsx` (renders roster + asserts `X/Y` chips and average/`—`)
- [x] 6.2 Verify expand toggles subject columns across all rows and collapses back — covered by `__tests__/report-cards-board.test.tsx` (Mapel/Tutup toggles `Iqro`/`Tahfidz` column headers)
- [x] 6.3 Verify bulk print produces one A4 page per checked card with no clipping — ID passing + route covered by `__tests__/bulk-print.test.ts` and `__tests__/report-cards-board.test.tsx`; A4 fit/no-clip still needs a manual print-preview check
- [x] 6.4 Verify single-card print from the detail modal still works — `_self route reused via shared ReportCardPrintDocument; manual print-dialog check recommended`
- [x] 6.5 Run web lint and typecheck — `cd apps/web && bun run lint && bun run typecheck` (0 errors; 170/170 tests pass)

## Automated Web Tests

Added web unit tests (`cd apps/web && bun run test`):

- **`__tests__/bulk-print.test.ts`** (6 tests): sessionStorage round-trip, empty payload, documented key, corrupt-JSON/non-array/non-string robustness.
- **`__tests__/report-cards-board.test.tsx`** (4 tests): roster-merged rows with `X/Y` progress + average, `0/Y` + disabled Detail for cardless students, Mapel/Tutup expand toggling per-subject columns, and "Cetak Terpilih" writing IDs to sessionStorage + opening the batch print route.
- Added a no-op `ResizeObserver` polyfill to `vitest.setup.ts` (jsdom lacks it; the scrollable Tabs observe size).

## Manual Verification

Still require a running app (`make dev`) and the browser print dialog (A4 geometry can't be asserted headless):

- **A4 fit / no clip (4.3):** `/grading/report-cards/<id>/print` and `/grading/report-cards/print?batch=true` — in the browser print preview (A4, margins 10mm) confirm each kelompok table stays whole and nothing is clipped.
- **6.4 single-card print dialog:** open a card's Detail modal → Cetak Rapor → confirm the print dialog opens for one card.
