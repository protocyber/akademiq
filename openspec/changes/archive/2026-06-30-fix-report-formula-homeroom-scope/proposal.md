## Why

The report-formula weight endpoint `PUT /report-types/{report_type_id}/formulas/{subject_id}`
destroys weights for **other homerooms** when saving weights for one class. The
underlying DELETE replaces all `report_formula` rows matching
`(report_type, subject)` with no homeroom filter, so saving a single class's
weights wipes the formula rows of every other class teaching that subject under
the same report type. This is an active data-corruption bug: the dev Supabase
database has 14 `(report_type, subject)` combinations spanning multiple
homerooms (61 homeroom-evaluations total) that are all vulnerable. It must be
fixed before the CLI bulk-weight feature can build on this endpoint.

## What Changes

- **BREAKING** — Refactor the formula upsert endpoint in place to be
  homeroom-scoped via a path parameter:
  `PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`.
- The repo DELETE inside `upsert_report_formula` MUST filter by `homeroom_id`
  (in addition to `report_type_id` and `subject_id`) so only that class's
  formula rows are replaced.
- The live-score recompute following a weight change MUST be narrowed to the
  affected homeroom instead of scanning every homeroom that participates in the
  `(report_type, subject)` formula.
- Formula writes MUST require the same authorization as evaluation CRUD:
  the `grade.evaluation.manage` permission **plus** an assignment-scope check
  (`tenant_admin`, or the caller is the teacher assigned to that
  `subject + homeroom + year`). A valid tenant token plus grading feature
  entitlement alone is not sufficient.
- The grading entry UI ("Kelola Evaluasi" weight matrix) MUST send the active
  `homeroom_id` via the new path segment. The body stays `{ weights }` keyed by
  evaluation id.
- The `GET /report-types/{report_type_id}/formulas` list endpoint is unchanged
  (it remains report-type-scoped; callers filter by homeroom client-side as
  today).

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `report-card-workflow`: The per-report-type weighting requirement changes
  scope. Weights are now set per `(report_type, homeroom, subject)` via a
  homeroom-scoped path, not per `(report_type, subject)`. The DELETE-and-replace
  semantics are confined to the single homeroom's evaluations so other classes'
  weights are never destroyed. The "sum to exactly 100" validity rule still
  applies per `(report_type, homeroom, subject)`. Additionally, formula writes
  are now gated behind `grade.evaluation.manage` **plus** an assignment-scope
  check, mirroring evaluation CRUD (closing an authorization gap where any
  tenant token could previously change weights).

## Impact

- **Backend `grading-service`**: `src/http.rs` (route shape + handler +
  permission gate), `src/repo.rs` (`upsert_report_formula` DELETE filter),
  `src/commands.rs` (`upsert_report_formula` +
  `recompute_subject_live_scores_batch` narrowing), trait `GradeRepository`
  signature.
- **Backend tests**: `grading-service/tests/integration.rs` `put_formula` helper
  and the multi-evaluation formula tests must cover the multi-homeroom case.
- **Frontend `apps/web`**: `src/app/grading/entry/page.tsx` (weight-matrix save)
  and `src/lib/query/mutations/use-grading.ts` (`useUpsertReportFormula`) to use
  the homeroom-scoped path.
- **No DB migration** — the `report_formula` table shape is unchanged; only the
  write/read logic around it changes. Existing data remains valid.
- **Out of scope**: `report_formula_template` (term-template editing),
  `evaluation-templates/apply` (bulk materialization), and the walikelas / CLI
  bulk-weight features — these are separate changes.

## Recovery for previously-wiped weights

This fix prevents **future** cross-homeroom data loss but does not repair
historical loss. Any class whose weights were wiped by a prior save can be
rebuilt in either of two ways:

1. **Re-save per homeroom** — open Grading → Kelola Evaluasi for the affected
   class and save its weight column via the new homeroom-scoped endpoint.
2. **Re-run `evaluation-templates/apply`** — the bulk materialization only
   fills gaps (`ON CONFLICT DO NOTHING`), so re-applying term templates restores
   missing `report_formula` rows without overwriting existing weights.

