# Proposal — report-types-year-scoped

> **Reworks the just-applied `report-card-batches`.** That change scoped report
> "batches" to `(homeroom × year)` and put weighting + an explicit compute step on
> a per-class modal. This change moves the concept up to the **academic year**,
> makes weighting a many-to-many of `(report type × evaluation)`, and replaces
> explicit compute with **live auto-calc + snapshot at draft generation**.

## Why

A report *type* ("Rapor Tengah Semester", "Rapor Akhir Semester") is a
school-wide, year-level concept — not something an operator should recreate per
class. Today it is a per-class `report_batch`, so the same two report types must
be invented again for every homeroom, and the weighting modal lives on the wrong
screen. Teachers also expect a subject's report mark to update **as grades are
entered**, and — being a multi-tenant SaaS — different schools fold the same
evaluation (e.g. UH1, UTS) into **different** report types with **different**
weights. Neither the per-class batch model nor the single per-batch formula can
express that.

## What Changes

- **BREAKING — Report type replaces batch.** `report_batch (homeroom × year)`
  becomes `report_type (year)` with a `code` ("Rapor UTS") and `name`
  ("Rapor Tengah Semester"). Report types are created/edited in the **Edit Tahun
  Ajaran** form (new section), not on the report board. `report_card` is keyed by
  `(report_type_id, student_id)`; homeroom is derived from enrollment.
- **BREAKING — Weighting is many-to-many `(report type × evaluation)`.** The old
  per-batch `report_formula` is re-keyed to `report_type_id`. One evaluation may
  contribute to several report types with different weights. Within a
  `(report type × subject)` the weights MUST total exactly **100%**.
- **Live report scores + snapshot.** A new `subject_report_score`
  `(report_type, subject, student)` is recomputed and stored **every time a grade
  is saved** (`Σ score × weight / 100`, missing score = 0). The explicit
  `[Hitung Nilai]` compute action is **removed**. `[Generate Draft]` freezes the
  live scores into `report_subject_score` and snapshots the weights into the card.
- **Grade entry grid gains N report-score columns.** `/grading/entry` shows one
  read-only "Nilai Rapor" column per report type (titled by its `code`), in
  addition to the editable evaluation columns. Evaluation headers carry **no**
  weight number (weight is per report type, set via a matrix in Kelola Evaluasi).
- **Report board rebuilt + routed.** `/grading/report-cards` lists report types
  for a chosen year (no class picker). `[Buka Rapor]` →
  `/grading/report-cards/<report_type_id>/classroom` (pick class) →
  `/grading/report-cards/<report_type_id>/classroom/<classroom_id>`, which shows
  the 5 workflow statuses as **tabs with counts**, a student **datatable** with
  multiselect checkboxes and a per-row **[Detail]** icon. `[Detail]` opens a large
  **modal** (the former `/report-cards/[id]` content). The
  `/grading/report-cards/[id]` page is **removed**; `[id]/print` is **kept**.
- **Weighting UI on the report board is removed** (moves to Kelola Evaluasi).

## Capabilities

### New Capabilities
<!-- none — both affected capabilities already exist from prior changes -->

### Modified Capabilities
- `report-card-workflow`: report cards group under year-level report types
  (not per-class batches); weighting is `(report type × evaluation)` summing to
  100%; per-subject scores are computed live on grade save and frozen at draft
  generation; the explicit compute endpoint is removed.
- `web-report-cards`: report types are managed in the academic-year form; the
  report board becomes a year + report-type list that routes into a per-class,
  tabbed, datatable workflow board with a detail modal; grade entry shows
  per-report-type score columns; the weighting modal moves to Kelola Evaluasi.

## Impact

- **Backend (grading-service):** migrations rewrite (`report_batch` →
  `report_type`, drop `homeroom_id`; re-key `report_formula` to `report_type_id`;
  new `subject_report_score`; `report_card.batch_id` → `report_type_id` +
  `weights_snapshot`). New report-type CRUD + formula routes; live recompute on
  grade upsert; `generate` snapshots live scores; remove the compute endpoint.
  `evaluation` unchanged (weight stays out of the evaluation row).
- **Backend (academic-config or grading):** report types are edited from the
  academic-year screen — decide ownership in design.
- **Web:** rebuild `/grading/report-cards` + new nested `classroom` routes;
  delete `/report-cards/[id]` page (keep `print`); add report-type section to the
  academic-year edit modal; add weight matrix + N score columns to `/grading/entry`.
- **Contracts/docs:** update `docs/internal/11_integration_contracts/apis/grading-service-api.md`
  (report-type/formula endpoints, `generate` snapshot, removed compute, codes).
- **Data:** early/dev — migrations are rewritten and the dev DB is reset; no data
  migration.
