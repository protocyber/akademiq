## Why

The `add-academic-term` work let academic-config and grading pick a term's
`term_id` independently during backfill: academic-config seeds the default term
with `gen_random_uuid()` (the source of truth) while grading derives it as
`md5(academic_year_id)::uuid`. For any year that predates the feature these IDs
never match, so the real `term_id` the web sends never resolves in grading's
`valid_term` projection. Verified in a live tenant: academic-config term
`091a02f2…` (Active) vs grading rows all carrying the ghost `9aa7758f…`.

This single root cause produces three user-visible failures:
- creating/editing an evaluation on a genuinely Active term returns
  `TERM_NOT_EDITABLE` ("term not found or not editable");
- report types exist but are stamped with the ghost `term_id`, so the report
  board shows "Belum ada jenis rapor untuk tahun ini" even though they exist;
- historical evaluations/grades point at a phantom term and disappear when
  queried by the real `term_id`.

## What Changes

- **BREAKING (data heal):** stop grading from fabricating `term_id`. Remove the
  `md5(academic_year_id)::uuid` derivation from grading command/query fallbacks;
  a `term_id` may only enter grading through the
  `academic_term.created` / `academic_term.status_changed` projection.
- The grading fallback for an omitted `term_id` resolves a real projected term
  (deterministic selection) instead of inventing one.
- academic-config gains a one-shot republish of `academic_term.created` for all
  existing terms so grading's `valid_term` is populated with real IDs.
- A grading reconcile operation (CLI), run after the republish, remaps existing
  `evaluation`/`report_type` rows from the ghost `md5(year)` id to the real
  `term_id` using the corrected `valid_term` as the `year → real term_id` map,
  then deletes the ghost `valid_term` rows. Idempotent; exits non-zero when
  nothing changed.

## Capabilities

### New Capabilities
- `term-id-reconciliation`: one-time heal of divergent `term_id` values across
  academic-config and grading (republish + reconcile), plus the forward-fix
  invariant that grading never fabricates a `term_id`.

### Modified Capabilities
- `grading-service-grade-capture`: evaluation/report-type/grade gates resolve
  `term_id` strictly from the `valid_term` projection; the omitted-`term_id`
  fallback selects a real projected term instead of `md5(year)`.
- `academic-config-service`: adds an operation to republish
  `academic_term.created` for all existing terms via the transactional outbox.

## Impact

- Backend submodule `apps/backend`, branch context `feat/add-academic-term`.
- `services/grading-service`: `commands.rs`, `queries.rs`, migrations
  (`V7`/`V8` lineage), new reconcile path; `akademiq` CLI command.
- `services/academic-config-service`: `commands.rs` (republish), outbox.
- No web changes required; the bug is entirely backend data/logic.
- Operational: heal runs once per environment (republish → reconcile); ordering
  matters (republish must complete before reconcile).
