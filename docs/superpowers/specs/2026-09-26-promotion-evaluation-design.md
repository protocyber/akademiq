# Design Spec: Promotion Evaluation Engine (Plan 3b)

**Status:** approved
**Date:** 2026-09-26
**Parent spec:** `docs/superpowers/specs/2026-09-23-promotion-design.md` (A1)
**Depends on:** Plan 3a (`docs/superpowers/specs/2026-09-24-promotion-foundation-design.md`)

---

## 1. Why this plan exists

Plan 3a gave the engine every fact it needs: the grade-level ladder as a
projection, homerooms linked to it, frozen report scores, the KKM policy, five
promotion tables, and the `promotion.manage` / `promotion.approve` permissions.
It deliberately computed nothing.

This plan makes the engine compute. It turns a set of criteria plus a year's
published report cards into one `promotion_decision` row per student, lets a
human override any row with a written reason, and moves the run through
`draft → submitted → approved`.

### 1.1 What this plan deliberately does NOT do

- **No execution.** Nothing moves a student into next year's homeroom, closes an
  enrollment, or writes `graduation_record` / `retention_record`. That is Plan 3c.
- **No `PUT /homeroom-map`.** Target homeroom mapping is an execution concern;
  `promotion_decision.target_homeroom_id` stays NULL throughout 3b.
- **No attendance criterion.** See §3.1.
- **No web UI.** Backend only.

---

## 2. Decisions

### 2.1 `min_attendance_percent` is rejected on write, not silently skipped

`promotion_rule_snapshot.min_attendance_percent` exists (Plan 3a, migration V16)
because the parent spec §3 specified it. But **no attendance data exists**: A2
(attendance) has not been built, and academic-ops has zero attendance tables.

A rule that carries a non-NULL `min_attendance_percent` is **rejected at the
command layer** with `VALIDATION_ERROR` and a field message saying the criterion
is not available yet. The column stays, waiting for A2.

Rejected alternatives:

- *Accept and skip during evaluation.* A school sets 80%, expects truants to be
  retained, and nobody is. The parent spec §4.2 names this class of failure as
  something that "permanently destroys a school's trust". Directly forbidden.
- *Accept and block evaluation.* Stores a value that silently disables the whole
  feature the moment it is set — a landmine in a settings form.

When A2 lands, exactly one guard is removed.

### 2.2 The promotion-source report type comes from a projection, not a snapshot flag

The engine must know **which report type decides promotion** for the year.

`known_report_score.is_promotion_source` (Plan 2) is a snapshot taken at publish
time, and its own column comment says it is "for audit and debugging only". The
flag is mutable after publication: `grading-service`'s update command
(`services/grading-service/src/commands.rs:1053`) can move
`report_type.is_promotion_source` to a different report type once cards are out.

A correction to the record: the comment in
`services/academic-ops-service/migrations/V13__known_report_score.sql` says the
engine "asks academic-config for the CURRENT flag". That is wrong on two counts.
`is_promotion_source` does not exist anywhere in academic-config — it lives in
**grading-service**, added by `V12__report_type_promotion_source.sql`. And there
was no path to ask: grading-service published exactly one event
(`report_card.published`), and academic-ops had no `known_report_type`
projection. Direct HTTP between services is forbidden by
`apps/backend/CONVENTIONS.md`, so the instruction in that comment was
unreachable. **Fix the comment as part of this plan.**

So this plan builds the missing path:

1. `grading-service` publishes `report_type.promotion_source_changed` through the
   **outbox, inside the same transaction** as the flag write.
2. `academic-ops` projects it into `known_report_type`.
3. The engine reads `known_report_type` for the current truth.

This is the only option that satisfies `CONVENTIONS.md` and closes a real
correctness hole rather than a hypothetical one.

Rejected alternatives:

- *Filter `known_report_score` on the snapshot flag.* Zero new work, but a school
  that moves the flag after publishing gets evaluated against the wrong report
  type with no warning — the exact silent failure §4.2 forbids.
- *Make `report_type_id` an operator-supplied parameter.* Pushes correctness onto
  an admin who has no way to see which flag is active. Hides an architecture gap
  behind a dropdown.

**Scope note:** this is the one place where Plan 3b reaches outside
academic-ops. Touching grading-service was explicitly approved.

### 2.3 Promotion is guarded by the existing `academic_ops` feature code

The parent spec §6 says promotion endpoints are "guarded by feature code
`promotion`". This plan **deviates**: they use the existing
`AcademicOpsFeature` (`CODE = "academic_ops"`, `services/academic-ops-service/src/http.rs:29`),
the same guard the service's other ~12 write handlers already use.

Reasoning:

- Feature code `promotion` is registered nowhere — zero rows in `plan_feature`,
  zero references in billing-service. Adding the marker without seeding billing
  would make every promotion endpoint return 403 `FEATURE_NOT_AVAILABLE` for
  every tenant: a feature that is built and dead.
- Seeding it properly means a billing-service migration, which would make one
  plan change three services (academic-ops + grading + billing).
- AkademiQ's plans have no such fine-grained tiering yet, so a separate code
  solves a problem that does not exist.
- Splitting the code out later is a one-line marker swap per handler. Retrofitting
  a broken guard is not.

### 2.4 Criteria arrive in the request body and are frozen immediately

There is **no editable promotion-rule table** — only `promotion_rule_snapshot`.
That is intentional per the parent spec: rules are frozen when a run executes so
old decisions stay explainable after the school changes its mind.

Therefore `POST /promotion-runs` carries the criteria in its body. The handler
writes one `promotion_rule_snapshot` row and one `promotion_run` row referencing
it, in a single transaction. Re-running an evaluation writes a **new** snapshot.

`kkm_snapshot` is NOT NULL and is **not** client-supplied: it is read from
`known_grading_policy.minimum_passing_score` for the tenant and year. If no
policy row exists, the run is **rejected** — the engine will not invent a passing
score.

### 2.5 `promotion_run` needs `report_type_id` (migration V17)

`promotion_run` has no `report_type_id` column (Plan 3a, V16). Without it a run
cannot be explained after the fact: "which report card produced these scores?"
becomes unanswerable once the flag moves.

V17 adds `report_type_id UUID NOT NULL` to `promotion_run`, resolved from
`known_report_type` at run creation. Since existing rows are impossible (no run
can have been created yet — no code path exists), the column is added NOT NULL
with no backfill. The migration must still be re-runnable.

### 2.6 A missing `grade_level_id` and a dangling one are the same failure

Carried from Plan 3a's debt #13. `homeroom.grade_level_id` has **no foreign key**
to `known_grade_level` (deliberately — a projection can lag). So the column can
be non-NULL and still point at a deleted projection row.

The readiness check **must treat a dangling reference exactly like NULL** and
refuse to evaluate. Checking `IS NOT NULL` alone would silently evaluate a
homeroom whose grade level no longer exists. The implementation joins to
`known_grade_level` and requires a matching row; a test proves a homeroom with a
non-NULL but unmatched `grade_level_id` is reported as not-ready.

### 2.7 Students who cannot be evaluated are listed, never assumed retained

Parent spec §4.2. A student without a published promotion-source report card does
**not** get `retain`. They appear in a separate "cannot evaluate" list with a
reason, and the run still produces decisions for everyone else.

`promotion_score_readiness` (`services/academic-ops-service/src/queries.rs:369`,
built in Plan 2) already answers this and is reused rather than rewritten.

### 2.8 Recommendation and result are separate columns from the start

`promotion_decision` already carries both `recommended` and `result` (V16). The
engine writes them **equal** on evaluation. An override changes `result` only,
sets `overridden = TRUE`, and requires a reason — the DB check constraint
(`length(trim(reason)) >= 10`) enforces the reason. `recommended` is never
rewritten, so "what did the machine say before a human intervened" stays
answerable forever.

### 2.9 Evaluation is re-runnable while the run is `draft`

Re-running replaces the decision set for that run: delete decisions for the
`run_id`, write a fresh `promotion_rule_snapshot`, repoint `promotion_run.rule_id`,
and insert new decisions — one transaction. Allowed only in `draft`.

**Overrides are lost on re-run.** This is deliberate and must be surfaced by the
API response (a count of discarded overrides), because silently discarding a
principal's written reasons would be its own trust failure.

### 2.10 Approval cannot be done by the same role that evaluates

Plan 3a seeded `promotion.manage` → `tenant_admin` and `promotion.approve` →
`principal`, with an IAM test asserting no role holds both. This plan honours
that split at the handler level: `submit` requires `promotion.manage`, `approve`
and `return` require `promotion.approve`.

Additionally `approve` **must reject** the case where `approved_by` equals
`created_by`, even if a future role somehow held both permissions. Defence in
depth: the audit trail is meaningless if one person can compute and bless a run.

---

## 3. Evaluation algorithm

All criteria are combined with **AND**; a NULL criterion is skipped.

```
subjects with final_score < kkm_snapshot  > max_subjects_below_kkm  → retain
average final_score                      < min_average             → retain
otherwise, if the homeroom's grade_level.is_final                  → graduate
otherwise                                                          → promote
```

Scores come from `known_report_score.final_score` filtered to the run's
`report_type_id` — the value frozen at publish time, not the still-changing
working score.

`computed_metrics` JSONB records what the engine actually saw per student:
`subjects_below_kkm`, `subjects_counted`, `average`, `kkm_used`, and the
criteria that were active. A decision nobody can reconstruct is not auditable.

A school that decides promotion in a staff meeting leaves every criterion NULL:
everyone gets `promote`, then rows are overridden by hand with reasons. One
engine serves that style and the strict-automatic style without a second path.

### 3.1 Preconditions for running an evaluation

Checked before any write; all failures reported together, not one at a time:

- Academic year is `Active` or `Closed`.
- The year has exactly one `known_grade_level` with `is_final = TRUE`.
- A promotion-source report type exists in `known_report_type` for the year.
- Every homeroom in the year resolves to a `known_grade_level` row (§2.6).
- A `known_grading_policy` row exists for the year (§2.4).

---

## 4. Schema changes

### 4.1 `grading-service` — migration V14

No schema change. The migration slot is **not** used; the event is added in code
only. (Listed here so the next author does not hunt for a missing migration.)

### 4.2 `academic-ops` — `known_report_type` projection (migration V17)

```sql
CREATE TABLE IF NOT EXISTS known_report_type (
  tenant_id           UUID NOT NULL,
  report_type_id      UUID NOT NULL,
  academic_year_id    UUID NOT NULL,
  is_promotion_source BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, report_type_id)
);

CREATE INDEX IF NOT EXISTS known_report_type_promotion_idx
  ON known_report_type (tenant_id, academic_year_id)
  WHERE is_promotion_source;
```

Same migration adds `report_type_id UUID NOT NULL` to `promotion_run` (§2.5).

The flag is **year-scoped** while `report_type` itself is term-scoped — mirroring
the scope note in grading-service's `V12`. At most one row per
`(tenant_id, academic_year_id)` may have `is_promotion_source = TRUE`; uniqueness
is the publisher's job, and the projection simply clears the old row when a new
one arrives.

### 4.3 Event shape

`report_type.promotion_source_changed`, published by grading-service through the
outbox in the same transaction as the flag write:

```json
{
  "tenant_id": "…",
  "academic_year_id": "…",
  "report_type_id": "…",
  "is_promotion_source": true
}
```

`academic-ops` must add the routing key to `ROUTING_KEYS`
(`services/academic-ops-service/src/events.rs`). **A match arm without an entry
there never fires** — the queue binding is what decides delivery.

A backfill is required for existing `report_type` rows, following Plan 3a's
precedent: extend `scripts/bootstrap-projections.sh`, report counts, never fail
silently.

---

## 5. API

All under `/api/v1/academic-ops`, guarded by the `academic_ops` feature (§2.3).

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/promotion-runs` | `promotion.manage` | Create draft + evaluate |
| POST | `/promotion-runs/:run_id/evaluate` | `promotion.manage` | Re-run while `draft` |
| GET | `/promotion-runs?academic_year_id=` | `promotion.manage` | List |
| GET | `/promotion-runs/:run_id` | `promotion.manage` | Detail + summary + cannot-evaluate list |
| GET | `/promotion-runs/:run_id/decisions` | `promotion.manage` | Filter by homeroom |
| PATCH | `/promotion-runs/:run_id/decisions/:decision_id` | `promotion.manage` | Override + reason |
| POST | `/promotion-runs/:run_id/submit` | `promotion.manage` | `draft → submitted` |
| POST | `/promotion-runs/:run_id/approve` | `promotion.approve` | `submitted → approved` |
| POST | `/promotion-runs/:run_id/return` | `promotion.approve` | back to `draft` |

`execute` and `homeroom-map` are Plan 3c.

Preconditions that fail return `VALIDATION_ERROR` with a `fields` map, aligned
with the frontend Zod contract per AGENTS.md.

---

## 6. Testing

Every item is a test that fails before the code exists:

- Each precondition in §3.1 blocks a run, with its own error identifying which
  one failed — and all failures are reported together.
- A homeroom with a non-NULL but **dangling** `grade_level_id` is reported
  not-ready, exactly like NULL (§2.6).
- A non-NULL `min_attendance_percent` is rejected on write (§2.1).
- Missing `known_grading_policy` rejects the run; `kkm_snapshot` is never invented.
- A student with no published promotion-source card lands in "cannot evaluate",
  **not** in `retain`.
- Each branch of §3: too many subjects below KKM → `retain`; average below
  minimum → `retain`; final grade level → `graduate`; otherwise → `promote`.
- All-NULL criteria → everyone `promote`.
- `computed_metrics` contains the numbers the decision was based on.
- Override changes `result`, leaves `recommended` untouched, sets `overridden`;
  a reason shorter than 10 trimmed characters is rejected.
- Re-running in `draft` replaces decisions and **reports** the discarded override
  count (§2.9); re-running outside `draft` is rejected.
- `submit` / `approve` / `return` enforce their permissions; `approve` rejects
  `approved_by == created_by` (§2.10).
- Moving the promotion-source flag in grading-service publishes the event **in
  the same transaction** as the flag write (rolled-back write publishes nothing),
  and academic-ops projects it, clearing the previous row.
- Tenant isolation on every new query: another tenant's run is invisible.

Baseline before this plan: academic-config 56/1, academic-ops 65/2, iam 105/0,
`cargo check --workspace` clean. The three failures are pre-existing
(`status_transition_legal_and_illegal_paths`,
`import_valid_sheet_and_bad_sheet_rolls_back`,
`photo_upload_validates_type_and_size_and_sets_photo_url`) and must not grow.

---

## 7. Deliberately out of scope

- Execution and enrollment movement (Plan 3c).
- Target homeroom mapping (Plan 3c).
- Attendance criterion (blocked on A2).
- A separate `promotion` feature code (§2.3).
- Reconciling `homeroom.grade_level` text (`1,2,3`) with `grade_level.code`
  (`A..F`). In dev data **zero of six** homerooms link. This is not a bug: the
  two systems genuinely use different vocabularies, and reconciling them is a
  human decision, not a migration. Until an admin links them, §3.1 blocks
  evaluation loudly — which is the designed behaviour.
