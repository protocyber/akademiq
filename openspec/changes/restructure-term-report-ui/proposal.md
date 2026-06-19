## Why

Report types are term-scoped in data (`add-academic-term`), but the management
UI still bundles year info, grading policy, curriculum versions, semesters, and
report types into one `YearFormModal` using fake tabs (styled `<Button>` +
`setActiveTab`). This misplaces report types under the year, has no explicit
Simpan (save) button on the year form, and surfaces the misleading message
"Belum ada jenis rapor untuk tahun ini. Tambahkan dari Pengaturan → Tahun
Ajaran." — wrong on two counts (report types are per-term, and they should be
managed from the semester form). This change relocates each management surface
to where its entity actually lives. It captures Decision 10 from
`add-academic-term/design.md` as its own follow-up.

## What Changes

- Convert the year edit form's fake tabs to real shadcn `Tabs` with three tabs:
  `Info`, `Kebijakan Nilai`, `Versi Kurikulum`, and add an explicit **Simpan**
  button (currently missing).
- Remove the `Semester` and `Jenis Rapor` sections from the year modal.
- Add a standalone `/academic/terms` page for term management (list,
  create/edit/delete, status transitions) as a sibling tab in the
  academic-config shell alongside Tahun Ajaran / Mata Pelajaran / Template Kelas.
- Add a semester edit form with two real shadcn `Tabs`: `Info` and
  `Jenis Rapor`. Move `ReportTypesSection` (already `term_id`-scoped in data)
  into the semester form. UI relocation only; the data contract is unchanged.
- Replace the misleading "Tambahkan dari Pengaturan → Tahun Ajaran" copy with
  term-correct guidance.
- Depends on a shared shadcn `Tabs` component (provided by `ui-foundations-polish`).

## Capabilities

### New Capabilities
- `web-term-management`: the standalone term-management surface and the semester
  edit form (Info + Jenis Rapor) where report types are managed.

### Modified Capabilities
- `web-academic-config-management`: year edit form restructured to three real
  tabs with a Simpan button; term management moves to a standalone page;
  report-type management moves to the semester form; corrected empty-state copy.

## Impact

- Web submodule `apps/web`, branch context `feat/add-academic-term`.
- `src/app/settings/academic/years/page.tsx` (split `YearFormModal`,
  `ReportTypesSection`, `TermsSection`).
- New `src/app/settings/academic/terms/page.tsx` and semester form components.
- `src/components/features/academic-config/academic-settings.tsx` (add the
  `/academic/terms` tab).
- `src/app/grading/report-cards/page.tsx` (empty-state copy).
- Reconcile the `web-academic-config-management` spec wording ("sub-page of the
  year area") with the standalone-page decision.
- New grading-service endpoint `POST /api/v1/grading/report-types/copy` that
  copies report-type definitions (code/name/position) from a source term to a
  target term within the same academic year, skipping duplicate codes. Used by
  the term create flow (optional "copy from another semester") and the Rapor
  tab ("Salin dari semester lain").
