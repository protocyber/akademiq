## Why

The per-class report-card board (`/grading/report-cards`) only lists students who
already have a generated `ReportCard`, so a homeroom teacher cannot see at a
glance which subjects still have missing grades — they must open
`/grading/entry` repeatedly. The A4 print page also has margin/alignment and
content-overflow issues, and there is no way to print multiple report cards in
one operation.

## What Changes

- **Roster-aware board**: the per-class board table MUST show every student in
  the homeroom roster, including those without a generated card. Students
  without a card appear in the **Draft** tab with a `0/Y` progress chip.
- **Monitoring columns**: each row gains a **progress chip** (`X/Y`, where `Y`
  is the count of distinct subjects assigned to the homeroom+year and `X` is the
  number of those subjects that have a frozen report score) and an **average
  score** column. A `⚠` flag marks incomplete rows.
- **Expand global subject columns**: an **[Expand]** toggle in the actions
  column widens the table to the right with one read-only column per assigned
  subject, showing each student's final score (or `—` when missing). This is a
  global table toggle, not a per-row sub-table.
- **A4 print layout fix**: fix `@page` margins, container grid alignment, and
  inter-kelompok table page-break behaviour so a report card fits a physical A4
  page without content being clipped.
- **Bulk print**: add a **"Cetak Terpilih"** bulk action that prints all checked
  report cards as a single document, one card per A4 page separated by CSS
  page breaks. The checked IDs are handed off to the print route via
  `localStorage` (shared across the board and print tabs). The print route is
  refactored to render a list of cards.

## Capabilities

### New Capabilities
<!-- None — all changes extend the existing web-report-cards capability. -->

### Modified Capabilities
- `web-report-cards`: the per-class board gains roster-merged rows, monitoring
  columns (progress + average), and an expand toggle for per-subject final
  scores; the print route gains multi-card bulk printing and A4 layout fixes.

## Impact

- **Frontend** (`apps/web`):
  - `src/app/grading/report-cards/page.tsx` — merge `useHomeroomRoster` into the
    table rows (currently used only as a name-lookup map); add progress, average,
    and expand columns; add `useTeachingAssignments(homeroomId)` to derive `Y`.
  - `src/app/grading/report-cards/[reportTypeId]/print/page.tsx` — refactor from
    single-card render to a list-of-cards render with `page-break-after`; fix
    `@page` margins and container alignment.
- Selection passing for bulk print: checked report-card IDs are passed to the
  print route via `localStorage` (robust for long UUID lists and shared across
  the board tab and the newly opened print tab), read by a `?batch=true` mode
  of the print route.
- **Backend** (`apps/backend`): no API changes expected — all data
  (`ReportCard.summary.subjects`, roster, teaching assignments) is already
  served by existing endpoints. No migrations, no new routes.
- **Dependencies**: none added.
