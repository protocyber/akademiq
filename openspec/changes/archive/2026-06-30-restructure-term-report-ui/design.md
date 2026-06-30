## Context

The academic-config management UI lives in `apps/web`. Today
`src/app/settings/academic/years/page.tsx` renders a single `YearFormModal` with
five fake-tab sections (`setActiveTab` + styled `<Button>`): `Info`,
`Kebijakan Nilai`, `Versi Kurikulum`, `Semester`, `Jenis Rapor`. Three shells
already use route-driven nav: `academic-settings.tsx`
(years/subjects/class-templates), `academic-ops-page.tsx`, and report-card
status approval.

Data is already term-scoped: `ReportTypesSection` gates on `termId`
(`disabled={!canManage || !termId}`), so moving report types to a semester form
is a UI relocation, not a contract change. The `web-academic-config-management`
spec describes term management as "a section/sub-page of the year management
area"; this change interprets that as the academic-config shell group, not the
year modal.

This change depends on a shared shadcn `Tabs` component, which does not yet exist
in the repo and is delivered by `ui-foundations-polish`.

## Goals / Non-Goals

**Goals:**
- Put each management surface where its entity lives: year attributes on the
  year form; terms on a terms page; report types on the semester form.
- Use real shadcn `Tabs` (state-driven) for the in-modal forms.
- Add the missing Simpan button to the year form.
- Replace the misleading report-type empty-state copy.

**Non-Goals:**
- The `term_id` data bug (covered by `fix-term-id-divergence`).
- The shared `Tabs` component, dialog scrollable base, and table→card layout
  (covered by `ui-foundations-polish`).
- Route-driven tab styling across ops/status pages (covered by
  `ui-foundations-polish`).

## Decisions

### Decision 1: Year form = three state-driven tabs + Simpan
`YearFormModal` keeps only `Info`, `Kebijakan Nilai`, `Versi Kurikulum` as real
shadcn `Tabs` (`value`/`onValueChange`, local state, no URL). Add an explicit
Simpan button on the Info tab (and per-tab save where a section already saves
independently, matching current GradingPolicy/Curriculum behavior).

### Decision 2: Terms get a standalone page in the academic-config shell
Add `/academic/terms` as a sibling tab in `academic-settings.tsx`. The page lists
a year's terms and supports create/edit/delete plus status transitions, reusing
the type-to-confirm + cooldown UX from year transitions.

### Decision 3: Report types move to a semester edit form (Info + Rapor)
The semester edit form uses two real shadcn `Tabs`: `Info` and `Rapor`.
`ReportTypesSection` moves here (already `term_id`-scoped). The report board
empty-state copy changes to term-correct guidance.

### Decision 4: Terms page uses the same server-driven DataTable as years
The terms page mirrors `/settings/academic/years`: URL search params
(`search`, `page`, `page_size`, `sort`), server-side search/pagination/sort (the
backend already supports it), a search input, a create button top-right, and
per-row actions (visible `Edit` + icon-only dropdown with `Delete`). Term status
moves into the edit modal's Info tab (with the existing type-to-confirm +
cooldown transition UX), not the row.

### Decision 5: Single TermFormModal handles create and edit
One `TermFormModal` component. **Create mode** shows only the Info tab (name,
dates, optional "copy report types from another semester" selector). **Edit
mode** shows two real shadcn `Tabs`: `Info` (name, dates, status transition +
Simpan) and `Rapor` (the term-scoped report type list). The Rapor tab label is
"Rapor" (not "Jenis Rapor"). After a successful create, the modal reopens in
edit mode on the Rapor tab so the operator can review copied report types.

### Decision 6: Backend report-type copy endpoint
Add `POST /api/v1/grading/report-types/copy` to grading-service. Body:
`{ academic_year_id, source_term_id, target_term_id, overwrite }`. It copies
report-type definitions only (`code`, `name`, relative `position`); it does NOT
copy formulas (formulas reference term-scoped evaluations and need separate
mapping). Duplicate codes in the target term are skipped. `overwrite=true` is
rejected for now (returns 422) until there is a product need. The endpoint is
tenant-scoped, requires admin role, validates that both terms belong to the same
academic year + tenant, and rejects `source == target`. Response returns
`{ copied, skipped }`. This endpoint is atomic (single DB transaction).

## Open Questions (resolved)

- Should the semester edit form be a modal launched from the terms page, or a
  sub-route (`/academic/terms/[termId]`)? **Resolved:** modal, consistent with
  the year edit form.
- Per-tab save vs single Simpan on the year form: keep the existing per-section
  save for GradingPolicy/Curriculum, add a single Simpan for Info? **Resolved:**
  yes — least churn to current behavior.
