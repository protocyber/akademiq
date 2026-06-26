## Context

The per-class report-card board (`/grading/report-cards`) currently builds its
table rows from `useReportCards(reportTypeId, homeroomId)` alone. The homeroom
roster is fetched (`useHomeroomRoster`) but used only as a name-lookup map, so
students without a generated `ReportCard` are invisible in every status tab.
There is no per-subject score visibility on the board, and the A4 print route
renders exactly one card with hardcoded `@page` margins that clip content.
Printing is single-card only.

The existing `web-report-cards` spec already defines the per-class board with
status tabs, multiselect checkboxes, and a detail modal, plus the single-card
print route. This change extends those without altering the backend contract:
`ReportCard.summary.subjects` already carries `[{subject_id, final_score,
passed}]`, the roster endpoint exists, and `useTeachingAssignments(homeroomId)`
exists.

## Goals / Non-Goals

**Goals:**
- Surface roster completeness (missing grades / missing cards) on the board
  without leaving the page.
- Add per-subject final scores as an expandable view on the same table.
- Fix A4 print margins/alignment and content overflow.
- Print multiple checked report cards as one document.

**Non-Goals:**
- Editing grades or weights from the board (that stays in `/grading/entry`).
- Changing the report-card workflow states or backend grading projection.
- Making the print page logo/signatures dynamic (they stay hardcoded for the
  TPQ Baitur Rochman template).
- Backend PDF generation or a new print service.
- Changing the per-class board's status-tab model beyond merging roster-less
  students into Draft.

## Decisions

### D1: Roster-merge produces the table row set

The table rows are the roster (`useHomeroomRoster`), not `useReportCards`.
Each roster student is joined to their card (if any) by `student_id`. A student
with no card is rendered in the **Draft** tab only, with no average, a `0/Y`
chip, and a disabled [Detail] action.

*Alternative:* a synthetic "Belum ada rapor" tab. Rejected — fragments the view
and the walikelas scans Draft first anyway.

### D2: Y (expected subjects) derives from teaching assignments

`Y = |distinct subject_id|` over `useTeachingAssignments(homeroomId)` filtered
to the active `academic_year_id`. `X` = count of `summary.subjects` entries on
the student's card whose `final_score` is present. A student with no card has
`X=0`. This makes "incomplete" mean "subjects assigned but not yet scored in
the report card", which is exactly the walikelas's monitoring question.

*Alternative:* Y from curriculum (all gradeable subjects regardless of
assignment). Rejected — a subject with no teacher assigned cannot be graded, so
flagging it as "missing" would be noise.

### D3: Expand is a global column toggle, not a per-row sub-table

The [Expand] button in the actions column toggles a component-level boolean
that appends one read-only `<th>/<td>` column per assigned subject to the
*whole table*. Cell value = the matching `summary.subjects[].final_score` or
`—`. This keeps every row aligned and lets the walikelas scan a column
vertically to spot gaps. The table scrolls horizontally when many subjects.

*Alternative:* per-row inline sub-table. Rejected by the user — "tabel melebar
ke kanan" requires shared columns across rows.

### D4: Bulk print via localStorage + single multi-card document

Checked report-card IDs are written to `localStorage` (key
`bulkPrint:reportCardIds`) and the print route is opened as
`/grading/report-cards/print?batch=true` (a new index-level route). That route
reads the IDs from localStorage, fetches each card's detail, and renders them
stacked with `break-after: page` between cards. A later bulk print overwrites
the key with the latest selection. The single-card route (`/[reportTypeId]/print`)
is kept for the detail-modal "Cetak Rapor" link.

*Why localStorage over sessionStorage:* the print route is opened in a **new
tab** (`window.open(...)`). `sessionStorage` is scoped to a single browsing
context (tab) and is **not** shared with a newly opened tab, so the IDs written
by the board are invisible to the print tab. `localStorage` is shared across all
same-origin tabs, which is what makes the board→new-tab handoff work. A later
bulk print overwrites the payload.

*Why localStorage over query params:* a class may have 30+ students; UUIDs in a
query string risk URL-length limits and clutter history. localStorage avoids
both.

*Alternative considered:* opening N print windows. Rejected — popup blockers and
N print dialogs are a poor UX. *Backend PDF generation* rejected — requires new
rendering infrastructure out of scope.

### D5: A4 fix targets @page + container grid + kelompok break

The current `@page { margin: 15mm 12mm }` and the `grid-cols-[1.5fr_1fr]`
split cause the photo/student-info column to overflow or the kelompok tables to
clip. The fix: tune `@page` margins, constrain the print container to the
`210mm × 297mm` content box, apply `break-inside: avoid` to each kelompok table
so it does not split across pages, and add `break-after: page` between cards in
bulk mode.

## Risks / Trade-offs

- **N card-detail fetches in bulk mode** → batch of 30 could issue 30 detail
  requests. Mitigation: fire them in parallel via `Promise.all`; each is a
  lightweight projection read. Re-evaluate a batch endpoint only if latency is
  observed.
- **Stale Y when assignments change** → teaching assignments query must
  invalidate on assignment create/delete. The existing
  `useTeachingAssignments` cache key already covers this.
- **sessionStorage cleared before print** → moot: localStorage is used (shared
  across tabs) and cleared on read by the print route, so even if the user
  closes the print tab the next "Cetak Terpilih" overwrites the key.
- **Horizontal scroll with many subjects** → acceptable; the table is already
  designed for horizontal scroll (see `/grading/entry`). Sticky name column
  recommended.

## Migration Plan

Frontend-only. No backend migrations, no env changes. Deploy is a web build.
Rollback is reverting the web commit — the backend contract is unchanged.
