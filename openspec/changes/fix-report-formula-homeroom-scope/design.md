## Context

The grading service stores report-formula weights in `report_formula(report_type_id,
evaluation_id, weight)`. Because `evaluation` is scoped per
`(tenant, homeroom, subject, year, term)`, a single `(report_type, subject)`
combination legitimately contains evaluation rows from **many homerooms** —
confirmed in the dev database where one `(report_type, subject)` spans up to 6
homerooms.

The upsert endpoint `PUT /report-types/{report_type_id}/formulas/{subject_id}`
(`src/http.rs:69-72`) calls `upsert_report_formula` (`src/repo.rs:933-966`),
which DELETEs by `(report_type, subject)` **without** a homeroom filter before
inserting the new set. The grading entry UI only ever sends one homeroom's
evaluations in the body, so the save silently destroys every other class's
formula rows for that subject/report-type. Read paths (`formula_weights`,
`materialize_weights_for_assignment`) are already homeroom-aware; only the write
path diverged.

This is a dev/demo-stage product (not in production), so an in-place breaking
route change is acceptable and preferred over maintaining a deprecated alias.

## Goals / Non-Goals

**Goals:**
- Make the formula write path homeroom-scoped so saving one class's weights can
  never affect another class.
- Keep the weight-validity rule (sum to exactly 100) but apply it per
  `(report_type, homeroom, subject)`.
- Narrow the post-save live-score recompute to the single affected homeroom.
- Require `grade.evaluation.manage` for concrete formula writes, matching
  evaluation CRUD sensitivity.
- Update the single frontend consumer (grading entry weight matrix) to the new
  homeroom-scoped route.

**Non-Goals:**
- No `report_formula` schema migration — the table already stores per-evaluation
  rows; only write logic changes.
- No change to `report_formula_template` / term-template editing or the
  `evaluation-templates/apply` bulk materialization (both are correct as-is).
- No walikelas assignment feature and no CLI bulk-weight command — those are
  separate changes that build on this fix.
- No production backward-compatibility shim (dev/demo only).

## Decisions

### Decision 1: Refactor the endpoint in place via a path param (no new route)

**Choice:** Replace
`PUT /report-types/{rt}/formulas/{subject_id}` with
`PUT /report-types/{rt}/homerooms/{homeroom_id}/formulas/{subject_id}`.

**Rationale:** The product is pre-production, so a clean break beats leaving a
known-broken route alive. A path segment (over a body field or query param) is
clearest and matches the existing codebase convention
(`/homerooms/:homeroom_id/roster`). It also makes the `(report_type, homeroom,
subject)` scope explicit in the URL, which is exactly the scope the upcoming CLI
bulk-weight command needs.

**Alternatives considered:**
- *New endpoint + leave old one returning 410:* safer for production, but
  unnecessary complexity for dev/demo. The old route has exactly one frontend
  consumer, so direct refactor is simpler.
- *Body field `homeroom_id`:* keeps the path stable but hides the scope in the
  body, inviting the same misuse again. Rejected.

### Decision 2: DELETE-and-replace scoped to the homeroom

**Choice:** The repo `upsert_report_formula` gains a `homeroom_id` argument and
its DELETE becomes:

```sql
DELETE FROM report_formula rf
USING evaluation e
WHERE rf.report_type_id = $1
  AND rf.evaluation_id = e.evaluation_id
  AND e.homeroom_id = $2
  AND e.subject_id = $3
```

**Rationale:** Mirrors the existing read query `formula_weights` (`repo.rs:985-996`)
which already filters by `(report_type, homeroom, subject)`. This makes read and
write scopes identical.

### Decision 3: Narrow the recompute to the affected homeroom

**Choice:** After a weight write, recompute only for the single `homeroom_id`
rather than iterating `homerooms_for_subject_formula` (which returns all
homerooms for that `(report_type, subject)`).

**Rationale:** Only that homeroom's weights changed, so only its live scores and
draft report cards can be affected. This is also a performance win. The existing
`recompute_subject_live_scores_batch` (`commands.rs:1346`) is refactored to
accept an explicit `homeroom_id` (or a new single-homeroom variant is added).

### Decision 4: Mirror evaluation-CRUD authorization for formula writes (folded into this change)

**Observation:** The handler currently does not call `require_permission` — any
valid tenant JWT with the grading feature entitled can write weights. This is an
authorization gap: a student, parent, or unassigned teacher could manipulate the
weights that determine final report-card scores. It is more severe than the
homeroom-scope bug because it permits *intentional* manipulation.

**Choice:** Formula writes MUST follow the exact same two-layer authorization
that evaluation CRUD already uses (`commands.rs:62-124`, `151-196`, `220+`):

1. **Permission gate** — `require_grade_evaluation_manage(&perms)`. The
   `grade.evaluation.manage` permission is granted to `tenant_admin`,
   `teacher`, and `homeroom_teacher` (IAM migration V22), so assigned teachers
   keep access.
2. **Assignment-scope gate** — `tenant_admin` bypasses; otherwise the caller
   MUST be assigned to the `(subject, homeroom, academic_year)` scope via
   `is_assigned_to_scope(...)` (else HTTP 403 `NOT_ASSIGNED`).

So the handler/command needs `user_id` and `roles` (already on the JWT) in
addition to `perms`. After the route refactor, `homeroom_id` and `subject_id`
are path params and `academic_year_id` is resolved from the fetched
`report_type` — all four scope dimensions are available for the assignment
check.

**Rationale:** Changing concrete formula weights is the same authority level and
scope as creating/editing evaluations — both are grade-configuration operations
that affect how scores compute, and both belong to the assigned teacher (or
admin). Mirroring the existing, already-tested pattern is lower-risk than
inventing a new gate. Folding it into this change is near-zero incremental cost
since we already touch the handler and command.

**Frontend impact:** The grading entry weight matrix is gated on
`canManageEvaluations` (`entry/page.tsx:150`), which already combines
`isTenantAdmin || isAssignedUser` with `hasAccessPerm("grade.evaluation.manage")`.
So no UI visibility change is expected; the backend simply starts enforcing what
the UI already assumes. Callers lacking the permission or assignment receive
HTTP 403 `FORBIDDEN` / `NOT_ASSIGNED`.

## Risks / Trade-offs

- **[BREAKING route change]** → The one frontend consumer is updated in the same
  change. Any other caller (none found in the web app or CLI) would get HTTP 404
  on the old path, failing safe rather than corrupting data.
- **[Existing dev data may have drifted weights]** → Past saves may have already
  wiped some classes' weights. This change prevents *future* corruption but does
  not repair historical loss. Affected rows can be rebuilt by re-saving weights
  per homeroom or by re-running `evaluation-templates/apply` (which only fills
  gaps, `ON CONFLICT DO NOTHING`). → Document a manual recovery note.
- **[Permission gate could block an existing UI caller]** → Verify the grading
  entry page is visible only to users with `grade.evaluation.manage`; add a test
  that a caller without the permission receives HTTP 403.
- **[Test helper `put_formula` covers only single-homeroom]**
  → A new multi-homeroom regression test is required (see tasks) to lock the fix.
