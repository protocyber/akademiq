# Tasks — grade-entry-evaluations

Ordered backend → web. No data migration (early/dev; existing grades may be
dropped). This change is a prerequisite for `report-card-batches`.

## 1. Backend — schema

- [ ] 1.1 Migration: add `evaluation` table (`evaluation_id`, tenant, homeroom_id, subject_id, academic_year_id, code, name, position, timestamps; `UNIQUE (tenant, homeroom, subject, year, code)`; index for list-by-scope)
- [ ] 1.2 Migration: change `grade` — replace `subject_id`/`academic_year_id`/`homeroom_id` columns with `evaluation_id` (FK → evaluation, `ON DELETE CASCADE`); swap unique constraint to `UNIQUE (tenant, student, evaluation_id)`; keep `score` 0..100 check
- [ ] 1.3 Update `domain.rs` `Grade` struct (drop subject/year/homeroom, add `evaluation_id`); add `Evaluation` struct

## 2. Backend — evaluation CRUD

- [ ] 2.1 `repo.rs`: evaluation insert/list-by-scope/update/delete; cascade verified
- [ ] 2.2 `commands.rs`/`queries.rs`: create/update/delete/list with auth (assigned teacher or admin); `DUPLICATE_EVALUATION_CODE` on unique violation
- [ ] 2.3 `http.rs`: `GET/POST/PATCH/DELETE /api/v1/grading/evaluations`
- [ ] 2.4 Integration tests (create, duplicate-code 409, list order, delete cascades grades, unassigned 403) + `make test`

## 3. Backend — grade keyed by evaluation

- [ ] 3.1 Rework `record_grade` upsert to key on `(tenant, student, evaluation_id)`; derive subject/homeroom/year from the evaluation for authz
- [ ] 3.2 Rework grade grid query to return scores joined via evaluation for `?homeroom_id&subject_id&academic_year_id`
- [ ] 3.3 Remove/replace the old `PATCH /grades/{id}` + subject/year-keyed paths
- [ ] 3.4 Integration tests (upsert idempotent per evaluation, NOT_ASSIGNED via evaluation, STUDENT_NOT_ENROLLED, score bounds) + `make test`

## 4. Backend — contract docs

- [ ] 4.1 Update `docs/internal/11_integration_contracts/apis/grading-service-api.md`: evaluation endpoints, grade payload `{ student_id, evaluation_id, score }`, grid read shape, new codes (`DUPLICATE_EVALUATION_CODE`)

## 5. Web — query/mutation layer

- [ ] 5.1 `use-grading.ts`: evaluation queries (list by scope) + mutations (create/update/delete/reorder)
- [ ] 5.2 `use-grading.ts`: grade upsert keyed by `evaluation_id`; grid query typed to index by `(student_id, evaluation_id)`; drop old update-by-id
- [ ] 5.3 `lib/schemas/grading`: evaluation schema; grade-cell schema (0–100)

## 6. Web — grade-entry screen

- [ ] 6.1 Rebuild grid in `grading/entry/page.tsx`: columns from evaluations, rows from roster, cell indexed by `(student, evaluation)`
- [ ] 6.2 Per-cell auto-save on blur/debounce with idle/saving/saved/error status; no Update button; inline invalid state; retry on error
- [ ] 6.3 [Kelola Evaluasi] modal gated on class+subject: add/edit/delete/reorder table; confirm delete-with-grades; reflect changes in columns
- [ ] 6.4 Empty-columns hint when no evaluations
- [ ] 6.5 Component/e2e coverage for auto-save status + modal flow; `make test` (or web test cmd)
