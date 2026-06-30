# Tasks: restructure-term-report-ui

Web submodule `apps/web`, branch context `feat/add-academic-term`.
Depends on `ui-foundations-polish` shipping the shared `ui/tabs` component first.

## 1. Year edit form → three real tabs + Simpan

- [x] 1.1 In `src/app/settings/academic/years/page.tsx`, replace the
      `setActiveTab` fake-tab buttons in `YearFormModal` with shadcn `Tabs`
      (`Info`, `Kebijakan Nilai`, `Versi Kurikulum`).
- [x] 1.2 Add an explicit Simpan button for the Info tab; keep per-section save
      for GradingPolicy/Curriculum.
- [x] 1.3 Remove the `Semester` (`TermsSection`) and `Jenis Rapor`
      (`ReportTypesSection`) tabs from the year modal.
- [x] 1.4 Verify create-flow disabling (Kebijakan/Kurikulum until year exists)
      still holds with the tab structure.

## 2. Standalone terms page

- [x] 2.1 Create `src/app/settings/academic/terms/page.tsx` listing the
      academic-scope year's terms (reuse `useTerms(yearId)`).
- [x] 2.2 Move/adapt `TermsSection` logic (create/edit/delete) into the page;
      wire status transitions reusing the year transition confirm UX
      (`status-confirm-dialog.tsx`).
- [x] 2.3 Register the **Semester** tab → `/settings/academic/terms` in
      `src/components/features/academic-config/academic-settings.tsx`.
- [x] 2.4 Gate the page on `academic.config.read` (view) and
      `academic.config.write` (mutate).

## 3. Semester edit form (Info + Jenis Rapor)

- [x] 3.1 Build a semester edit form (modal) with shadcn `Tabs`: `Info`
      (name/dates/status) and `Jenis Rapor`.
- [x] 3.2 Move `ReportTypesSection` into the Jenis Rapor tab unchanged
      (term-scoped `term_id`).
- [x] 3.3 Launch the form from the terms page row actions.

## 4. Empty-state copy

- [x] 4.1 In `src/app/grading/report-cards/page.tsx`, replace "Tambahkan dari
      Pengaturan → Tahun Ajaran" with guidance to manage Jenis Rapor on the
      semester form for the selected term.

## 5. Spec & tests

- [x] 5.1 Update `web-academic-config-management` wording: term management is a
      standalone page in the academic-config group (reconcile "sub-page of the
      year area").
- [x] 5.2 Component/visibility tests: year modal shows 3 tabs + Simpan; terms
      page lists/creates/transitions; semester form shows Info/Jenis Rapor;
      read-only role disables mutations.
- [x] 5.3 Web lint + typecheck green; relevant Playwright specs updated.

## 6. Terms page → server-driven DataTable (rework)

- [x] 6.1 Replace the terms page cards/inline create form with the
      `DataTable`-based layout used by `/settings/academic/years`: search input,
      create button top-right, pagination + sort controls.
- [x] 6.2 Add `src/lib/schemas/academic-terms-params.ts` (URL params
      `search`/`page`/`page_size`/`sort`; default sort `start_date`, page size 10)
      and a `useTermsTable(yearId, params)` query hook returning `{ data, meta }`.
- [x] 6.3 Row actions: visible `Edit` button (left) + icon-only `⋮` dropdown
      with `Delete` only.
- [x] 6.4 Remove client-side sorting; rely on backend `sort`.

## 7. TermFormModal (create + edit, tabs Info + Rapor)

- [x] 7.1 Build a single `TermFormModal` with `mode="create"|"edit"`. Create
      mode renders only the Info tab; edit mode renders `Info` + `Rapor` tabs.
- [x] 7.2 Info tab edit mode: persist name/dates via update + run status
      transition if the status changed; show error + refetch on partial failure.
- [x] 7.3 Rename the report-type tab label from "Jenis Rapor" to "Rapor".
- [x] 7.4 After a successful create, reopen the modal in edit mode on the
      `Rapor` tab for the newly created term.
- [x] 7.5 Retire the legacy `TermEditDialog` once `TermFormModal` covers it.

## 8. Backend: report-type copy endpoint

- [x] 8.1 Add `POST /api/v1/grading/report-types/copy` to grading-service
      (`commands::copy_report_types`): tenant-scoped, admin-only, validates both
      terms in the same academic year + tenant, rejects `source == target`.
- [x] 8.2 Copy report-type definitions only (`code`, `name`, relative
      `position`); skip duplicate codes already present in the target term.
- [x] 8.3 Run the inserts in a single transaction; return
      `{ copied: N, skipped: M }`.
- [x] 8.4 Reject `overwrite=true` with 422 until there is a product need.
- [x] 8.5 Backend tests for happy path, duplicate-skip, cross-year rejection,
      and `source == target` rejection.

## 9. Frontend copy report-types integration

- [x] 9.1 Add `ReportType` field `term_id`; add `useCopyReportTypes` mutation
      and `copyReportTypes` Zod schema.
- [x] 9.2 Fix `useCreateReportType`/`useUpdateReportType`/`useDeleteReportType`
      invalidation to include `termId` (use the full
      `reportTypesQueryKey(yearId, termId)`).
- [x] 9.3 Create flow: optional "Salin daftar rapor dari semester lain"
      checkbox + source-term selector (same year, exclude target); disabled when
      no source term has report types; calls copy endpoint after create.
- [x] 9.4 Rapor tab: "Salin dari semester lain" button → small dialog to pick a
      source term; on success toast `X disalin, Y dilewati` and refetch.
- [ ] 9.5 Playwright smoke: search table, open create, open edit tabs, copy
      dialog visible.

## 10. Final verification

- [ ] 10.1 `cd apps/backend && make test` green (grading-service) — skipped by apply; run manually using the command below.
- [ ] 10.2 `cd apps/web && bun run lint && bun run typecheck` green.
- [ ] 10.3 `cd apps/web && bun run test` green.

## Manual Backend Tests

Run this manually after implementation (skipped by `/opsx-apply`):

```sh
cd apps/backend && make test
```

For the grading-service crate only:

```sh
cd apps/backend && cargo test -p grading-service
```
