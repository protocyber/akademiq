## 1. Backend — repo layer (homeroom-scoped write)

- [x] 1.1 Add `homeroom_id: Uuid` parameter to the `upsert_report_formula` method on the `GradeRepository` trait (`src/repo.rs` trait def ~line 186 and impl ~line 933).
- [x] 1.2 Update the DELETE statement in `upsert_report_formula` to filter `AND e.homeroom_id = $homeroom_id` so only that class's formula rows are replaced.
- [x] 1.3 Verify the INSERT path already binds per-evaluation rows correctly and needs no change beyond the new arg threading.

## 2. Backend — command + recompute narrowing

- [x] 2.1 Add `homeroom_id` to the `UpsertReportFormula` command struct (`src/commands.rs` ~line 1186) and pass it into `state.grades.upsert_report_formula(...)`.
- [x] 2.2 Refactor `recompute_subject_live_scores_batch` (`src/commands.rs` ~line 1346) to accept an explicit `homeroom_id` and recompute only that homeroom's live scores and draft report cards (instead of iterating `homerooms_for_subject_formula`).
- [x] 2.3 Confirm the sum-to-100 validity check still runs against the submitted weights for the `(report_type, homeroom, subject)` scope.

## 3. Backend — HTTP route

- [x] 3.1 Replace the route in `src/http.rs` (~line 69) from `PUT /report-types/:report_type_id/formulas/:subject_id` to `PUT /report-types/:report_type_id/homerooms/:homeroom_id/formulas/:subject_id`.
- [x] 3.2 Update the `upsert_report_formula` handler to extract `homeroom_id` from the path and pass it into the command struct.
- [x] 3.3 Apply evaluation-CRUD-style authorization in the command: call `require_grade_evaluation_manage(&input.perms)` (HTTP 403 `FORBIDDEN` on failure), then for non-`tenant_admin` callers run `is_assigned_to_scope(tenant, user, subject, homeroom, year)` (HTTP 403 `NOT_ASSIGNED`). Thread `user_id`, `roles`, `perms` into `UpsertReportFormula`; resolve `academic_year_id` from the fetched `report_type`.
- [x] 3.4 Leave `GET /report-types/:report_type_id/formulas` (list) unchanged.
- [x] 3.5 Add or update a 404 fallthrough so the old PUT path no longer matches (Axum auto-404s once the route is removed — verify no orphaned matcher).

## 4. Backend — tests

- [x] 4.1 Update the `put_formula` test helper (`tests/integration.rs` ~line 989) to the new homeroom-scoped path.
- [x] 4.2 Update existing formula tests (`formula_with_weights_100_accepted_else_rejected`, `incomplete_formula_yields_no_live_score`, cross-term gate) to the new path.
- [x] 4.3 Add a regression test: two homerooms with distinct evaluations under the same `(report_type, subject)`; saving weights for homeroom A leaves homeroom B's formula rows intact.
- [x] 4.4 Add a regression test: saving weights for one homeroom recomputes only that homeroom's live scores (homeroom B's `subject_report_score` is unchanged).
- [x] 4.5 Add authorization regression tests: (a) a token without `grade.evaluation.manage` → HTTP 403 `FORBIDDEN`, no rows change; (b) a `teacher` with the permission but not assigned to the scope → HTTP 403 `NOT_ASSIGNED`; (c) an assigned `teacher` and a `tenant_admin` both succeed.
- [ ] 4.6 Run `cargo test -p grading-service` and confirm all pass. _(skipped: backend test — see Manual Backend Tests)_

## 5. Frontend — grading entry weight matrix

- [x] 5.1 Update `useUpsertReportFormula` (`src/lib/query/mutations/use-grading.ts` ~line 165) to accept `homeroomId` and call the homeroom-scoped path.
- [x] 5.2 Update `WeightColumnSave` / `WeightMatrix` (`src/app/grading/entry/page.tsx` ~line 1007) to pass the active `homeroomId` into the mutation.
- [x] 5.3 Update the `weight-matrix.test.tsx` mock to match the new mutation signature.
- [x] 5.4 Verify the weight matrix still hydrates and saves correctly for a class with a single evaluation and for one with multiple evaluations.

## 6. Verification & docs

- [ ] 6.1 Manually verify in the dev environment: open grading entry for class A, change weights, then confirm class B's weights are unchanged (query `report_formula` before/after). _(skipped: manual dev verification — see Manual Backend Tests)_
- [x] 6.2 Add a short recovery note to the change/README or PR description: previously-wiped weights can be rebuilt by re-saving per homeroom or re-running `evaluation-templates/apply`.
- [ ] 6.3 Run backend lint/typecheck (`make dev-backend` boot, or `cargo clippy`) and frontend lint (`npm run lint` / `tsc`) per `AGENTS.md`. _(frontend `tsc` + `eslint` + `vitest` verified green; backend `cargo clippy` skipped — see Manual Backend Tests)_

## Manual Backend Tests

The following backend checks were not executed in this session (require
Docker/testcontainers + a running toolchain). Run them before merging:

```bash
cd apps/backend && cargo test -p grading-service
cd apps/backend && cargo clippy -p grading-service --tests -- -D warnings
```

For the manual cross-homeroom dev verification (task 6.1), boot the stack
(`make dev-backend`), open grading entry for class A, change+save a weight
column, then query `report_formula` to confirm class B's rows are unchanged:

```sql
SELECT e.homeroom_id, rf.evaluation_id, rf.weight
FROM report_formula rf JOIN evaluation e ON e.evaluation_id = rf.evaluation_id
WHERE rf.report_type_id = '<rt>';
```
