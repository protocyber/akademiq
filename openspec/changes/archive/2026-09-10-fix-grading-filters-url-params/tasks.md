## 1. Shared param helpers
- [x] 1.1 Create `lib/schemas/grading-entry-params.ts` with type `{ homeroom_id?, subject_id? }`, defaults, `parseGradingEntryParams`, `serializeGradingEntryParams`, and a query-key helper — mirroring `teaching-assignments-params.ts`
- [x] 1.2 Create `lib/schemas/report-cards-params.ts` with type `{ report_type_id?, homeroom_id? }`, defaults, parse, serialize, and key helper
- [x] 1.3 Add unit tests for both parse/serialize modules (round-trip, defaults, omitted fields)

## 2. Refactor /grading/entry to URL params
- [x] 2.1 Replace `homeroomId`/`subjectId` local `useState` in `GradeEntryPanel` with params derived from `useSearchParams` via `parseGradingEntryParams`
- [x] 2.2 Add `onParamsChange` that serializes and calls `router.replace(`/grading/entry?${query}`, { scroll: false })`
- [x] 2.3 Move the year-change reset: when `yearId` changes, clear `homeroom_id`/`subject_id` via the param-change path (replace the existing `useEffect` that set local state to "")
- [x] 2.4 Verify `changeHomeroom` still clears subject and writes both through the URL

## 3. Refactor /grading/report-cards to URL-as-source
- [x] 3.1 Replace the seed-from-`searchParams`-into-`useState` + write-back `useEffect` with params derived directly from `useSearchParams` via `parseReportCardsParams`
- [x] 3.2 Route report-type and class changes through `onParamsChange` → `router.replace`
- [x] 3.3 Confirm `bothSelected` gating and `GenerateDraftButton` still key off the URL-derived ids

## 4. Verification
- [x] 4.1 `/grading/entry`: refresh preserves class+subject; deep link applies them; back/forward round-trips; year change clears them
- [x] 4.2 `/grading/report-cards`: refresh, deep link, and back/forward all round-trip the report-type+class selection
- [x] 4.3 Run web lint/typecheck and the unit tests for the new param modules
