# Promotion API (Academic Operations Service)

Grade promotion (kenaikan kelas) is implemented inside
**academic-ops-service**, not as a separate service. Base path:
`/api/v1/academic-ops`. All endpoints use the standard success and error
envelopes from `13_engineering_standards/03_api_conventions.md`, resolve
`tenant_id` from the JWT and never from the request body, and are guarded by
the existing `academic_ops` entitlement (a tenant without it gets
`403 FEATURE_NOT_AVAILABLE`). There is no separate `promotion` feature code.

Design: `docs/superpowers/specs/2026-09-26-promotion-evaluation-design.md`.

## Model

A **promotion run** evaluates one academic year. It freezes the criteria in a
rule snapshot, reads the frozen report scores of the year's promotion-source
report type (`known_report_type`), and writes one **decision** per evaluable
student. At most one run per tenant and academic year may be open (status
other than `executed`); a partial unique index enforces this.

Run status: `draft` → `submitted` → `approved`. `return` sends a submitted
run back to `draft`. Execution (`executed`) is Plan 3c and has no endpoint yet.

Each decision keeps the engine's `recommended` result and the effective
`result`. An override changes `result` only and requires a reason;
`recommended` is never rewritten.

## Permissions

| Permission | Granted to | Endpoints |
|---|---|---|
| `promotion.manage` | `tenant_admin` | create, re-evaluate, override, submit |
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
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

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
    "cannot_evaluate": ["student-uuid"]
  },
  "meta": {}
}
```

`criteria` and `kkm` come from the run's current rule snapshot. `counts`
group decisions by effective `result`. `cannot_evaluate` is recomputed on
each request. Unknown or foreign run → `404`.

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
  }
}
```

`result` and `recommended` are always one of `promote`, `retain`, `graduate`.

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

## Events

The promotion endpoints publish no events yet (execution, Plan 3c, will).
They consume, through academic-ops projections:
`report_card.published`, `grading_policy.configured`, `grade_level.*` and
`report_type.promotion_source_changed` — see `../events/`.
