## Context

Subjects today sit directly under a curriculum version:

```text
Academic Year
└─ Curriculum Version
   └─ Subject { name, code, passing_grade }
```

Grading, teaching assignments, report formulas, and report scores all key on
`subject_id`. The web renders subjects as a flat table and report cards list
subject scores with no grouping.

Schools want tenant-defined **kelompok mata pelajaran** (subject groups) above
subjects purely for report-card presentation (e.g. "Kelompok A", "Muatan
Lokal"). Grading behavior must not change — groups are presentation metadata.

Current implementation reference points:
- `academic-config-service/migrations/V1__init.sql` — `curriculum_version`,
  `subject` tables.
- `academic-config-service/src/{domain,repo,commands,queries,http}.rs` —
  existing resource pattern (CRUD, tenant scope, list/sort/page, all-or-nothing
  bulk delete, `*_IN_USE` guards via local usage projections).
- Web: `apps/web/src/app/settings/academic/subjects/page.tsx`,
  `use-academic-config.ts` (queries/mutations), `subject.ts` (schemas),
  `academic-settings.tsx` (nav).
- Grading/report cards: `06_Grading_Service_ERD.md`, `web-report-cards/spec.md`.

## Goals / Non-Goals

**Goals:**
- Introduce `subject_group` as a tenant-defined, per-curriculum-version layer.
- Require every subject to belong to exactly one group.
- Auto-create one default group ("Umum") on curriculum-version creation.
- Keep grouping metadata-only: zero impact on scores, formulas, evaluations,
  teaching assignments, or entitlements.
- Render report cards (web + portal) grouped by kelompok.

**Non-Goals:**
- No per-group passing-grade, weight, or grading policy.
- No cross-curriculum or cross-year group templates/inheritance.
- No group-level teacher assignment or permissions.
- No grouping in the grade-entry grid (only in report cards).

## Decisions

### D1: Group lives in academic-config, not grading

`subject_group` is owned by `academic-config-service` alongside
`curriculum_version` and `subject`. Grading never stores group ids; report
rendering resolves group metadata from academic-config (web joins client-side
from the subject list it already fetches). **Why:** keeps grading schema
untouched and preserves the projection boundary. **Alternative considered:**
denormalize `subject_group_id` into grading — rejected, it would couple score
tables to presentation metadata and require event syncing.

### D2: Subject carries a required, mutable `subject_group_id`

`subject.subject_group_id` is `NOT NULL` after migration. `POST`/`PATCH`
subject accept `subject_group_id`; UI defaults the selector to the first group
or "Umum". A subject can move between groups via `PATCH`. **Why:** simplest
model that satisfies "every subject has a group" while allowing re-grouping.
**Alternative:** nullable column with a synthetic "ungrouped" bucket at render
time — rejected because the user decided groups are mandatory.

### D3: Default group auto-created on curriculum-version creation

`add_curriculum_version` command inserts one `subject_group` named by the
constant `DEFAULT_SUBJECT_GROUP_NAME = "Umum"` at `position = 1` in the same
transaction. The constant lives in `academic-config-service/src/domain.rs` (or
a small `constants` module) as a single source of truth. **Why:** guarantees
the invariant "every curriculum version has ≥1 group" so subjects can always be
created. **Alternative:** lazy-create on first subject — rejected, violates the
mandatory invariant and complicates UI (empty group list on new curriculum).

### D4: Group identity is `(curriculum_version_id, code)` unique, nullable code

`code` is optional like subject `code`; uniqueness when present is
`(tenant_id, curriculum_version_id, code)`. `position` is an integer the user
sets/reorders; it is not auto-managed gaps (keep parity with existing
`position` fields on evaluation/report-type). **Why:** matches existing
conventions; avoids a complex linked-list ordering scheme.

### D5: Delete guards mirror existing pattern

`DELETE /subject-groups/{id}` and bulk delete reject with `SUBJECT_GROUP_IN_USE`
(409) when the group still has subjects. No event/projection needed — the
subjects live in the same database, so a direct count suffices (unlike the
cross-service `SUBJECT_IN_USE` / `YEAR_IN_USE` guards).

### D6: Migration backfills existing subjects into an auto-created default group

Migration steps:
1. Create `subject_group` table.
2. For each existing `curriculum_version`, insert one "Umum" group at
   `position 1` (same constant value, applied as a literal in SQL).
3. Add `subject.subject_group_id` column (nullable first).
4. Backfill each subject to its curriculum version's default group.
5. `ALTER ... SET NOT NULL`.
6. Add FK `subject.subject_group_id → subject_group(subject_group_id)
   ON DELETE RESTRICT` (RESTRICT because deletes are guarded in-app and we
   never want silent cascade).

Dev-reset is acceptable per existing migration precedent.

### D7: Report-card grouping resolved client-side

The web already loads the subject list (with group metadata after this change)
for the selected curriculum version. Report-card detail and the parent portal
group `report_subject_score` rows by `subject → subject_group`, ordered by
`group.position` then subject name. No grading API change required.
**Alternative:** grading returns pre-grouped payload — rejected, YAGNI and
couples grading to presentation.

## Risks / Trade-offs

- **[Backfill correctness]** Existing subjects must all land in a group before
  the `NOT NULL` constraint. → Migration step 2 guarantees a default group per
  curriculum version before the backfill; integration test asserts zero
  null-group subjects post-migration.
- **[Breaking subject API]** Clients sending the old shape (no
  `subject_group_id`) will fail. → Bump in lockstep with the web; document the
  breaking change in the API contract doc; backend returns `VALIDATION_ERROR`
  with a `subject_group_id` field error.
- **[Group with subjects deleted out-of-band]** Direct SQL could orphan a
  subject. → FK `ON DELETE RESTRICT` plus app guard; no other writers exist.
- **[Reorder complexity]** Manual `position` integers can collide/desync.
  → Acceptable for v1; a future change can add drag-drop normalization. Keep
  parity with how evaluation/report-type positions work today.

## Migration Plan

1. Merge backend migration + code first; deploy.
2. Deploy web update in the same release window (API is breaking).
3. Verify: every curriculum version shows the default "Umum" group; existing
   subjects appear under it.
4. Rollback: revert migration is non-trivial (column drop + table drop). Keep
   the change behind a single release; if needed, `subject.subject_group_id`
   can be re-nullable but the table can stay — groups are inert without UI.

## Open Questions

- Should group `position` support fractional/gap values or strict integers?
  (Proposed: integers, parity with evaluation/report-type.)
- Bulk-move subjects between groups (multi-select → change group)? Nice-to-have
  for v2; not in initial scope.
