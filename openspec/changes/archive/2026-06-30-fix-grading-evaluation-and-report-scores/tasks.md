# Tasks

## 1. IAM permission (`grade.evaluation.manage`)

- [x] 1.1 Add `PERM_GRADE_EVALUATION_MANAGE = "grade.evaluation.manage"` constant to `apps/backend/libs/common-auth/src/jwt.rs` and re-export it in `lib.rs`.
- [x] 1.2 Add IAM migration `V22__seed_grade_evaluation_manage_permission.sql` inserting the permission row (deterministic UUID, `ON CONFLICT (code) DO NOTHING`).
- [x] 1.3 In the same or a paired migration, seed `role_permission` for `tenant_admin`, `teacher`, `homeroom_teacher` (`ON CONFLICT DO NOTHING`).
- [ ] 1.4 Run `make migrate` (or service migrate) against a dev DB and verify the permission and grants exist; confirm a fresh token for each role carries `grade.evaluation.manage` in `perms`. Skipped: backend migration/dev DB verification must be run manually.

## 2. Backend — evaluation write authorization

- [x] 2.1 Gate `create_evaluation`, `update_evaluation`, `delete_evaluation` in `grading-service/src/commands.rs` on `grade.evaluation.manage` (return 403 `FORBIDDEN` when absent), keeping the existing non-admin `is_assigned_to_scope` check (403 `NOT_ASSIGNED`).
- [x] 2.2 Thread `perms` from the request extractor into the evaluation command inputs in `http.rs` where not already present.
- [ ] 2.3 Update/extend grading-service tests to cover: authorized admin, authorized assigned teacher, missing-permission 403, and authorized-but-unassigned 403. Skipped: backend test implementation/execution must be handled manually.

## 3. Backend — per-assignment backfill fix

- [x] 3.1 Rewrite `materialize_evaluations_for_term` (repo.rs) to insert only for `teaching_authz` rows with `NOT EXISTS` any `evaluation` for `(tenant, homeroom, subject, year, term)`; keep the unique constraint + `ON CONFLICT DO NOTHING` as a redundant guard.
- [ ] 3.2 Confirm the new predicate matches `count_unmaterialized_assignments`; add a regression test that an assignment with a different-coded evaluation (`SA` vs template `SAS`) is skipped and reported. Skipped: backend regression test implementation/execution must be handled manually.
- [ ] 3.3 Add an idempotency test: applying twice creates nothing on the second run. Skipped: backend regression test implementation/execution must be handled manually.
- [x] 3.4 Decide and document whether `materialize_evaluations_for_assignment` needs the same per-assignment guard (per design Open Questions); adjust if required. Decision: keep as-is because it targets a single fresh assignment and teacher overrides remain allowed.

## 4. Backend — operator cleanup tool

- [x] 4.1 Add an `akademiq` CLI subcommand (report mode default) that lists assignments holding >1 evaluation and formulas referencing gradeless evaluations, scoped by tenant and optional term.
- [x] 4.2 Add a `--execute` flag that deletes the gradeless duplicate evaluation and its dependent grades/formula rows; keep the graded one.
- [x] 4.3 When both/neither duplicate has grades, skip deletion and report for manual review; exit non-zero on a confirmed no-op.
- [x] 4.4 Ensure output prints target ids/codes and never secrets; add a short runbook note (where the command lives + post-cleanup "Generate Draft" step).

## 5. Frontend — grade-entry fixes

- [x] 5.1 Gate the "Kelola Evaluasi" button in `app/grading/entry/page.tsx` on `hasAccessPerm("grade.evaluation.manage")` in addition to existing conditions.
- [x] 5.2 Fix the refresh redirect: only clear `homeroom_id`/`subject_id` when `yearId` changes between two defined values; skip the `undefined → value` hydration transition.
- [x] 5.3 Fix the delete-evaluation freeze (nested Radix Dialog + AlertDialog): blur the trigger before opening confirm and/or render the confirm dialog outside the Dialog subtree and/or make it non-modal — verify no stale `pointer-events`/`aria-hidden` remains after confirm and after cancel.
- [x] 5.4 Add a leading row-number ("No") column to `EvaluationGrid`.

## 6. Frontend — remove client pagination

- [x] 6.1 Remove `PAGE_SIZE`, page state, slicing, and the pagination control from `app/grading/report-cards/page.tsx`; render the full `statusData`.
- [x] 6.2 Verify `/grading/entry` has no residual data pagination; remove any leftover controls. Do not send a `page_size` param.

## 7. Verification

- [ ] 7.1 Backend: `cd apps/backend && make test` (grading-service + iam-service) passes. Skipped: backend test command must be run manually.
- [x] 7.2 Frontend: `cd apps/web && <lint/typecheck/test>` passes for the touched files.
- [ ] 7.3 Manual/dev: against dev Supabase, confirm apply no longer creates a second evaluation; run the cleanup tool (report → confirm) on the affected tenant; re-generate report drafts and confirm scores populate for previously empty/zero classes. Skipped: backend/dev Supabase verification must be run manually.
- [ ] 7.4 Manual: refresh `/grading/entry?homeroom_id=...&subject_id=...` keeps the scope; delete an evaluation without freezing; row numbers and full lists render; button hidden without the permission. Skipped: browser/manual UI verification must be run manually.

## Manual Backend Tests

- `cd apps/backend && make migrate`
- `cd apps/backend && make test`
- Against dev Supabase: confirm apply no longer creates a second evaluation; run `cargo run -p akademiq-cli -- grading cleanup-evaluations --tenant-id <tenant-id> [--term-id <term-id>]`, then rerun with `--execute`; re-generate report drafts and confirm scores populate.
