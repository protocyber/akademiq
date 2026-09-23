# Design Spec: Promotion Foundation (Plan 3a)

**Status:** approved
**Date:** 2026-09-24
**Parent spec:** `docs/superpowers/specs/2026-09-23-promotion-design.md` (A1)
**Depends on:** Plan 1 (`grade_level`), Plan 2 (`report_card.published` + projections)

---

## 1. Why this plan exists

The parent spec's step 5 — "promotion tables + evaluation engine" — is one line of
prose hiding roughly 20 tasks: a new event producer, a new projection, five
tables, a rule engine, ten endpoints, a four-state machine, transactional
execution, three outbox events, and new IAM permissions.

Plan 2 taught us why that must not be one plan. Across eight tasks, six briefs
had already drifted from the shipped code by the time an implementer read them —
because they were written against an imagined codebase, not a real one. The
longer the plan, the further the tail end is written from reality.

So A1 step 5 is split into three sequential plans:

| Plan | Scope | Ends with |
|---|---|---|
| **3a (this one)** | `known_grade_level` projection + `grade_level.*` events + `homeroom.grade_level_id` + promotion tables + IAM permissions | The engine has every fact it needs, and nothing to compute with yet |
| 3b | Rule engine, decisions, overrides, run state machine, read endpoints | Decisions exist and can be reviewed, but change nothing |
| 3c | Homeroom mapping, transactional execution, outbox events | Students actually move |

Each plan is written **after** the previous one has landed and been verified, so
every brief describes code that exists.

### 1.1 What this plan deliberately does NOT do

No rule evaluation, no decisions, no endpoints beyond what the tables need, no
execution. 3a creates the vocabulary; 3b and 3c use it. A reviewer should be able
to read this plan's output and find nothing that decides a student's fate.

---

## 2. The problem this plan actually solves

The evaluation engine lives in `academic-ops`. The parent spec's formula needs two
facts from `grade_level`:

- `is_final` — decides `graduate` vs `promote`
- `ordinal` — decides the destination grade (`ordinal + 1`)

`grade_level` lives in **`academic-config`**. Verified state today:

- `academic-config` emits exactly five event types: `academic_year.created`,
  `academic_year.status_changed`, `academic_term.created`,
  `academic_term.status_changed`, `grading_policy.configured`. **No `grade_level`
  event exists.**
- `academic-ops` has **no** `grade_level` projection.
- `academic_ops.homeroom.grade_level` is free text `VARCHAR(64)`, unlinked to
  anything.
- Plan 1 added `grade_level_id` to `class_template` — but that table lives in
  academic-config. `homeroom` never got the same treatment.

So `academic-ops` currently has no legitimate way to know whether a homeroom is
the final grade, or which grade follows it. `CONVENTIONS.md` forbids calling
academic-config over HTTP.

### 2.1 The finding that shaped this plan

Before assuming a backfill would work, the two services' grade vocabularies were
compared in the dev database:

```
FULL OUTER JOIN academic_config.grade_level gl
  ON gl.code = h.grade_level AND gl.tenant_id = h.tenant_id
 AND gl.academic_year_id = h.academic_year_id
```

Result: **nine rows, zero matches.** `academic_config.grade_level.code` holds
`A, B, C, D, E, F` (backfilled by V9 from `class_template.grade_level`), while
`academic_ops.homeroom.grade_level` holds `1, 2, 3`.

Two services have been storing different vocabularies for the same concept, and
nothing noticed, because nothing had ever compared them.

A V9-style backfill (`JOIN ON gl.code = h.grade_level`) would therefore leave
**every** `homeroom.grade_level_id` NULL — and do it silently. The migration
would report success, and months later the promotion engine would refuse to run
for every school with no legible reason.

The dev data is small (6 homerooms, 6 grade levels) and obviously seeded, so it
does not prove what real tenant data looks like. That is exactly why the
assumption must not be baked into a migration.

---

## 3. Decisions

### 3.1 How academic-ops learns about grade levels — **projection + link**

`known_grade_level` projection in academic-ops, fed by new `grade_level.*` events
from academic-config, **plus** a nullable `homeroom.grade_level_id` FK.

Rejected: passing `grade_level` inside the existing report-card event. `is_final`
and `ordinal` are configuration facts, not report facts; smuggling them through a
report event means a grade-ladder change never propagates until someone publishes
a new report card.

Rejected: HTTP calls to academic-config — forbidden by `CONVENTIONS.md`, and it
would make promotion evaluation fail whenever academic-config is down.

The projection alone is not enough. Parent spec §4.5 requires the system to
*suggest* a destination homeroom from "name and grade-level match". Without
`grade_level_id` on homeroom, "grade level" is a string, and `ordinal + 1` cannot
be computed at all.

### 3.2 The backfill must report, never fail silently

After the UPDATE, the migration counts `homeroom` rows still holding NULL and
raises a warning naming the count and the unmatched values. A migration that
succeeds while matching nothing is the worst possible outcome, because it looks
like progress.

### 3.3 `grade_level_id` stays NULLable

Forcing NOT NULL would make the migration fail outright on any tenant whose
vocabularies disagree — which the dev data shows is the likely case, not the
edge case. NULL is a legible "not yet reconciled" state; a failed migration is
not.

### 3.4 Unlinked homerooms block evaluation loudly

3b's engine must refuse to evaluate a homeroom whose `grade_level_id` is NULL,
and must surface it in the "cannot be evaluated" list with the reason. This
mirrors parent spec §4.2: a student without data is never silently treated as
retained. The same discipline applies to a homeroom without a grade level.

### 3.5 `grade_level` events must be transactional

Verified: of the four existing grade-level commands, only `reorder_grade_levels`
opens a transaction.

| Command | Opens `tx` today |
|---|---|
| `add_grade_level` | no |
| `update_grade_level` | no |
| `delete_grade_level` | no |
| `reorder_grade_levels` | yes |

Plan 2 hit this exact bug in grading-service: a status write and its outbox
insert on separate connections, so a crash between them left a permanent state
change that never emitted its event. Adding an outbox write to a non-transactional
command reproduces that bug deliberately. All four commands therefore move to
`begin()` → repo write → `enqueue()` → `commit()`, matching the house pattern at
`academic-config-service/src/commands.rs:548-570`.

### 3.6 Event shapes

`reorder_grade_levels` moves the entire ladder in one two-phase update, so
per-row events would emit a burst of messages describing momentarily-invalid
intermediate states (the temporary parking ordinals). It emits one
`grade_level.reordered` carrying the final ordered list instead.

| Event | Payload |
|---|---|
| `grade_level.created` | `tenant_id`, `academic_year_id`, `grade_level_id`, `code`, `label`, `ordinal`, `is_final` |
| `grade_level.updated` | same field set (full current state, not a delta) |
| `grade_level.deleted` | `tenant_id`, `grade_level_id` |
| `grade_level.reordered` | `tenant_id`, `academic_year_id`, `levels: [{grade_level_id, ordinal}]` |

Full current state rather than deltas, matching `grading_policy.configured`:
a projection consumer that receives full state is idempotent by construction and
cannot drift when a message is missed.

### 3.7 Projection backfill is required

Events only carry changes forward. Without a backfill, `known_grade_level` stays
empty until somebody edits a grade level, and evaluation refuses to run for every
existing school. 3a therefore ships a bootstrap that populates the projection from
academic-config's current rows, following the existing projection-bootstrap script
pattern rather than inventing a new mechanism.

---

## 4. Schema

### 4.1 `academic-ops` — new projection (migration V14)

```sql
CREATE TABLE IF NOT EXISTS known_grade_level (
  tenant_id        UUID NOT NULL,
  grade_level_id   UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  code             VARCHAR(64) NOT NULL,
  label            VARCHAR(64) NOT NULL,
  ordinal          INT NOT NULL,
  is_final         BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, grade_level_id)
);

CREATE INDEX IF NOT EXISTS known_grade_level_year_idx
  ON known_grade_level (tenant_id, academic_year_id, ordinal);
```

Keyed by `grade_level_id` because that is the identity academic-config owns;
`code` is mutable and `ordinal` changes on every reorder.

### 4.2 `academic-ops` — homeroom link (migration V15)

```sql
ALTER TABLE homeroom
  ADD COLUMN IF NOT EXISTS grade_level_id UUID NULL;
```

No FK to `known_grade_level`: projections are eventually consistent, and a hard
FK would make homeroom writes fail whenever the projection lags behind. The
free-text `grade_level` column stays authoritative until reconciliation is done.

Backfill matches on `code`, then reports what it could not match.

### 4.3 `academic-ops` — promotion tables (migration V16)

Exactly as specified in parent spec §3, with two corrections carried from Plan 2:

- `min_average`, `min_attendance_percent`, `kkm_snapshot` are **`DOUBLE PRECISION`**,
  not `NUMERIC`. Plan 2 established this: the producers and every existing
  projection of the same fact use `DOUBLE PRECISION`, and a type mismatch across
  projections of one fact produces subtle comparison bugs — in a comparison that
  decides whether a child repeats a year.
- Every table carries `tenant_id`, and every index leads with it.

Tables: `promotion_rule_snapshot`, `promotion_run`, `promotion_decision`,
`graduation_record`, `retention_record`.

3a creates them and proves their constraints. Nothing writes to them until 3b.

### 4.4 IAM — permissions (migration V26)

`promotion.manage` and `promotion.approve`, following
`V21__seed_academic_ops_manage_permission.sql`. Feature code `promotion` already
exists in `features.toml:32` and needs no new entry.

The two are separate because `promotion.approve` is the principal's sign-off.
One permission would let whoever computes the decisions also approve them,
collapsing the only human check in the whole flow.

---

## 5. Testing

- Each `grade_level.*` event updates the projection; redelivery is idempotent;
  a missed message cannot cause drift (full-state payloads).
- Each of the four commands emits its event **and** rolls back the write when the
  outbox insert fails — the Plan 2 atomicity proof, applied to all four.
- `reorder_grade_levels` emits exactly one event carrying the final ordering, not
  one per row, and never emits the temporary parking ordinals.
- Backfill: matching rows link; non-matching rows stay NULL **and are reported**.
- Projection is tenant-scoped in both directions.
- Promotion table constraints reject what they must: `overridden` without a
  reason, a reason under 10 characters, unknown `status` / `recommended` /
  `result` values, duplicate `(run_id, student_id)`.
- Bootstrap populates the projection for pre-existing tenants and is safe to
  re-run.

---

## 6. Deliberately out of scope

| Not in 3a | Where |
|---|---|
| Rule engine, `computed_metrics` | 3b |
| Override + reason enforcement at the API layer | 3b |
| `promotion_run` state machine transitions | 3b |
| Homeroom mapping, execution, outbox events | 3c |
| Web UI, SK printing | Plan 4 |
| Reconciling the two grade vocabularies for real tenants | Operational task; 3a reports the mismatch, a human resolves it |
