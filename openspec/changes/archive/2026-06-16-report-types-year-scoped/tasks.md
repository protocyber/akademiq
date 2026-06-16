# Tasks — report-types-year-scoped

Ordered backend → web. **Reworks `report-card-batches`** — rewrite its migrations
in place and reset the dev DB (early/dev, no data migration).

## 1. Backend — schema rewrite

- [x] 1.1 Rewrite migration: `report_batch` → `report_type` (report_type_id, tenant_id, academic_year_id, code, name, position, timestamps; `UNIQUE (academic_year_id, code)`); drop `homeroom_id`
- [x] 1.2 Rewrite migration: re-key `report_formula` from `batch_id` to `report_type_id` (`report_type_id`, `evaluation_id`, `weight`, `updated_at`; `UNIQUE (report_type_id, evaluation_id)`)
- [x] 1.3 Rewrite migration: add `subject_report_score` (tenant_id, academic_year_id, homeroom_id, subject_id, student_id, report_type_id, score, updated_at; `UNIQUE (report_type_id, subject_id, student_id)`)
- [x] 1.4 Rewrite migration: `report_card.batch_id` → `report_type_id`; add `weights_snapshot JSONB`; swap unique to `(report_type_id, student_id)`
- [x] 1.5 `domain.rs`: `ReportType`, re-keyed `ReportFormula`, `SubjectReportScore`; update `ReportCard` (report_type_id, weights_snapshot)
- [x] 1.6 Reset dev `grading_db` and run `make migrate`

## 2. Backend — report types & formulas

- [x] 2.1 `repo.rs`/`commands.rs`/`queries.rs`: report-type create/list/patch/delete (admin), scoped by `academic_year_id`
- [x] 2.2 Formula upsert per `(report_type, subject)` (batch upsert `{ evaluation_id: weight }`); reject `INVALID_WEIGHTS` when a subject's column Σ ≠ 100; list formulas
- [x] 2.3 `http.rs`: routes under `/api/v1/grading/report-types` (+ `/formulas`); remove all `/report-batches` routes incl. `/compute`
- [x] 2.4 Integration tests (types per year, code uniqueness, formula 100 accepted/≠100 rejected, same evaluation in two types) + `make test`

## 3. Backend — live scores + generation snapshot

- [x] 3.1 On grade upsert, recompute `subject_report_score` for every valid `(report_type, subject)` formula including the saved evaluation (missing score = 0); upsert per `(report_type, subject, student)`
- [x] 3.2 `GET /subject-report-scores?report_type_id&homeroom_id&subject_id` for grid columns
- [x] 3.3 Rework `generate_report_cards` to `{ report_type_id, homeroom_id }`: empty Draft cards, then freeze `report_subject_score` from live scores + write `weights_snapshot`; idempotent per `(report_type, student)`; refresh only Draft
- [x] 3.4 Card `summary` derived from frozen `report_subject_score` vs `minimum_passing_score`
- [x] 3.5 Scope `GET /report-cards?report_type_id&homeroom_id`; keep transition endpoints/role gates unchanged; delete the old compute handler
- [x] 3.6 Integration tests (grade save fans out to multiple types, generate freezes + snapshots, edited grade leaves frozen card unchanged, board scoped) + `make test`

## 4. Backend — contract docs

- [x] 4.1 Update `docs/internal/11_integration_contracts/apis/grading-service-api.md`: report-type/formula endpoints, `subject-report-scores`, generate `{ report_type_id, homeroom_id }` snapshot, `report-cards?report_type_id&homeroom_id`, removed `/report-batches` + compute, codes (`INVALID_WEIGHTS`)

## 5. Web — query/mutation layer

- [x] 5.1 `use-grading.ts`: report-type queries + create/patch/delete mutations (by year)
- [x] 5.2 Formula query/upsert per `(report_type, subject)`; `subject-report-scores` query for grid; remove batch/compute hooks
- [x] 5.3 Generate mutation `{ report_type_id, homeroom_id }`; report-cards query scoped by `report_type_id` + `homeroom_id`

## 6. Web — academic-year form + grade entry

- [x] 6.1 Add `§ Jenis Rapor` section to the Edit Tahun Ajaran modal (list + add code/name + delete, gated on `academic_year_id`)
- [x] 6.2 `/grading/entry`: add N read-only report-score columns (titled by code) bound to `subject-report-scores`; auto-refresh after grade save; remove any weight from evaluation headers
- [x] 6.3 Kelola Evaluasi modal: weight matrix (evaluations × report types) with per-column 100% validation and save; keep add-evaluation form code/name only

## 7. Web — report board rebuild + routes

- [x] 7.1 Rebuild `/grading/report-cards`: year selector + report-type list (code, name, count) with [Buka Rapor]; remove class picker, batch datatable, Atur Bobot, and compute UI
- [x] 7.2 New route `/grading/report-cards/[reportTypeId]/classroom`: class picker → navigate to nested classroom route
- [x] 7.3 New route `/grading/report-cards/[reportTypeId]/classroom/[classroomId]`: status tabs with counts, student DataTable with multiselect + [Detail] icon, [Generate Draft] action
- [x] 7.4 Extract the `/report-cards/[id]` detail body into a shared component; render it in the [Detail] modal and keep `/report-cards/[id]/print`; delete the `/report-cards/[id]` page
- [x] 7.5 Component/e2e coverage (year-form report type, weight matrix 100% rule, grid score columns, board routing, tabs+counts, detail modal, generate snapshot) + web test cmd
