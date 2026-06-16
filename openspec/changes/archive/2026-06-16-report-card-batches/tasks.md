# Tasks — report-card-batches

Ordered backend → web. **Depends on `grade-entry-evaluations`** (evaluations +
grades keyed by `evaluation_id` must exist first). No data migration (early/dev).

## 1. Backend — schema

- [x] 1.1 Migration: add `report_batch` (batch_id, tenant, homeroom_id, academic_year_id, name, timestamps)
- [x] 1.2 Migration: add `report_formula` (batch_id, subject_id, weights JSONB, updated_at; `UNIQUE (batch_id, subject_id)`)
- [x] 1.3 Migration: add `batch_id` to `report_card`; swap unique constraint `(student, year)` → `(batch_id, student)`
- [x] 1.4 Migration: add `report_subject_score` (report_card_id FK CASCADE, subject_id, final_score, computed_at; `UNIQUE (report_card_id, subject_id)`)
- [x] 1.5 `domain.rs`: `ReportBatch`, `ReportFormula`, `ReportSubjectScore` structs; add `batch_id` to `ReportCard`

## 2. Backend — batches & formulas

- [x] 2.1 `repo.rs`/`commands.rs`/`queries.rs`: batch create/list/delete (admin)
- [x] 2.2 Formula upsert `PUT /report-batches/{id}/formulas/{subject_id}`; reject `INVALID_WEIGHTS` when Σ ≠ 100; list formulas
- [x] 2.3 `http.rs`: batch + formula routes under `/api/v1/grading/report-batches`
- [x] 2.4 Integration tests (multiple batches per class+year, formula 100 accepted, ≠100 rejected) + `make test`

## 3. Backend — compute (snapshot) + generation

- [x] 3.1 Replace `derive_report_summary` average with weighted compute: per valid subject, per student `Σ score×weight/100`, missing score = 0; skip subjects with invalid formula
- [x] 3.2 `POST /report-batches/{id}/compute`: upsert frozen `report_subject_score`, stamp `computed_at`, return `{ computed[], skipped[] }`
- [x] 3.3 Rework `generate_report_cards` to take `{ batch_id }` and create **empty** Draft cards (no scores); idempotent per `(batch, student)`; refresh only Draft
- [x] 3.4 Card `summary` derived from frozen `report_subject_score` rows (pass/fail vs `minimum_passing_score`)
- [x] 3.5 Scope `GET /report-cards?batch_id`; keep transition endpoints/role gates unchanged
- [x] 3.6 Integration tests (compute freezes scores, missing=0, skip invalid subject, re-compute overwrites, generate empty drafts, board filtered by batch) + `make test`

## 4. Backend — contract docs

- [x] 4.1 Update `docs/internal/11_integration_contracts/apis/grading-service-api.md`: batch/formula/compute endpoints, generate `{ batch_id }`, `report-cards?batch_id`, codes (`INVALID_WEIGHTS`)

## 5. Web — query/mutation layer

- [x] 5.1 `use-grading.ts`: batch queries + create/delete mutations
- [x] 5.2 Formula query (per batch) + upsert mutation; compute mutation returning computed/skipped
- [x] 5.3 Generate mutation takes `batch_id`; report-cards query scoped by `batch_id`

## 6. Web — report board rebuild

- [x] 6.1 Rebuild `grading/report-cards/page.tsx`: Tahun/Kelas selectors → batch datatable with [+ Tambah Rapor]
- [x] 6.2 [Atur Bobot] modal: subjects × evaluation weight inputs; per-subject running total; exact-100 valid state; "belum diatur" + skip indicator
- [x] 6.3 [Hitung Nilai] action in modal; report computed vs skipped counts
- [x] 6.4 [Buka] opens the existing 5-status approval board scoped to the batch (reuse current board, filter by batch_id)
- [x] 6.5 Component/e2e coverage (batch create, weight validation, compute result, board per batch) + web test cmd
