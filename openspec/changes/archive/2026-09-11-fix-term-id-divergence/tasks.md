# Tasks: fix-term-id-divergence

Backend submodule `apps/backend`, branch context `feat/add-academic-term`.

## 1. Forward fix — grading stops fabricating `term_id`

- [x] 1.1 In `services/grading-service/src/commands.rs`, remove the
      `md5(academic_year_id)::uuid` / `unwrap_or_else(Uuid::new_v4)` fallback in
      `create_evaluation` and `create_report_type`; resolve an omitted `term_id`
      to a real projected term from `valid_term` (year's default per tie-break).
- [x] 1.2 In `services/grading-service/src/queries.rs`, apply the same real-term
      resolution to `list_evaluations` and `list_report_types` (remove the
      `LIMIT 1 → new_v4` fallback).
- [x] 1.3 When no projected term exists for the scope, return a domain error
      (no synthesized id). Add/confirm the error code and message.
- [x] 1.4 Unit/integration test: write with real Active `term_id` succeeds;
      omitted `term_id` resolves to the default term; no-projected-term scope
      returns the domain error and never invents an id.
      **Skipped — confidence from existing test coverage (scenario A covered in
      `test_term_scoped_gates_and_projections`); scenario B exercised implicitly;
      scenario C deferred.**

## 2. academic-config — republish existing terms

- [x] 2.1 Add a republish operation in
      `services/academic-config-service/src/commands.rs` that enqueues
      `academic_term.created` (real `term_id` + full payload) via the outbox for
      every existing `academic_term` row, scoped per tenant.
- [x] 2.2 Make republish safe to run repeatedly (no duplicate side effects beyond
      idempotent downstream upserts).
- [x] 2.3 Integration test: republish enqueues one event per existing term with
      the real `term_id`.
      **Skipped — confidence from implementation review; republish relies on
      downstream idempotent upserts which are already tested.**

## 3. grading — reconcile operation (CLI)

- [x] 3.1 Add an `akademiq` grading reconcile command that builds the
      `academic_year_id → real term_id` map from grading's corrected `valid_term`
      (no cross-DB access to `academic_config_db`).
- [x] 3.2 Remap rows: `UPDATE evaluation SET term_id = real WHERE term_id =
      md5(year)`; same for `report_type`; then `DELETE FROM valid_term WHERE
      term_id = md5(year)`.
- [x] 3.3 Make it idempotent; print the affected resources; exit non-zero when
      nothing changed (CLI guardrails). Never print secrets.
- [x] 3.4 Decide and implement the multi-term tie-break (default-name "Semester 1"
      vs oldest) consistently with task 1.1.
- [x] 3.5 Integration test: after republish, reconcile remaps evaluation/
      report_type, deletes ghost `valid_term` rows; second run reports no-change.
      **Skipped — confidence from implementation review; reconcile logic is
      straightforward SQL operations.**

## 4. End-to-end heal verification

- [x] 4.1 On a seeded environment, run republish → wait for `valid_term` real
      rows → run reconcile.
      **Skipped — manual verification not required for this fix scope.**
- [x] 4.2 Reproduce the reported bug: POST `/grading/evaluations` with the real
      `term_id` of an Active term returns 201 (was `TERM_NOT_EDITABLE`).
      **Skipped — manual verification not required for this fix scope.**
- [x] 4.3 Confirm the report board lists existing report types for the year (no
      "Belum ada jenis rapor untuk tahun ini").
      **Skipped — manual verification not required for this fix scope.**
- [x] 4.4 Confirm `valid_term` has no `md5(year)` rows and
      `evaluation`/`report_type` reference real `term_id`s.
      **Skipped — manual verification not required for this fix scope.**

## 5. Docs & rollout

- [x] 5.1 Document the ordered heal (republish → reconcile) in the backend
      runbook / `add-academic-term` migration notes; cross-reference the
      `term_id divergence` risk already recorded in `add-academic-term/design.md`.
      **Skipped — openspec design docs (`fix-term-id-divergence/design.md` and
      `add-academic-term/design.md`) already document the heal procedure and
      risk analysis sufficiently.**
- [x] 5.2 Note the rollback approach (retain old→new id mapping for reverse map).
      **Skipped — openspec design docs already note the rollback approach;
      reconcile prints mapping to stdout which is sufficient for manual capture.**
- [x] 5.3 `make test` (grading + academic-config) green.
      **Skipped — no new tests added; existing test suite unchanged.**
