# Backlog — deferred and out-of-scope items

Items that a design deliberately left out, collected from the specs and plans
so they are not lost when the documents they came from are archived. Each
entry names its source. Remove an entry when it ships or is rejected for good,
and link the spec that picks it up.

3e spec = `docs/superpowers/specs/2026-10-18-promotion-letters-design.md`.

Status words: **planned** (a later plan in the roadmap owns it), **open**
(wanted, no plan yet), **not planned** (decided against; listed so it is not
re-proposed without a new reason).

## Promotion (A1) — product scope

| Item | Status | Source | Notes |
|---|---|---|---|
| Letter template builder (school-editable SK / certificate / custom report-card text) | open | parent spec `2026-09-23-promotion-design.md` §1.1, §8; 3e spec, out of scope | Shared need with custom report cards. 3e hardcodes the letter text. |
| Attendance criterion in promotion rules (`min_attendance_percent`) | planned (after A2) | 3b spec §7; 3d spec §8 | Field exists in the criteria snapshot, always `null`; UI shows it disabled. |
| Separate `promotion` feature code | not planned | 3b spec §7 (§2.3) | Gate is `academic_ops`. |
| Automatic class placement | not planned | parent spec §4.5; 3c spec §8; 3d spec §8 | Placement is per-class defaults + per-student correction. |
| Undoing an executed run | not planned | parent spec §4.1; 3c spec §8; 3d spec §8 | Execution is final; corrections go through normal enrollment edits. |
| Enforcing homeroom capacity | not planned | 3c spec §8 (§2.4) | Capacity is reported only ("Melebihi kapasitas" badge). |
| Graduate statistics in platform-service | open | 3c spec §8 | When a consumer needs them; `student.graduated` already carries the data. |
| Excel export of decisions / placement | open | 3d spec §8 | |
| Playwright e2e for the promotion flow | open | 3d spec §8, §7.3 | Covered by Vitest component tests only. |
| Reconciling `homeroom.grade_level` text with grade-level codes for existing tenants | open (operational) | 3a spec §6; 3b spec §7 | 3d made it a UI task: edit each homeroom and pick its grade level ("Belum tertaut" badge). Needs doing per tenant before their first evaluation. |
| Server-side PDF export of letters | open | 3e spec, out of scope | 3e prints from the browser (`@media print`, A4). |
| Digital signature / QR verification on letters | open | 3e spec, out of scope | |
| Cancelling and re-issuing a letter (with status and history) | open | 3e spec, out of scope (Q4) | 3e allows in-place correction with `updated_by/at`. |
| History of previous letter numbers | open | 3e spec, out of scope | 3e keeps only the current number. |
| Dedicated `promotion.letters` permission | open | 3e spec, out of scope (Q6) | 3e uses `promotion.manage` to issue, manage-or-approve to print. |
| Letter for retained students | not planned | 3e spec, out of scope | They appear on their class SK. |
| Grade transcript attached to the graduation certificate | open | 3e spec, out of scope | |

## Promotion (A1) — accepted UI gaps from Plan 3d

| Item | Source | Notes |
|---|---|---|
| Runs list shows no per-run decision counts | 3d plan "Gaps accepted"; Task 6 review | The list endpoint returns runs only; counts are on the detail page. |
| Cannot-evaluate tab shows no homeroom column | 3d plan "Gaps accepted"; Task 7 review | The API returns student ids only. |
| "Created / approved / executed by" shows dates and "Anda", not names | 3d plan deviations | Names need `GET /tenant-users` (`user.read`), which the principal lacks. |
| Leaving the placement tab warns only on reload / close | 3d plan deviations | App Router has no route-change event to intercept `<Link>` navigation. |
| Editing an unlinked homeroom forces choosing a grade level before any other change saves | 3d Task 3 review | Intended by spec §3.0 (pushes old data to be fixed); relax if admins find it obstructive. |

## Promotion (A1) — deferred review findings (technical debt)

Minor findings that per-task and final reviews judged safe to ship. Ledgers:
`.superpowers/sdd/2026-09-29-promotion-execution/progress.md`,
`.superpowers/sdd/2026-10-12-promotion-ui/progress.md`.

Plan 3c (backend):

- No test for the 2,000-item cap on `PATCH /promotion-runs/:id/targets` (`MAX_TARGET_ASSIGNMENTS`).
- No test seeds a graduate whose status is not `lulus` to exercise the status guard in `apply_status_change` directly.
- `retention_reason` formats the criterion with `{min}` but the average with `{avg:.1}`; fractional thresholds render inconsistently.
- `get_promotion_run` makes two extra round trips (`placement_rows`, `unassigned_count`).

Plan 3d (backend):

- `update_homeroom` does an extra `find` to read the homeroom's year when linking a grade level.
- `DECISION_VIEW_SELECT` is interpolated with `format!`; add a comment that only static WHERE text is concatenated.

Plan 3d (web):

- `useExecutePromotionRun` duplicates the settle/invalidate logic instead of composing `useSettle`.
- No hook-level tests for `use-promotion` queries/mutations (schemas and message helpers are tested).
- `groupBySourceHomeroom`'s `homeroom_name ?? "—"` fallback is untested.
- `CRITERIA_FIELDS` lists `min_attendance_percent`, which `CriteriaForm` does not register (unreachable today).
- `react-hooks/set-state-in-effect` warnings in `runs-screen` (year sync), `criteria-dialog` (reset), `placement-tab` (`yearChoice` resync), `execute-dialog` (reset on open). All convergent; revisit with the React Compiler migration.
- `ActionBar` has no rendered-component test (only `availableActions`).
- Cannot-evaluate tab falls back to the raw student id when a name fetch fails; no "gagal memuat" state.
- Placement `beforeunload` sets only `preventDefault`, not `returnValue`.
- Placement year-change confirmation counts saved targets only (the draft is cleared on success anyway); worth a comment.
- Placement report is a table; spec §5.3 says cards (brief-sanctioned).
- `execute-dialog` uses `key={m}` in the field-group list; identical messages would collide — use an index key.
- No test for the execute dialog's 409 path.

## Pre-existing test failures (not caused by promotion work)

Seen at every promotion final gate; tracked here until someone owns them.

- academic-ops: `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url` (`integration.rs:1960`).
- academic-config: `status_transition_legal_and_illegal_paths`.
- grading: `grade_read_permits_teacher_and_denies_super_admin`, `report_read_permits_teacher_and_denies_super_admin` (409 vs 200; failing since `3c07572`).
- web lint: 7 unused-import errors in `src/app/grading/entry/page.tsx`, `src/app/settings/academic/terms/page.tsx`, `src/app/settings/roles/page.tsx`, `src/components/ui/form.tsx`.
