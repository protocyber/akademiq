## 1. Backend — grading-service schema

- [x] 1.1 Add refinery migration creating `evaluation_template(template_id PK, tenant_id, term_id, code, name, position, created_at, updated_at)` with `UNIQUE(tenant_id, term_id, code)`
- [x] 1.2 Add `report_formula_template(report_type_id, evaluation_template_id, weight, created_at, updated_at)` with `UNIQUE(report_type_id, evaluation_template_id)` and FKs
- [x] 1.3 Add domain structs `EvaluationTemplate` and `ReportFormulaTemplate` in `src/domain.rs`
- [x] 1.4 Add repo methods: insert/list/update/delete template entries; upsert/list weight templates (resolve `tenant_id` from `valid_term`)

## 2. Backend — template CRUD + weight endpoints

- [x] 2.1 Add command handlers for evaluation-template create/update/delete with `(tenant_id, term_id)` uniqueness and `academic.config.write` permission gate
- [x] 2.2 Add query handler `list_evaluation_templates(term_id)` ordered by `position`
- [x] 2.3 Add weight-template upsert handler validating same-term references and 100% sum
- [x] 2.4 Register routes: `/api/v1/grading/evaluation-templates` (GET/POST), `/{id}` (PATCH/DELETE), `/report-types/{id}/formula-templates` (GET/PUT)

## 3. Backend — materialization on teacher.assigned

- [x] 3.1 Extend the `teacher.assigned` consumer in `src/events.rs` to materialize concrete evaluations from the term template for each Draft/Active term in the assignment's year
- [x] 3.2 Insert concrete evaluations with `ON CONFLICT (tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code) DO NOTHING`
- [x] 3.3 Materialize concrete `report_formula` from weight templates when a matching report type exists, idempotently; skip weights when no report type exists
- [x] 3.4 Verify no-op behavior when no template exists (safe to deploy before any template)

## 4. Backend — backfill (apply) + nudge count

- [x] 4.1 Add apply handler: for a term, INSERT...SELECT concrete evaluations for assignments (`teaching_authz`) that have zero evaluations; return filled/skipped counts; gate on `academic.config.write`
- [x] 4.2 Materialize weights in the apply path where report types exist, idempotently
- [x] 4.3 Add unmaterialized-assignment count query (local `teaching_authz ⟕ evaluation` join) and endpoint
- [x] 4.4 Register routes for apply action and count

## 5. Backend — tests

- [x] 5.1 Integration test: template CRUD + uniqueness + permission gate (admin 200, non-admin 403)
- [x] 5.2 Integration test: weight template 100% validation and cross-term rejection
- [x] 5.3 Integration test: materialization on `teacher.assigned`, including redelivery idempotency and Closed/Archived term skip
- [x] 5.4 Integration test: apply backfills only assignments lacking evaluations and is idempotent; count goes to 0 after apply

## 6. Web — query/mutation hooks + types

- [x] 6.1 Add `term_id` to the `Evaluation` TS type in `use-grading.ts`
- [x] 6.2 Add hooks for evaluation-template list/create/update/delete and weight-template read/save
- [x] 6.3 Add hooks for the apply action and the unmaterialized-assignment count

## 7. Web — Evaluasi tab on term edit form

- [x] 7.1 Extend `TermTab` union and add the Evaluasi `TabsTrigger`/`TabsContent` after Rapor in `term-form-modal.tsx`
- [x] 7.2 Build the template evaluation list editor (add/edit/delete/reorder), reusing the `/grading/entry` evaluation-row pattern in template mode
- [x] 7.3 Build the weight matrix (columns = term report types) with the 100%-per-report-type save guard, reusing `WeightMatrix`
- [x] 7.4 Add the "Terapkan ke semua penugasan yang belum punya evaluasi" button wired to the apply hook with filled/skipped feedback
- [x] 7.5 Add the nudge (count of assignments lacking evaluations) on the Evaluasi tab

## 8. Web — grade-entry adjustments

- [x] 8.1 Add the unmaterialized-assignment nudge banner on `/grading/entry`
- [x] 8.2 Add the non-blocking weight-drift / missing-report-type warning on `/grading/entry`

## 9. Web — tests

- [x] 9.1 Update `__tests__/academic-config-restructure.test.tsx` for the new `Info | Status | Rapor | Evaluasi` tab order
- [x] 9.2 Update `playwright/academic-config.spec.ts` term-edit tab assertions
- [x] 9.3 Add a test for the apply action feedback and the nudge banner

## 10. Documentation

- [x] 10.1 Add technical documentation under `docs/internal/` for the template tables, materialization flow, idempotency, and term-status gating
- [x] 10.2 Add user-facing documentation under `docs/product/` for managing per-semester evaluations and applying them to assignments
- [x] 10.3 Update `docs/internal/11_integration_contracts/apis/` for the new grading endpoints

## 11. Verification

- [ ] 11.1 Run `cd apps/backend && make test` for grading-service
- [ ] 11.2 Run web lint + unit tests + relevant Playwright spec in `apps/web`
- [ ] 11.3 Manual: create template, assign a teacher, confirm auto-materialization; run apply for a pre-existing assignment; confirm nudge clears
