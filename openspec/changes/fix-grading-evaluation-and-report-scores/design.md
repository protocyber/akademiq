## Context

`/grading/entry` and `/grading/report-cards` drive evaluation management, grade
entry, live per-subject report scores, and report-card generation in the grading
service. A field report surfaced multiple defects; investigation against the dev
Supabase database (`grading` schema) confirmed they share a single backend root
cause plus several independent UI bugs.

Observed data (dev):

- `evaluation_template` for the active term has one entry: `SAS` (100%).
- `evaluation` table holds `SA` ×74 and `SAS` ×74 — i.e. ~74 assignments carry
  **both** a manually-created `SA` and a template-materialized `SAS`.
- `report_formula` is split: 15 rows point at `SA`, 74 at `SAS` (89 total).
- `subject_report_score`: one homeroom all-positive, two homerooms all-zero,
  others empty — matching the "kosong / nol / 1 mapel" report-card complaints.

Root cause: `materialize_evaluations_for_term` (repo.rs) inserts with
`ON CONFLICT (tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)
DO NOTHING`. The conflict key includes `code`, so the apply action skips only when
an evaluation with the *same code* exists. An assignment that already had `SA`
does not conflict with the template's `SAS`, so `SAS` is inserted anyway. This
contradicts both the button's label ("…yang belum punya evaluasi") and the
`term-evaluation-templates` spec, and diverges from `count_unmaterialized_
assignments`, which already checks "has any evaluation".

Downstream, `compute_subject_score` treats a missing evaluation score as 0, and
`generate_report_cards` only freezes subjects whose `(report_type, subject)`
formula is valid (Σ = 100). With formulas split across two codes and grades
entered against the "wrong" code, scores collapse to 0 or whole subjects are
skipped at generation.

Constraints: backend follows `apps/backend/CONVENTIONS.md` (refinery migrations,
`AppError`, permission-based authz, projection-only cross-service reads, CLI is
thin/operational). Frontend follows `apps/web/CONVENTIONS.md` (shadcn/ui,
TanStack Query, centralized error messages). IAM owns the permission vocabulary;
permissions are platform-owned and not tenant-editable.

## Goals / Non-Goals

**Goals:**
- Stop the backfill from ever adding a second evaluation to an assignment that
  already has one (per-assignment skip).
- Introduce `grade.evaluation.manage` as the authority gate for evaluation
  writes and the `/grading/entry` "Kelola Evaluasi" entry point.
- Eliminate the nested-modal freeze when deleting an evaluation.
- Preserve `/grading/entry` URL filters across browser refresh.
- Remove client-side pagination on `/grading/entry` and `/grading/report-cards`.
- Add a row-number column to the entry grid.
- Provide an operator tool to clean up already-duplicated evaluations and split
  formulas so historical report scores can be corrected.

**Non-Goals:**
- No server-side pagination (explicitly deferred; backend already returns all
  rows for these scopes).
- No automatic data migration that deletes evaluations on deploy (too risky and
  hard to reverse; cleanup is an operator-run, confirmation-gated tool).
- No change to event schemas or the report-card approval workflow.
- No change to the `compute_subject_score`/`formula_is_valid` math itself.

## Decisions

### 1. Per-assignment skip in `materialize_evaluations_for_term`

Change the INSERT…SELECT to filter `teaching_authz` rows with a `NOT EXISTS`
sub-select against `evaluation` for the same `(tenant, homeroom, subject, year,
term)` — the same predicate `count_unmaterialized_assignments` already uses —
instead of relying on the `code`-bearing `ON CONFLICT`. Keep the unique
constraint and `ON CONFLICT … DO NOTHING` as a redundant idempotency guard.

- *Why:* makes the apply action match its label and the spec, and keeps the
  count and the insert in lockstep (single source of "has evaluations").
- *Alternative considered:* drop `code` from the conflict key — rejected; that
  changes the evaluation uniqueness contract and does not express "skip if any
  evaluation exists".

`materialize_evaluations_for_assignment` (the per-`teacher.assigned` path) is
left as-is: it targets a single fresh assignment and the existing conflict-ignore
is correct there. (Confirm during apply that it cannot re-add a code a teacher
later removed; current behavior is acceptable per the grade-capture spec which
allows teacher overrides.)

### 2. New permission `grade.evaluation.manage`

Add the constant to `common-auth`, seed it in a new IAM migration (`V22`) into the
permission table, and grant it to `tenant_admin`, `teacher`, `homeroom_teacher` in
the role-permission seed. Evaluation create/update/delete in the grading service
gate on this permission first; for non-admins the existing assignment-scope check
(`is_assigned_to_scope`) is retained so a teacher can still only manage their own
assignments. The web entry point uses `hasAccessPerm("grade.evaluation.manage")`.

- *Why:* the bug report asks for an explicit permission so the button can be
  hidden when unauthorized; today the gate is role/scope only.
- *Naming:* `grade.evaluation.manage` keeps the `grade.*` namespace consistent
  with `grade.record`/`grade.read`.
- *Alternative considered:* reuse `academic.config.write` (used by apply) —
  rejected; that conflates term-config authority with per-assignment evaluation
  editing and is not granted to teachers.

The `apply_term_template` gate stays on `academic.config.write` (admin-only);
only the per-assignment evaluation CRUD adopts the new permission.

### 3. Nested-modal freeze fix

The Kelola Evaluasi `Dialog` and the delete `ConfirmDialog` (an `AlertDialog`)
are both Radix modals. Opening the AlertDialog while the trash button retains
focus inside the Dialog triggers the `aria-hidden`-on-focused-element warning and
leaves a stale `pointer-events: none` / scroll-lock guard that never clears,
freezing the page. Fix by removing the stacked-modal condition: blur the trigger
before opening the confirm dialog and/or render the confirm dialog outside the
Dialog subtree (and/or set the confirm `AlertDialog` non-modal). The exact
mechanism is pinned during apply, mirroring the approach in the existing
`fix-dialog-combobox-focus-clip` change.

- *Why:* matches the console evidence (`Blocked aria-hidden … descendant retained
  focus`) and the observed "freeze even when I close the confirm" symptom.

### 4. Refresh-redirect fix

`GradeEntryPanel` resets URL params whenever `yearId` changes. On reload,
`useAcademicScope` yields `undefined` first, then the real id; that
`undefined → value` transition is misread as a year change and clears the params,
redirecting to bare `/grading/entry`. Gate the reset so it fires only when both
the previous and next `yearId` are defined and actually differ.

### 5. Remove client pagination

`/grading/report-cards` paginates client-side (`PAGE_SIZE = 10`, `slice`). Remove
the page state, slicing, and pagination control; render the full `statusData`.
`/grading/entry` has no data pagination today — verify and remove any residual
controls. No `page_size` param is sent; the backend already returns all rows.

### 6. Row-number column

Add a leading "No" column to `EvaluationGrid` showing the 1-based row index,
left-aligned with the sticky student column.

### 7. Operator cleanup tool

Add a thin `akademiq` CLI subcommand (or script wrapped by it) that, for a tenant
(and optionally a term), reports assignments holding more than one evaluation and
formulas referencing evaluations that have no grades, then — only with an explicit
confirm flag — deletes the duplicate evaluations (and their dependent grades /
formulas) chosen by a documented rule. It prints the target resources, never
prints secrets, and exits non-zero when nothing changed. Operators re-run
"Generate Draft" afterward to recompute frozen report scores.

- *Why:* fixing the code stops new corruption but does not repair the ~74
  existing duplicates; an automatic destructive migration is too risky.
- *Open:* the selection rule (keep the evaluation that has grades; if both/neither
  have grades, keep the template code and report the conflict for manual review)
  is finalized during apply against the live data.

## Risks / Trade-offs

- [Cleanup deletes the wrong evaluation when both `SA` and `SAS` carry grades] →
  Tool defaults to report-only; deletion requires a confirm flag and prints each
  target; ambiguous cases (grades on both) are listed for manual resolution
  rather than auto-deleted.
- [Per-assignment skip hides legitimately-new template codes from assignments that
  already have evaluations] → Matches the spec's intent (template is a seed only;
  teachers own their lists post-materialization); admins can still add a column
  via Kelola Evaluasi.
- [New permission not present on existing tenant tokens until re-login] → Permission
  is seeded onto built-in roles; tokens refresh on next login. Document that users
  may need to re-authenticate to see the button.
- [Frozen report scores stay wrong until re-generation] → Runbook step: after
  cleanup, re-run Generate Draft for affected `(report_type, classroom)`.

## Migration Plan

1. Ship `common-auth` constant + IAM `V22` permission/role-permission seed
   (idempotent `ON CONFLICT DO NOTHING`).
2. Ship grading-service authz change and the `materialize_evaluations_for_term`
   fix.
3. Ship frontend fixes (freeze, refresh, pagination, row number, permission gate).
4. Run the cleanup tool per affected tenant: report → review → confirm-delete.
5. Re-generate report-card drafts for affected classes.

Rollback: the code changes are independently revertible; the cleanup tool is
manual and makes no changes without the confirm flag, so steps 1–3 can ship
without step 4. No schema is dropped (only a new permission row is added).

## Open Questions

- Final duplicate-selection rule for the cleanup tool when both codes have grades
  (resolve against live data during apply).
- Whether `materialize_evaluations_for_assignment` needs the same per-assignment
  guard, or whether its single-assignment scope makes the current conflict-ignore
  sufficient (verify during apply).
