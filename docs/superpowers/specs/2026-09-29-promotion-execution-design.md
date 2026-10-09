# Design Spec: Promotion Execution (Plan 3c)

**Status:** approved
**Date:** 2026-09-29
**Parent spec:** `docs/superpowers/specs/2026-09-23-promotion-design.md` (A1)
**Depends on:** Plan 3a (`2026-09-24-promotion-foundation-design.md`) and
Plan 3b (`2026-09-26-promotion-evaluation-design.md`)

---

## 1. Why this plan exists

Plan 3b ends with an `approved` promotion run: one decision per student, each
`promote`, `retain` or `graduate`, signed off by the principal. Nothing has
happened to any student yet.

This plan makes the decisions take effect. An admin picks the academic year the
students move into, assigns every promoted or retained student a homeroom in
that year, and executes the run. Execution closes every old enrollment, opens
the new ones, writes the graduation and retention records, marks graduates
`lulus`, and publishes one event per student — all in one transaction. When the
graduating year is later closed, its graduates become `alumni`.

After this plan, one full school year can be closed out end to end in the
backend.

### 1.1 What this plan deliberately does NOT do

- **No web UI and no printed decrees (SK).** Parent spec §7–§8 move to Plan 3d,
  built on the finished API contract. This plan is backend only.
- **No automatic class placement.** Parent spec §4.5 rules it out; this plan
  keeps it out. The admin chooses every target homeroom.
- **No capacity enforcement.** See §2.4.
- **No homeroom creation.** Target homerooms must already exist in the target
  year; execution never creates one.
- **No undo.** `executed` is terminal, as parent spec §4.1 states.

---

## 2. Decisions

### 2.1 The admin chooses the target academic year explicitly

`known_academic_year` stores only `academic_year_id`, `tenant_id` and `status` —
no dates and no ordering — so academic-ops cannot know which year is "next".
Deriving it from `start_date` would need a projection migration plus backfill,
and would still have to guess when a tenant has zero or two candidate years
(two `Draft` years is common while a school prepares).

Instead the admin sets `promotion_run.target_academic_year_id`. It is validated,
not guessed (§5.1).

### 2.2 Target homerooms are set per student, on the decision

One source homeroom sends students two ways: most move up a grade, some stay.
A single source → target homeroom map (parent spec §4.5, `PUT /homeroom-map`)
cannot express that. Each decision instead carries its own
`target_homeroom_id` (the column has existed since V16). The admin fills them in
bulk; reshuffling classes is therefore possible before execution, not only after.

This replaces the parent spec's `PUT /homeroom-map` endpoint.

### 2.3 Targets can only be set once the run is `approved`

A target depends on the decision's result: `promote` needs the next grade,
`retain` the same grade. Every change to a result would stale a target — an
override, a re-evaluation (which deletes all decisions), or a `return` that
reopens overriding. Allowing targets only in `approved`, when results are final,
removes that whole class of stale data.

The workflow becomes: evaluate → override → submit → approve → set target year
and homerooms → execute.

`return` stays allowed only from `submitted`, as in 3b. An `approved` run cannot
go back to `draft`, so targets an admin has set are never orphaned. The parent
spec §4.1 diagram, which drew a return arrow from `approved`, is superseded.

### 2.4 Capacity is reported, never enforced

`homeroom.capacity` exists and must be > 0, but no enrollment path checks it
today. Enforcing it only at execution would give one system two capacity rules
and could block a whole school on promotion day because of a carelessly filled
number. Execution therefore never rejects on capacity. The run detail instead
reports, per target homeroom, current active students plus assigned students
against capacity (§5.4), so the admin sees overfull classes before executing.

### 2.5 Any conflict rejects the whole execution, reported together

If a student already has an active enrollment in the target year (an admin
enrolled them by hand), the unique index `enrollment_one_active_per_student_year_uidx`
forbids a second one. Execution does not skip such students and does not adopt
their existing enrollment: either would silently accept an enrollment that may
be in the wrong grade or homeroom. It rejects with `400 VALIDATION_ERROR` and
lists every problem at once — the same all-failures-together pattern as 3b's
evaluation preconditions (§5.3). The admin fixes them and executes again.
Nothing is half-written, because everything is one transaction.

### 2.6 Execution publishes three new events, not `enrolled` / `unenrolled`

Reusing `student.unenrolled` + `student.enrolled` would need no new consumer
code, but:

- platform-service increments the tenant's student count on every
  `student.enrolled`, so every promoted or retained student would be counted
  again each year;
- grading would record the old enrollment as `unenrolled`, making "moved up a
  grade" indistinguishable from "left the school";
- nothing would say a student graduated.

Execution therefore publishes `student.promoted`, `student.retained` and
`student.graduated` (parent spec §4.4). grading-service consumes them;
platform-service does not subscribe, so student counts stay correct.

### 2.7 `lulus` becomes `alumni` in this plan

The parent spec §4.4 says the existing `academic_year.status_changed` consumer
moves graduates to `alumni` when the year closes. It does not: that consumer
only stores the year's status. Leaving it for later would leave every graduate
`lulus` forever. This plan adds it (§6.3).

### 2.8 Grade levels are matched across years by ordinal

A grade level's `grade_level_id` differs every year, and schools may rename
`code` and `label`. `ordinal` is the stable position on the ladder. A student
promoted from a homeroom whose grade level has ordinal *n* must go to a target
homeroom whose grade level has ordinal *n + 1*; a retained student to ordinal *n*.

### 2.9 One transaction, row by row in Rust

Execution runs in one transaction, processing decisions one at a time in Rust,
following 3b's re-evaluate and override pattern. Roughly four statements per
student: about 6,000 for a 1,500-student school, a few seconds. Set-based SQL
(`UPDATE … FROM`, `INSERT … SELECT`) would be faster but long, hard to test per
branch, and poor at per-student error messages; an asynchronous job would break
the parent spec's promise that execution rolls back whole. If a much larger
tenant ever appears, the inside can move to set-based SQL without changing the
API contract.

### 2.10 Small decisions

- `graduation_record.graduation_date` is the execution date.
  `certificate_number` stays NULL; Plan 3d fills it when printing.
- `retention_record.reason` (NOT NULL) is the override reason when the decision
  was overridden; otherwise a summary of the failed criteria built from
  `computed_metrics`, e.g. `average 65.2 below 70; 3 subjects below KKM (max 2)`.
  Never a generic placeholder.

---

## 3. Schema changes — academic-ops migration V19

grading-service needs no migration: its `enrolled_student_status_chk` already
accepts `promoted` (grading V13, Plan 1).

```sql
ALTER TABLE promotion_run
  ADD COLUMN IF NOT EXISTS target_academic_year_id UUID NULL,
  ADD COLUMN IF NOT EXISTS executed_by             UUID NULL;

ALTER TABLE promotion_decision
  ADD COLUMN IF NOT EXISTS target_enrollment_id UUID NULL;

-- An executed run always carries its audit trail.
ALTER TABLE promotion_run DROP CONSTRAINT IF EXISTS promotion_run_executed_chk;
ALTER TABLE promotion_run ADD CONSTRAINT promotion_run_executed_chk CHECK (
  status <> 'executed'
  OR (executed_at IS NOT NULL
      AND executed_by IS NOT NULL
      AND target_academic_year_id IS NOT NULL)
);

-- A graduate never moves into a homeroom.
ALTER TABLE promotion_decision DROP CONSTRAINT IF EXISTS promotion_decision_graduate_no_target_chk;
ALTER TABLE promotion_decision ADD CONSTRAINT promotion_decision_graduate_no_target_chk CHECK (
  result <> 'graduate' OR target_homeroom_id IS NULL
);
```

- `target_enrollment_id` records the enrollment execution created, so "where did
  this student go" is always answerable without guessing.
- The header documents that every decision's `target_homeroom_id` is cleared
  whenever the run's target year changes (§5.1).
- V19 is idempotent (`IF NOT EXISTS`, drop-then-add constraints): the dev
  database still receives promotion migrations by hand until refinery catches up.

Existing DB backstops this plan relies on: the one-active-enrollment-per-year
unique index; `UNIQUE (student_id, academic_year_id)` on `graduation_record` and
`retention_record` (V16); V18's one-open-run-per-year index.

---

## 4. Execution algorithm

`commands::execute_promotion_run`, one transaction:

1. `BEGIN`; `lock_run_for_update(tenant_id, run_id)`. Missing → 404. Status not
   `approved` → `409 PROMOTION_RUN_INVALID_STATUS`.
2. Check every precondition inside the transaction (§5.3) and collect all
   failures. Any failure → roll back, `400 VALIDATION_ERROR`, nothing written.
3. Read the run's decisions ordered by homeroom, then student (deterministic
   event order). For each decision:

   | `result` | Old enrollment | New rows | Event |
   |---|---|---|---|
   | `promote` | → `promoted` | `active` enrollment in `target_homeroom_id`, target year; set `target_enrollment_id` | `student.promoted` |
   | `retain` | → `promoted` | as `promote`, plus `retention_record` (§2.10) | `student.retained` |
   | `graduate` | → `promoted` | `graduation_record`; `student.status` → `lulus` | `student.graduated` |

   The old enrollment is closed with an `UPDATE` scoped by `tenant_id`,
   `enrollment_id` and `status = 'active'`, and `rows_affected` must be exactly
   1. Zero means the enrollment changed after evaluation (e.g. the student was
   transferred); it is collected as a `400` on field `enrollments`, never
   skipped. Every write filters by `tenant_id`.
4. Move the run to `executed` with a conditional `UPDATE … WHERE status =
   'approved'`, setting `executed_at` and `executed_by`. Zero rows → roll back,
   409.
5. `COMMIT`. Events leave through the existing outbox, so they exist only if
   the commit does.

Concurrency:

- Two concurrent executions: the second waits on the run lock, then sees
  `executed` and gets 409.
- A manual enrollment between step 2 and step 3: the unique index rejects it at
  DB level. That `23505` is mapped to `400` on field `enrollments`, not 500
  (the lesson of 3b's V18 mapping). The mapping matches the constraint name
  `enrollment_one_active_per_student_year_uidx` only; any other database error
  inside execution stays `500` and rolls the whole transaction back.

---

## 5. API

All under `/api/v1/academic-ops`, guarded by the `academic_ops` entitlement,
permission `promotion.manage`. A run of another tenant is `404`. No new error
codes.

### 5.1 `PUT /promotion-runs/:run_id/target`

Body: `{ "target_academic_year_id": "uuid" }`. Run must be `approved`, otherwise
`409 PROMOTION_RUN_INVALID_STATUS`.

Validated together, each failure reported under field `target_academic_year_id`
in one `400 VALIDATION_ERROR`:

- the year exists in `known_academic_year` for this tenant;
- it differs from the run's `academic_year_id`;
- its status is not `Closed` or `Archived`;
- its grade-level ladder contains every ordinal the decisions need
  (source ordinal + 1 for `promote`, the same ordinal for `retain`).

Changing the target year clears every decision's `target_homeroom_id` in the
same transaction. Response (200): the run shape plus `cleared_targets`.

### 5.2 `PATCH /promotion-runs/:run_id/targets`

Body:

```json
{ "assignments": [ { "decision_id": "uuid", "homeroom_id": "uuid" } ] }
```

`homeroom_id: null` clears a target. At most 2,000 items. The run must be
`approved` and have a target year; the run row is locked for the write, as in
override.

All or nothing: one bad item rejects the batch, and every error is reported
under field `assignments`, e.g.
`decision <id>: homeroom XI IPA 1 is ordinal 2, expected 1`. Per-item errors:

- decision not in this run;
- decision result is `graduate`;
- homeroom not in this tenant, or not in the target year;
- homeroom not linked to a grade level;
- homeroom ordinal does not match the decision's result (§2.8).

Response (200): `{ "updated": n }`.

### 5.3 `POST /promotion-runs/:run_id/execute`

No body. Response (200): the run shape (now `executed`) plus
`counts: { promoted, retained, graduated }`.

Preconditions, checked inside the transaction and reported together as
`400 VALIDATION_ERROR`:

| Field key | Failure |
|---|---|
| `target_academic_year` | not set, or now `Closed` / `Archived` |
| `targets` | `promote` / `retain` decisions without a target — count and `student_id`s |
| `enrollments` | students already active in the target year; old enrollments no longer `active` |
| `target_homerooms` | targets no longer valid: homeroom deleted, moved to another year, or its grade level relinked or given another ordinal since assignment |

Any status other than `approved`, including a second execution →
`409 PROMOTION_RUN_INVALID_STATUS`.

### 5.4 Read endpoints extended

- Run shape: adds `target_academic_year_id`, `executed_by`, `executed_at`.
- Decision shape: adds `target_homeroom_id`, `target_enrollment_id`.
- Run detail: adds `placement` — one entry per target homeroom with
  `homeroom_id`, `name`, `capacity`, `existing_active`, `assigned`, `total`,
  `over_capacity` — plus an `unassigned` count. Informational only (§2.4).

---

## 6. Events and consumers

### 6.1 Payloads

`student.promoted` and `student.retained` share one shape:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "run_id": "uuid",
  "from": { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "to":   { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "full_name": "string",
  "nis": "string"
}
```

`full_name` and `nis` let grading fill the new `enrolled_student` row exactly as
it does from `student.enrolled`.

`student.graduated`:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "run_id": "uuid",
  "from": { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "graduation_date": "date",
  "student_status": "lulus"
}
```

### 6.2 grading-service consumer

Added to `ROUTING_KEYS` and the handler:

- `student.promoted` / `student.retained`: in one transaction, set the `from`
  row of `enrolled_student` to `promoted`, then upsert the `to` row as `active`
  with the same statement as `upsert_enrolled_student` (key
  `(tenant_id, student_id, academic_year_id)`).
- `student.graduated`: set the `from` row to `promoted`; no new row.
- Redelivery is a no-op: setting `promoted` again and repeating the upsert
  change nothing.
- A missing `from` row (never projected) logs `tracing::warn!` and still
  upserts the `to` row, following the existing `student.unenrolled` handling.

platform-service is unchanged: promotion does not change a tenant's student
count, and graduate statistics are not needed yet.

### 6.3 academic-ops: `lulus` → `alumni`

In the existing `academic_year.status_changed` handler, after storing the
status, and only when the new status is `Closed`, in the same transaction:

```sql
UPDATE student SET status = 'alumni', updated_at = NOW()
 WHERE tenant_id = $1
   AND status = 'lulus'
   AND student_id IN (SELECT student_id FROM graduation_record
                       WHERE tenant_id = $1 AND academic_year_id = $2);
```

No event is published; student status is not part of grading's projection.
Years closed before this plan shipped have no `graduation_record`, so nothing
needs backfilling.

### 6.4 Contract documentation (parent repo)

- `docs/internal/11_integration_contracts/events/`: the three new events (one
  combined file, as `grade-level-events.md`).
- `apis/promotion-service-api.md`: the three new endpoints, the added fields,
  `placement`, and the Events section now listing what execution publishes.

---

## 7. Testing

Cadence per `apps/backend/CONVENTIONS.md` §7.1: each task runs only its new
tests (`--exact`), with RED shown as a real failing assertion; the full suites
run once at the final gate, one service at a time (academic-ops, grading), plus
`cargo check --workspace`. A `StartupTimeout` failure counts as clean only if
the test passes when re-run alone.

Required:

- **Target year:** another tenant's year, the source year, a `Closed` year and a
  missing ordinal are rejected together; changing the year clears all targets
  and `cleared_targets` matches; a non-`approved` run is 409.
- **Target assignment:** wrong grade for `promote` and for `retain`; a
  `graduate` decision; a homeroom from another year and from another tenant;
  one bad item rejects the batch with nothing written; `null` clears; the
  repo-level UPDATE is scoped to tenant and run.
- **Execution, happy path:** one fixture with a promoted, a retained and a
  graduating student — old enrollments `promoted`, new enrollments in the right
  homerooms, `retention_record.reason` correct for both the overridden and the
  metrics case, `graduation_record` present, graduate `lulus`,
  `target_enrollment_id` set, run `executed` with `executed_by`, three outbox
  events with correct payloads.
- **Execution, failures:** already-active, missing and stale targets reported
  together as 400 with no row changed; an old enrollment transferred after
  evaluation → 400; second execution → 409; concurrent executions
  (`tokio::join!`) → exactly one 200 and one 409 with no duplicated
  enrollment; an interleaved manual enrollment's `23505` → 400, not 500; a
  failure mid-transaction rolls back everything — triggered by a pre-existing
  `graduation_record` for a graduating student processed after others (a state
  the preconditions do not check), asserting the response is 500 and every
  earlier student's writes are rolled back. A deleted target homeroom is not a
  usable trigger: the `target_homerooms` precondition catches it before any
  write.
- **Alumni:** closing a year moves its graduates to `alumni`; `lulus` students
  of another year or another tenant are untouched; redelivery is a no-op.
- **grading consumer:** correct rows for all three events; redelivery is a
  no-op; a missing `from` row warns and still creates `to`; one end-to-end test
  through RabbitMQ.
- **Isolation and permissions:** all three new endpoints return 404 for another
  tenant's run and 403 without `promotion.manage` (e.g. `principal`).

---

## 8. Deliberately out of scope

| Item | Where it goes |
|---|---|
| Promotion web UI (`/promotion`), override dialog, target panel | Plan 3d |
| SK Kenaikan Kelas and Surat Keterangan Lulus printing | Plan 3d |
| `certificate_number` assignment | Plan 3d |
| Capacity enforcement | Not planned (§2.4) |
| Automatic class placement | Not planned (parent spec §4.5) |
| Undoing an executed run | Not planned (parent spec §4.1) |
| Graduate statistics in platform-service | When a consumer needs them |
