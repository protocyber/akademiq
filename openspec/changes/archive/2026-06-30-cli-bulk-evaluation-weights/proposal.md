## Why

When a teaching assignment has exactly one evaluation for a subject in a given
term, the correct weight for that evaluation is always 100% — there is nothing
else to distribute. In practice, many assignments are in this state after
materialization (especially when schools use a single "SAS" evaluation per
subject per term), yet their `report_formula.weight` is left unset or at a
non-100 value from the template, causing those subjects to show no live score
and no frozen score on the rapor. Setting weights manually for dozens of classes
and subjects is tedious. A CLI command to bulk-fix this in one step — and
immediately recompute all affected scores — eliminates the manual work.

This change depends on `fix-report-formula-homeroom-scope` being deployed first,
because it calls the corrected homeroom-scoped formula endpoint to set weights
and trigger recompute.

## What Changes

- Add a new `akademiq grading set-single-eval-weights` subcommand to the
  `akademiq-cli` binary.
- The command finds all `(homeroom, term, subject)` scopes in the grading
  database that have **exactly one** concrete `evaluation` row, then calls the
  grading service HTTP endpoint
  `PUT /report-types/{rt}/homerooms/{homeroom}/formulas/{subject}` with
  `{ weights: { <evaluation_id>: 100 } }` for each affected `(report_type,
  homeroom, subject)` combination.
- The endpoint enforces the sum-to-100 rule, persists the weight, and
  recomputes all live and frozen rapor scores atomically — no separate recompute
  step needed.
- The command operates in **dry-run mode by default**; `--execute` is required
  to apply changes. `--yes` skips the interactive confirmation prompt.
- Optional `--tenant <uuid>` and `--term <uuid>` flags narrow the scope.
- The command exits non-zero if no rows would be changed (nothing to fix).

## Capabilities

### New Capabilities

- `cli-grading-bulk-weights`: Operator CLI command that identifies single-evaluation
  assignments and bulk-sets their formula weight to 100% via the grading service
  HTTP API, triggering automatic score recompute.

### Modified Capabilities

_(none)_

## Impact

- **`apps/backend/tools/akademiq-cli/src/main.rs`**: new `SetSingleEvalWeights`
  subcommand under `GradingCommands`; adds HTTP client dependency (`reqwest`)
  and auth token plumbing (`--grading-url`, `--token` / `GRADING_AUTH_TOKEN`).
- **Depends on**: `fix-report-formula-homeroom-scope` (homeroom-scoped endpoint
  must exist); grading service must be running and reachable.
- **No DB migration**, no frontend change, no other service change.
