## Why

The grade-entry and report-card flow has a cluster of related defects that
culminate in wrong or empty report scores. Investigating the dev Supabase data
confirmed a single root cause: the "Terapkan ke semua penugasan yang belum punya
evaluasi" backfill skips per evaluation **code** instead of per **assignment**.
Because most assignments already had a manually-created `SA` evaluation, applying
the `SAS` template inserted a *second* evaluation into ~74 assignments and split
the 89 report formulas across two codes. Scores are then computed against an
evaluation that has no grades (treated as 0), so report cards come out empty,
all-zero, or showing only one subject. Several UI bugs on the same screen
(delete-evaluation freeze, refresh redirect, client pagination, missing row
numbers, and a missing permission gate) compound the pain.

## What Changes

- Fix the backfill so applying a term template inserts evaluations **only** into
  teaching assignments that currently have **no** evaluations at all
  (per-assignment skip), matching the existing `term-evaluation-templates`
  spec and keeping it in lockstep with the unmaterialized-assignment count.
- Add a new platform permission `grade.evaluation.manage` and seed it to
  `tenant_admin`, `teacher`, and `homeroom_teacher`. Make it the primary gate for
  evaluation create/update/delete; retain the existing assignment-scope check for
  non-admins. The `/grading/entry` "Kelola Evaluasi" button is hidden when the
  signed-in user lacks the permission.
- Fix the delete-evaluation freeze: opening the confirm dialog while the Kelola
  Evaluasi dialog is open leaves a stale `pointer-events: none`/`aria-hidden`
  guard on the page (nested Radix modals), killing all clicks.
- Fix the refresh redirect: `/grading/entry` must keep its `homeroom_id`/
  `subject_id` URL params on reload and only clear them on a genuine academic-year
  change, not during the initial `undefined → value` hydration of the scope.
- Remove client-side pagination from `/grading/entry` and
  `/grading/report-cards`; render all rows the backend already returns.
- Add a row-number column to the `/grading/entry` grid.
- Provide an operator tool to detect and remove the duplicate evaluations and
  orphaned/ split formulas already created in existing databases, with
  confirmation, so historical report scores can be corrected. **(operational —
  run by the maintainer, not automatic)**

## Capabilities

### New Capabilities
- `grading-evaluation-cleanup`: an operator CLI/script that detects duplicate
  concrete evaluations per assignment and split/orphaned report formulas, reports
  them, and removes them only on confirmation (non-zero exit when nothing changed,
  no secrets in output).

### Modified Capabilities
- `term-evaluation-templates`: sharpen the backfill requirement so the apply
  action skips an assignment when it already has **any** evaluation (not merely a
  same-coded one), keeping behavior consistent with the unmaterialized count.
- `grading-service-grade-capture`: evaluation create/update/delete writes are
  gated by the new `grade.evaluation.manage` permission as the primary authority,
  with the assignment-scope check retained for non-admins.
- `iam-service`: add `grade.evaluation.manage` to the platform permission
  vocabulary and seed it onto `tenant_admin`, `teacher`, and `homeroom_teacher`.
- `web-grading-entry`: the Kelola Evaluasi entry point is gated by
  `grade.evaluation.manage`; the grid shows a row-number column; the screen
  preserves URL filters across refresh; deleting an evaluation never freezes the
  page.
- `web-report-cards`: the report board lists all rows for the selected scope with
  no client-side pagination.

## Impact

- Backend `grading-service`: `repo.rs` (`materialize_evaluations_for_term`),
  `commands.rs`/`http.rs` evaluation write authorization.
- Backend `iam-service`: new permission seed migration (`V22`) and role-permission
  seed; `common-auth` permission constant.
- Frontend `apps/web`: `app/grading/entry/page.tsx`,
  `app/grading/report-cards/page.tsx`, the shared confirm/alert-dialog usage, and
  a permission helper (`lib/auth/access-claims.ts`).
- Operations: new cleanup command/script and a short runbook for correcting
  existing tenant data; affected tenants must re-generate report-card drafts after
  cleanup.
- No public API contract changes; no event schema changes.
