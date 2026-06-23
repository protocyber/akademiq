## Why

Today an evaluation (evaluasi) is created one-by-one per `(homeroom, subject, term)` directly on `/grading/entry`. Every teacher must manually recreate the same evaluation list (UH1, UTS, UAS, ...) and re-enter weights for every class and subject they teach. There is no per-semester master list, so structure and weighting drift between classes and a newly created teaching assignment starts with an empty evaluation set.

This change introduces a per-term **evaluation template** (master) managed centrally on the term edit form, plus weight templates, and materializes concrete evaluations + weights for teaching assignments automatically and on demand.

## What Changes

- Add a per-term **evaluation template** master, scoped per tenant via `term_id`, holding `code`, `name`, `position`.
- Add a **weight template** linking each report type to template evaluations (`report_formula_template`), mirroring the existing concrete `report_formula`.
- Add an **"Evaluasi" tab** to the term edit form at `/settings/academic/terms`. **BREAKING (UI):** the tab order changes to `Info | Status | Rapor | Evaluasi` — the Evaluasi tab is placed **after** Rapor because weight columns depend on report types created in the Rapor tab.
- The Evaluasi tab mirrors the existing "Kelola Evaluasi" dialog: an evaluation list editor plus a weight matrix (columns = report types of that term).
- Add a **"Terapkan ke semua penugasan yang belum punya evaluasi"** action that backfills concrete evaluations (and weights, where report types exist) for every teaching assignment in the term that has no evaluations yet. Idempotent.
- On `teacher.assigned`, the grading service **auto-materializes** concrete evaluations + weights from the term template. Idempotent, no-op when no template/report type exists yet.
- Materialization applies only to terms in `Draft`/`Active` status that have a template.
- The template is a **seed, not a lock**: teachers may still add/delete concrete evaluations per `(class, subject)` afterward.
- Surface a **nudge banner** ("N penugasan belum punya evaluasi") computed locally in grading, on the Evaluasi tab and `/grading/entry`.
- Show a **warning (not a block)** when a report type's subject weights no longer total 100% after teacher overrides, or when a report type does not yet exist.
- Add **user-facing and technical documentation** for the evaluation/weight template copy flow.

## Capabilities

### New Capabilities
- `term-evaluation-templates`: per-term master evaluation list and weight templates in the grading service, including the auto-materialization on `teacher.assigned`, the on-demand backfill action, idempotency rules, and term-status gating.

### Modified Capabilities
- `grading-service-grade-capture`: evaluations and report formulas gain a template source; concrete evaluations may be created by materialization from a term template in addition to manual creation.
- `web-grading-entry`: the "Kelola Evaluasi" experience is reused on the term edit form; `/grading/entry` shows the unmaterialized-assignments nudge banner and post-override weight warnings.
- `web-academic-config-management`: the term edit form gains the "Evaluasi" tab and changes tab order to place it after "Rapor".

## Impact

- **grading-service**: new tables `evaluation_template`, `report_formula_template` (new migration); new HTTP endpoints for template CRUD, weight template CRUD, backfill/apply, and the unmaterialized-assignment count; `teacher.assigned` event consumer extended to materialize from template; idempotent inserts via `ON CONFLICT DO NOTHING`.
- **academic-ops-service**: no schema change; continues to emit `teacher.assigned` (IDs only) as today.
- **apps/web**: new "Evaluasi" tab in `term-form-modal.tsx`; reuse of the evaluation list + weight matrix components from `/grading/entry`; new query/mutation hooks for templates; nudge banner; tab-order change. Existing tests asserting `Info | Rapor` tab structure must be updated.
- **docs**: technical + user-facing documentation for the template copy/materialization flow.
- No change to `tenant_id`-from-JWT resolution rules; templates resolve `tenant_id` from `valid_term` on insert.
