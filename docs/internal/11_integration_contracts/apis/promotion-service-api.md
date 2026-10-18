# Promotion API (Academic Operations Service)

Grade promotion (kenaikan kelas) is implemented inside
**academic-ops-service**, not as a separate service. Base path:
`/api/v1/academic-ops`. All endpoints use the standard success and error
envelopes from `13_engineering_standards/03_api_conventions.md`, resolve
`tenant_id` from the JWT and never from the request body, and are guarded by
the existing `academic_ops` entitlement (a tenant without it gets
`403 FEATURE_NOT_AVAILABLE`). There is no separate `promotion` feature code.

Design: `docs/superpowers/specs/2026-09-26-promotion-evaluation-design.md`
(evaluation, Plan 3b) and
`docs/superpowers/specs/2026-09-29-promotion-execution-design.md`
(execution, Plan 3c).

## Model

A **promotion run** evaluates one academic year. It freezes the criteria in a
rule snapshot, reads the frozen report scores of the year's promotion-source
report type (`known_report_type`), and writes one **decision** per evaluable
student. At most one run per tenant and academic year may be open (status
other than `executed`); a partial unique index enforces this.

Run status: `draft` → `submitted` → `approved` → `executed`. `return` sends a
submitted run back to `draft`. Once a run is `approved`, the admin sets its
target academic year and each promoted or retained student's target homeroom,
then executes it. Execution moves every student in one transaction and is
final: there is no undo, and an executed run cannot be executed again.

Each decision keeps the engine's `recommended` result and the effective
`result`. An override changes `result` only and requires a reason;
`recommended` is never rewritten.

## Permissions

| Permission | Granted to | Endpoints |
|---|---|---|
| `promotion.manage` | `tenant_admin` | create, re-evaluate, override, submit, set target year, assign targets, execute |
| `promotion.approve` | `principal` | approve, return |
| `promotion.manage` **or** `promotion.approve` | both | every `GET` |

No built-in role holds both permissions. Independently of roles, the user who
created a run can never approve it (`PROMOTION_SELF_APPROVAL`).

A missing permission returns `403 FORBIDDEN` with message
`missing required permission: <code>` (reads:
`missing required permission: promotion.manage or promotion.approve`).

A run or decision that belongs to another tenant is reported as `404`, never
`403`.

## Criteria

Request bodies that carry criteria accept:

| Field | Type | Rule |
|---|---|---|
| `min_average` | number or null | `0`–`100`. Retain when the average of the student's final scores is **below** it. |
| `max_subjects_below_kkm` | integer or null | `>= 0`. Retain when **more than** this many subjects score below the KKM. |
| `min_attendance_percent` | must be null | Rejected until attendance (A2) exists: `VALIDATION_ERROR` with `"attendance criterion is not available yet"`. |

A null criterion is skipped. All active criteria are combined with AND.
Retain wins over graduate; a student in the year's final grade level who is
not retained graduates; everyone else is promoted. KKM is read from the
year's grading policy and is never client-supplied.

## Endpoints

### `POST /promotion-runs`

Creates a draft run and evaluates it. Permission: `promotion.manage`.

Request:

```json
{
  "academic_year_id": "uuid",
  "min_average": 70,
  "max_subjects_below_kkm": 2,
  "min_attendance_percent": null
}
```

Success (201):

```json
{
  "data": {
    "run_id": "uuid",
    "status": "draft",
    "report_type_id": "uuid",
    "rule_id": "uuid",
    "counts": { "promote": 120, "retain": 4, "graduate": 0 },
    "cannot_evaluate": ["student-uuid"],
    "discarded_overrides": 0
  },
  "meta": {}
}
```

`cannot_evaluate` lists students with no score under the promotion-source
report type. They get no decision and are never assumed retained.

Preconditions are checked together; every failure is reported in one
response as `400 VALIDATION_ERROR` with these `fields` keys:

| Field key | Failure |
|---|---|
| `academic_year` | Year is missing or not `Active` / `Closed`. |
| `grade_levels` | The year does not have exactly one final grade level. |
| `report_type` | No promotion-source report type for the year. |
| `homerooms` | A homeroom is not linked to a grade level (NULL or dangling link), one message per homeroom: `homeroom <name> is not linked to a grade level`. |
| `grading_policy` | No grading policy (KKM) for the year. |

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `VALIDATION_ERROR` | 400 | Invalid criteria, or failed preconditions (see above). |
| `FORBIDDEN` | 403 | Missing `promotion.manage`. |
| `PROMOTION_RUN_EXISTS` | 409 | An open run already exists for the year; re-evaluate it instead. Also returned to the loser of two concurrent creates. |

### `GET /promotion-runs?academic_year_id=`

Lists the year's runs, newest first. Missing or non-UUID `academic_year_id`
→ `400 VALIDATION_ERROR` on field `academic_year_id`. A year without runs
returns `[]`.

Run shape (also used by the transition endpoints):

```json
{
  "run_id": "uuid",
  "academic_year_id": "uuid",
  "report_type_id": "uuid",
  "rule_id": "uuid",
  "status": "draft",
  "created_by": "uuid",
  "approved_by": null,
  "target_academic_year_id": null,
  "executed_by": null,
  "executed_at": null,
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

`target_academic_year_id` is set by `PUT .../target`; `executed_by` and
`executed_at` are set by execution (an `executed` run always has all three).

### `GET /promotion-runs/:run_id`

Run detail:

```json
{
  "data": {
    "run": { "...": "run shape" },
    "criteria": { "min_average": 70, "max_subjects_below_kkm": 2, "min_attendance_percent": null },
    "kkm": 75,
    "counts": { "promote": 119, "retain": 5, "graduate": 0 },
    "overridden": 1,
    "cannot_evaluate": ["student-uuid"],
    "placement": [
      {
        "homeroom_id": "uuid",
        "name": "XI IPA 1",
        "capacity": 36,
        "existing_active": 2,
        "assigned": 35,
        "total": 37,
        "over_capacity": true
      }
    ],
    "unassigned": 4
  },
  "meta": {}
}
```

`criteria` and `kkm` come from the run's current rule snapshot. `counts`
group decisions by effective `result`. `cannot_evaluate` is recomputed on
each request. Unknown or foreign run → `404`.

`placement` has one entry per homeroom that is some decision's target,
ordered by name. `existing_active` counts the homeroom's `active` enrollments
that this run did not create; `assigned` counts the decisions targeting it;
`total = existing_active + assigned`; `over_capacity = total > capacity`.
`unassigned` counts `promote` / `retain` decisions without a target. Both are
informational: capacity never blocks assignment or execution. Before any
target is set, `placement` is `[]`.

### `GET /promotion-runs/:run_id/decisions?homeroom_id=`

Decisions of the run, ordered by homeroom then student, optionally filtered
by `homeroom_id`. Unknown or foreign run → `404` (not an empty list).

Decision shape:

```json
{
  "decision_id": "uuid",
  "student_id": "uuid",
  "homeroom_id": "uuid",
  "recommended": "promote",
  "result": "retain",
  "overridden": true,
  "reason": "Attended remedial program; staff meeting decision",
  "computed_metrics": {
    "subjects_counted": 12,
    "subjects_below_kkm": 3,
    "average": 71.4,
    "kkm_used": 75,
    "criteria": { "min_average": 70, "max_subjects_below_kkm": 2, "min_attendance_percent": null }
  },
  "target_homeroom_id": null,
  "target_enrollment_id": null,
  "full_name": "Siti Aminah",
  "nis": "2024001",
  "homeroom_name": "VII-A",
  "source_ordinal": 1
}
```

`full_name`, `nis` (from the student), `homeroom_name` and `source_ordinal`
(from the source homeroom and its linked grade level) are read through
tenant-scoped joins and stay filled after execution, when the source
enrollment is no longer active. Each is `null` when the row it comes from is
missing; `source_ordinal` is `null` when the source homeroom is not linked to
a grade level. The override response (`PATCH .../decisions/:decision_id`)
returns the same shape.

`result` and `recommended` are always one of `promote`, `retain`, `graduate`.
`target_homeroom_id` is set by `PATCH .../targets` (always null for
`graduate`); `target_enrollment_id` is the enrollment execution created for a
promoted or retained student.

### `POST /promotion-runs/:run_id/evaluate`

Re-evaluates a **draft** run with new criteria (body: the three criteria
fields). Permission: `promotion.manage`. Runs in one transaction that locks
the run: deletes all decisions, writes a new rule snapshot (the old one is
kept for audit), re-reads the current promotion source, and writes fresh
decisions. Response (200) has the same shape as create;
`discarded_overrides` reports how many written overrides were lost.

Errors: `VALIDATION_ERROR` (400, criteria or preconditions), `FORBIDDEN`
(403), `404` (unknown or foreign run), `PROMOTION_RUN_INVALID_STATUS` (409,
message `promotion run must be in draft status`).

### `PATCH /promotion-runs/:run_id/decisions/:decision_id`

Overrides one decision of a **draft** run. Permission: `promotion.manage`.

Request:

```json
{ "result": "retain", "reason": "Attended remedial program; staff meeting decision" }
```

- `result` equal to the decision's `recommended` clears the override
  (`overridden = false`, `reason = null`); no reason is needed.
- Otherwise `reason` is required and must have at least 10 characters after
  trimming.

The run row is locked for the duration of the write, so an override cannot
land after a concurrent submit. Response (200): the decision shape.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `VALIDATION_ERROR` | 400 | `fields.result`: not promote/retain/graduate. `fields.reason`: `reason must be at least 10 characters`. |
| `FORBIDDEN` | 403 | Missing `promotion.manage`. |
| — | 404 | Unknown or foreign run or decision, or the decision was removed by a concurrent re-evaluation. |
| `PROMOTION_RUN_INVALID_STATUS` | 409 | Run is not `draft`. |

### `POST /promotion-runs/:run_id/submit` · `/approve` · `/return`

No body. Response (200): the run shape.

| Endpoint | Permission | Transition | Effect |
|---|---|---|---|
| `submit` | `promotion.manage` | `draft` → `submitted` | — |
| `approve` | `promotion.approve` | `submitted` → `approved` | sets `approved_by` to the caller |
| `return` | `promotion.approve` | `submitted` → `draft` | overrides become editable again |

Each transition is one conditional update on the expected status, so of two
concurrent approvals exactly one succeeds.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `FORBIDDEN` | 403 | Missing the endpoint's permission. |
| `PROMOTION_SELF_APPROVAL` | 403 | `approve` only: the caller created the run. |
| — | 404 | Unknown or foreign run. |
| `PROMOTION_RUN_INVALID_STATUS` | 409 | Run is not in the expected status; message `promotion run must be in <expected> status`. |

## Execution endpoints

All three require `promotion.manage` and a run in status `approved`; any
other status → `409 PROMOTION_RUN_INVALID_STATUS` with message
`promotion run must be in approved status`. Each locks the run row for its
whole transaction, so they serialise against each other and against a second
execution. Unknown or foreign run → `404`.

Grade levels are matched across years by `ordinal`, because each year has its
own grade-level ids: a `promote` decision needs a target homeroom whose grade
level has the source ordinal + 1, a `retain` decision the same ordinal.
`graduate` decisions have no target.

### `PUT /promotion-runs/:run_id/target`

Sets the run's target academic year.

Request:

```json
{ "target_academic_year_id": "uuid" }
```

Validated together; every failure is reported under field
`target_academic_year_id` in one `400 VALIDATION_ERROR`:

| Message | Failure |
|---|---|
| `academic year not found` | Not a known year of this tenant. |
| `target academic year must not be Closed or Archived` | |
| `target academic year must differ from the run's academic year` | |
| `target academic year has no grade level with ordinal <n>` | One per ordinal the decisions need and the year lacks. |

Changing the year clears every decision's `target_homeroom_id` in the same
transaction; setting the same year again clears nothing.

Success (200): the run shape plus `cleared_targets` (number of targets
cleared).

### `PATCH /promotion-runs/:run_id/targets`

Assigns target homerooms in bulk.

Request:

```json
{
  "assignments": [
    { "decision_id": "uuid", "homeroom_id": "uuid" },
    { "decision_id": "uuid", "homeroom_id": null }
  ]
}
```

`homeroom_id: null` clears that decision's target. At most 2,000 items.
All or nothing: one bad item rejects the whole batch, and every problem is
reported under field `assignments` in one `400 VALIDATION_ERROR`:

| Message | Failure |
|---|---|
| `at most 2000 assignments per request` | Batch too large (checked first, alone). |
| `decision <id>: assigned more than once` | Same decision twice in the batch. |
| `decision <id>: not in this run` | Unknown decision, or one of another run or tenant. |
| `decision <id>: graduating students have no target homeroom` | Non-null homeroom on a `graduate` decision. |
| `decision <id>: homeroom <homeroom_id> not found` | Unknown homeroom, or one of another tenant. |
| `decision <id>: homeroom <name> is not in the target academic year` | |
| `decision <id>: homeroom <name> is not linked to a grade level` | |
| `decision <id>: its source homeroom is not linked to a grade level` | The decision's own homeroom lost its grade level after evaluation, so no expected ordinal exists. |
| `decision <id>: homeroom <name> is ordinal <actual>, expected <expected>` | Ordinal rule above. |

A run without a target year → `400 VALIDATION_ERROR` on field
`target_academic_year_id`: `set the target academic year first`.

Success (200): `{ "updated": 12 }`.

### `POST /promotion-runs/:run_id/execute`

No body. Executes the run in one transaction. For each decision, ordered by
homeroom then student:

- the student's enrollment in the run's year → `promoted`;
- `promote` / `retain`: a new `active` enrollment in the target homeroom,
  recorded on the decision as `target_enrollment_id`; `retain` also writes a
  `retention_record` whose reason is the override reason, or the failed
  criteria (e.g. `average 65.2 below 70; 3 subjects below KKM (max 2)`);
- `graduate`: a `graduation_record` dated today (UTC) and
  `student.status` → `lulus`;
- one event through the outbox (see Events).

Finally the run becomes `executed` with `executed_at` and `executed_by`.

Success (200): the run shape (now `executed`) plus counts:

```json
{
  "data": {
    "run_id": "uuid",
    "status": "executed",
    "target_academic_year_id": "uuid",
    "executed_by": "uuid",
    "executed_at": "datetime",
    "...": "rest of the run shape",
    "counts": { "promoted": 118, "retained": 5, "graduated": 0 }
  },
  "meta": {}
}
```

Preconditions are checked inside the transaction and reported together as
`400 VALIDATION_ERROR`; nothing is written:

| Field key | Message |
|---|---|
| `target_academic_year` | `set the target academic year first`, or `target academic year must not be Closed or Archived`. |
| `targets` | `student <id> has no target homeroom` — one per `promote` / `retain` decision without a target. |
| `enrollments` | `student <id> is already enrolled in the target academic year`, or `student <id>'s enrollment is no longer active` (e.g. transferred after evaluation). |
| `target_homerooms` | `student <id>'s target homeroom is no longer valid` — homeroom deleted, moved to another year, or its grade level relinked or renumbered since assignment. |

If a conflicting enrollment is created concurrently, after the checks pass,
the unique index `enrollment_one_active_per_student_year_uidx` rejects it and
the whole execution rolls back as `400 VALIDATION_ERROR` on `enrollments`.
Any other database failure is `500` and also rolls everything back.

Capacity is never checked; see `placement` in the run detail.

Errors:

| Code | HTTP | Cause |
|------|------|-------|
| `VALIDATION_ERROR` | 400 | Failed preconditions (see above). |
| `FORBIDDEN` | 403 | Missing `promotion.manage`. |
| — | 404 | Unknown or foreign run. |
| `PROMOTION_RUN_INVALID_STATUS` | 409 | Run is not `approved`, including a second execution, and the loser of two concurrent executions. |

## Events

Execution publishes, through the outbox and in the same transaction, one
event per decision: `student.promoted`, `student.retained` or
`student.graduated` — see `../events/student-promotion-events.md`. It does
not publish `student.enrolled` / `student.unenrolled`. The other promotion
endpoints publish nothing.

The promotion endpoints consume, through academic-ops projections:
`report_card.published`, `grading_policy.configured`, `grade_level.*`,
`report_type.promotion_source_changed` and `academic_year.*` — see
`../events/`. Closing a year (`academic_year.status_changed` → `Closed`)
turns that year's `lulus` graduates into `alumni`.
