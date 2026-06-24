# Grading Service API

Base path: `/api/v1/grading`

All endpoints are tenant-scoped from the bearer JWT. Success responses use
`{ "data": ..., "meta": {} }`; errors use the standard API error envelope.

## GET /healthz

Health check. Verifies database and RabbitMQ connectivity.

**Response 200**

```json
{ "data": { "status": "ok" }, "meta": {} }
```

## GET /evaluations?homeroom_id=&subject_id=&academic_year_id=[&term_id=]

List evaluations for a class+subject+year in column order (`position` asc). Optional `term_id` filters to a specific term.
No entitlement check — any authenticated user can read.

**Response 200**

```json
{
  "data": [
    {
      "evaluation_id": "uuid",
      "tenant_id": "uuid",
      "homeroom_id": "uuid",
      "subject_id": "uuid",
      "academic_year_id": "uuid",
      "term_id": "uuid",
      "code": "UH1",
      "name": "Ulangan Harian 1",
      "position": 1,
      "created_at": "2026-06-10T00:00:00Z",
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

## POST /evaluations

Create an evaluation column for a class+subject+year+term. Requires the `grading`
entitlement. The caller must be assigned to the subject+homeroom+year or be a
tenant admin. The referenced term must be `Draft` or `Active`.

**Request**

```json
{
  "homeroom_id": "uuid",
  "subject_id": "uuid",
  "academic_year_id": "uuid",
  "term_id": "uuid",
  "code": "UH1",
  "name": "Ulangan Harian 1",
  "position": 1
}
```

**Response 201** — same evaluation shape as the list item above.

**Errors**

- `403 NOT_ASSIGNED` when caller is not assigned to this scope.
- `409 DUPLICATE_EVALUATION_CODE` when `code` already exists for this class+subject+year+term.
- `409 TERM_NOT_EDITABLE` when the referenced term is not `Draft` or `Active`.

## PATCH /evaluations/{id}

Update an evaluation's `code`, `name`, and/or `position`. Omitted fields are
left unchanged. Same authorization as POST.

**Request**

```json
{ "code": "UH1-rev", "name": "Ulangan Harian 1 (revisi)", "position": 2 }
```

**Response 200** — updated evaluation shape.

**Errors**

- `403 NOT_ASSIGNED`
- `404` when the evaluation is not found.
- `409 DUPLICATE_EVALUATION_CODE`

## DELETE /evaluations/{id}

Delete an evaluation. Cascades to all grades referencing it. Same
authorization as POST.

**Response 204** (no body).

**Errors**

- `403 NOT_ASSIGNED`
- `404` when the evaluation is not found.

## GET /evaluation-templates?term_id=

List template evaluations for a term in `position` order.

**Response 200**

```json
{
  "data": [
    {
      "template_id": "uuid",
      "tenant_id": "uuid",
      "term_id": "uuid",
      "code": "UH1",
      "name": "Ulangan Harian 1",
      "position": 1,
      "created_at": "2026-06-10T00:00:00Z",
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

## POST /evaluation-templates

Create a term template evaluation. Requires `academic.config.write`; `tenant_id` is resolved from the projected term.

```json
{ "term_id": "uuid", "code": "UH1", "name": "Ulangan Harian 1", "position": 1 }
```

**Response 201** — same shape as list item.

**Errors**

- `403 FORBIDDEN` when the caller lacks `academic.config.write` or term tenant mismatches.
- `409 DUPLICATE_EVALUATION_CODE` when `code` already exists for the term.

## PATCH /evaluation-templates/{id}

Update `code`, `name`, and/or `position`. Requires `academic.config.write`.

```json
{ "code": "UH1", "name": "Ulangan Harian 1", "position": 1 }
```

**Response 200** — updated template.

## DELETE /evaluation-templates/{id}

Delete a template evaluation and its template weights. Concrete evaluations already materialized are not deleted.

**Response 204**

## GET /report-types/{id}/formula-templates

List weight template rows for a report type.

```json
{
  "data": [
    {
      "report_type_id": "uuid",
      "evaluation_template_id": "uuid",
      "weight": 25,
      "created_at": "2026-06-10T00:00:00Z",
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

## PUT /report-types/{id}/formula-templates

Replace the report type's template weights. Requires `academic.config.write`; referenced template evaluations must belong to the same term and weights must total 100.

```json
{ "weights": { "evaluation-template-uuid": 25, "other-template-uuid": 75 } }
```

**Response 204**

**Errors**

- `400 VALIDATION_ERROR` when weights are invalid, not numeric, cross-term, or do not total 100.

## POST /evaluation-templates/apply

Backfill concrete evaluations and weights for assignments in a term that have no evaluations yet. Idempotent. Requires `academic.config.write`.

```json
{ "term_id": "uuid" }
```

**Response 200**

```json
{ "data": { "evaluations_created": 12, "weights_created": 24 }, "meta": {} }
```

## GET /evaluation-templates/unmaterialized-count?term_id=

Return the count of projected teaching assignments in a term that have zero concrete evaluations.

```json
{ "data": { "count": 3 }, "meta": {} }
```

## POST /grades

Record or update a grade for an enrolled student keyed by evaluation. Idempotent
upsert on `(tenant, student, evaluation_id)`. Requires the `grading`
entitlement and an active subscription. The recording teacher is the JWT subject;
subject/homeroom/year are derived from the referenced evaluation.

**Request**

```json
{
  "student_id": "uuid",
  "evaluation_id": "uuid",
  "score": 88
}
```

**Response 201**

```json
{
  "data": {
    "grade_id": "uuid",
    "tenant_id": "uuid",
    "student_id": "uuid",
    "evaluation_id": "uuid",
    "score": 88,
    "recorded_by": "uuid",
    "created_at": "2026-06-10T00:00:00Z",
    "updated_at": "2026-06-10T00:00:00Z"
  },
  "meta": {}
}
```

**Errors**

- `400 VALIDATION_ERROR` with `fields.score` when score is outside `0..100`.
- `403 FEATURE_NOT_AVAILABLE` when the tenant is not entitled to grading.
- `403 NOT_ASSIGNED` when the teacher is not assigned to the evaluation's scope.
- `409 GRADES_LOCKED` when any report card for the student/year has left `Draft`.
- `409 YEAR_NOT_ACTIVE` when the evaluation's academic year is not `Active`.
- `409 TERM_NOT_ACTIVE` when the evaluation's term is not `Active`.
- `409 TEACHER_ACCOUNT_NOT_LINKED` when a teaching assignment exists but is not linked to a teacher user account.
- `422 STUDENT_NOT_ENROLLED` when the student is not actively enrolled in the evaluation's homeroom for the year.

## GET /grades?homeroom_id=&subject_id=&academic_year_id=

Return the grade grid for one homeroom, subject, and academic year. Grades are
joined via the evaluation table so the response covers all evaluations in scope.
The client can index the result by `(student_id, evaluation_id)`.

**Response 200**

```json
{
  "data": [
    {
      "grade_id": "uuid",
      "student_id": "uuid",
      "evaluation_id": "uuid",
      "score": 88,
      "recorded_by": "uuid"
    }
  ],
  "meta": {}
}
```

## GET /homerooms/{homeroom_id}/roster?academic_year_id=

Return active students for one homeroom and academic year from grading-service's `enrolled_student` projection. Requires `grade.read`.

**Response 200**

```json
{
  "data": [
    {
      "student_id": "uuid",
      "full_name": "Student One",
      "nis": "S-001"
    }
  ],
  "meta": {}
}
```

## GET /students/{id}/grades?academic_year_id=

Return every evaluation grade for a student in an academic year. Grades are
joined via the evaluation table to filter by year.

**Response 200**

```json
{
  "data": [
    { "evaluation_id": "uuid", "score": 88 }
  ],
  "meta": {}
}
```

---

## Report Types

A report type is a named report run scoped to an **academic year and term** — for example "Rapor Tengah Semester" (`code` "Rapor UTS"). The `code` doubles as the grade-entry column title. Every report card belongs to exactly one report type; a card is unique per `(report_type_id, student_id)`. Report types are NOT scoped to a homeroom. A report formula may only reference evaluations from the same term as the report type (`EVALUATION_TERM_MISMATCH`).

## GET /report-types?academic_year_id=[&term_id=]

List all report types for an academic year in `position` order. Optional `term_id` filters to a specific term. No entitlement check.

**Response 200**

```json
{
  "data": [
    {
      "report_type_id": "uuid",
      "tenant_id": "uuid",
      "academic_year_id": "uuid",
      "term_id": "uuid",
      "code": "Rapor UTS",
      "name": "Rapor Tengah Semester",
      "position": 0,
      "created_at": "2026-06-10T00:00:00Z",
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

## Term-related error codes

| Code | HTTP | Trigger |
|------|------|---------|
| `TERM_NOT_EDITABLE` | 409 | Create/edit evaluation when term is not `Draft` or `Active` |
| `TERM_NOT_ACTIVE` | 409 | Record grade when term is not `Active` |
| `EVALUATION_TERM_MISMATCH` | 409 | Add report formula linking evaluation from a different term than the report type |

## POST /report-types

Create a report type. Requires `grading` entitlement and `tenant_admin` role.
`position` is assigned automatically (appended after existing types for the year).

**Request**

```json
{
  "academic_year_id": "uuid",
  "code": "Rapor UTS",
  "name": "Rapor Tengah Semester"
}
```

**Response 201** — report type shape (see GET above).

**Errors**

- `400 VALIDATION_ERROR` with `fields.code` / `fields.name` when either is empty.
- `403 WRONG_APPROVER_ROLE` when caller is not a tenant admin.
- `409 DUPLICATE_REPORT_TYPE_CODE` when `code` already exists for the academic year.

## PATCH /report-types/{id}

Update a report type's `code`, `name`, and/or `position`. Omitted fields are left
unchanged. Requires `grading` entitlement and `tenant_admin` role.

**Request**

```json
{ "code": "Rapor UTS", "name": "Rapor Tengah Semester", "position": 1 }
```

**Response 200** — updated report type shape.

**Errors**

- `403 WRONG_APPROVER_ROLE`
- `404` when the report type is not found.
- `409 DUPLICATE_REPORT_TYPE_CODE`

## DELETE /report-types/{id}

Delete a report type and cascade-delete its report cards, formulas, and scores.
Requires `grading` entitlement and `tenant_admin` role.

**Response 204** (no body).

**Errors**

- `403 WRONG_APPROVER_ROLE`
- `404` when the report type is not found.

---

## Report Formulas

A formula stores each evaluation's percentage weight for one subject within a
report type (the `(report_type × evaluation)` many-to-many). Because an
evaluation is scoped to `(homeroom, subject, year)`, a weight inherits its
subject. The same evaluation may contribute to several report types with
different weights. A subject's formula within a report type is **valid only when
its evaluation weights sum to exactly 100**; otherwise the subject is treated as
not-configured (no live report score, blank in the grade-entry grid).

## GET /report-types/{id}/formulas

List all `(report_type, evaluation)` weight rows for a report type (joined to
evaluation so they are returned in subject then position order). No entitlement
check.

**Response 200**

```json
{
  "data": [
    {
      "report_type_id": "uuid",
      "evaluation_id": "uuid",
      "weight": 25,
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

## PUT /report-types/{id}/formulas/{subject_id}

Upsert the `(report_type, subject)` formula as a batch of evaluation weights —
replaces the existing weights for that subject under the report type. All
`evaluation_id` keys must belong to the given subject. Requires `grading`
entitlement.

**Request**

```json
{ "weights": { "<evaluation_id>": 25, "<evaluation_id>": 75 } }
```

**Response 204** (no body).

**Errors**

- `400 VALIDATION_ERROR` when a weight key is not an evaluation id or a value is not a number.
- `400 INVALID_WEIGHTS` when the subject's percentages do not sum to exactly 100.
- `404` when the report type is not found.

---

## Subject Report Scores (live)

`subject_report_score` is the live "Nilai Rapor" per `(report_type, subject,
student)`, recomputed automatically whenever a grade is saved. For every report
type whose `(report_type, subject)` formula includes the saved evaluation and is
valid (Σ = 100), the service recomputes the student's score as
`Σ score(evaluation) × weight / 100` (missing evaluation score = 0). A subject
whose formula is not valid has no live score (blank).

## GET /subject-report-scores?report_type_id=&homeroom_id=&subject_id=

Return the live report-score column for a `(report_type, homeroom, subject)` —
one row per student, used to render the read-only grade-entry grid columns. No
entitlement check.

**Response 200**

```json
{
  "data": [
    {
      "tenant_id": "uuid",
      "academic_year_id": "uuid",
      "homeroom_id": "uuid",
      "subject_id": "uuid",
      "student_id": "uuid",
      "report_type_id": "uuid",
      "score": 82.5,
      "updated_at": "2026-06-10T00:00:00Z"
    }
  ],
  "meta": {}
}
```

> The explicit `[Hitung Nilai]` compute action has been removed. Per-subject
> scores are produced live on grade save (above) and frozen at draft generation
> (see `POST /report-cards/generate`). There is no `POST /report-batches/{id}/compute`
> and no `/report-batches` routes.

---

## Report Cards

## POST /report-cards/generate

Generate or refresh report cards for a `(report_type, homeroom)`. For every
actively-enrolled student it upserts an empty `Draft` card if absent, then — for
cards still in `Draft` — **freezes a snapshot**: copies the current live
`subject_report_score` rows for that `(report_type, student)` into
`report_subject_score` (`computed_at` stamped), writes the report type's valid
weights into `report_card.weights_snapshot` (`{ subject_id: { evaluation_id: weight } }`),
and derives `summary` pass/fail from the frozen scores versus the year's
`minimum_passing_score`. Cards past `Draft` are skipped and reported. Generation
is idempotent per `(report_type_id, student_id)` and refreshes only `Draft`
cards; editing grades after generation does not change a card's frozen scores
until generation is re-run.

Requires `grading` entitlement and `report.generate` permission.

**Request**

```json
{ "report_type_id": "uuid", "homeroom_id": "uuid" }
```

**Response 201**

```json
{
  "data": {
    "generated": [
      {
        "report_card_id": "uuid",
        "student_id": "uuid",
        "academic_year_id": "uuid",
        "homeroom_id": "uuid",
        "report_type_id": "uuid",
        "status": "Draft",
        "summary": {
          "subjects": [],
          "average_score": null,
          "pass_count": 0,
          "total_subjects": 0,
          "incomplete": true
        },
        "weights_snapshot": {
          "<subject_id>": { "<evaluation_id>": 25, "<evaluation_id>": 75 }
        }
      }
    ],
    "skipped": ["student_uuid"]
  },
  "meta": {}
}
```

**Errors**

- `403 WRONG_APPROVER_ROLE` when caller lacks `report.generate`.
- `404` when the report type is not found.
- `409 GRADING_POLICY_NOT_CONFIGURED` when the year has no minimum passing score.

## GET /report-cards?report_type_id=&homeroom_id=

Return the staff workflow board for a `(report_type, homeroom)`. Cards are
ordered by status then student.

**Response 200** — array of report card objects (see generate shape above).

## GET /report-cards/{id}

Return report-card detail including raw evaluation grades, frozen subject scores,
and approval history.

**Response 200**

```json
{
  "data": {
    "report_card": {
      "report_card_id": "uuid",
      "report_type_id": "uuid",
      "status": "HomeroomReview"
    },
    "grades": [{ "evaluation_id": "uuid", "score": 88 }],
    "subject_scores": [
      { "subject_id": "uuid", "final_score": 82.5, "computed_at": "2026-06-10T00:00:00Z" }
    ],
    "approvals": [{ "action": "submit", "role": "subject_teacher" }]
  },
  "meta": {}
}
```

## PATCH /report-cards/{id}/submit

Move `Draft` → `HomeroomReview`. Allowed for a subject teacher or homeroom
teacher scoped to the class.

## PATCH /report-cards/{id}/homeroom-approve

Move `HomeroomReview` → `PrincipalApproval`. Allowed for the homeroom teacher.

## PATCH /report-cards/{id}/return

Move `HomeroomReview` → `Draft` and re-open grade editing. Allowed for the
homeroom teacher.

## PATCH /report-cards/{id}/principal-approve

Move `PrincipalApproval` → `Published`. Allowed for the principal. Emits
`report_card.approved`.

## PATCH /report-cards/{id}/reject

Move `PrincipalApproval` → `HomeroomReview`. Allowed for the principal.

Transition requests accept an optional note:

```json
{ "note": "Needs correction" }
```

Transition responses return the updated report-card shape. Every successful
transition appends a `report_approval` audit row.

**Transition errors**

- `403 WRONG_APPROVER_ROLE` when the caller role/scope cannot perform the transition.
- `409 INVALID_STATE_TRANSITION` when the card status is not valid for the action.

## GET /students/{id}/report-card?academic_year_id=

Return the most-recently published report card for a student in a year.
Returns `404` for pre-publish cards to avoid revealing existence.

**Response 200** — same shape as `GET /report-cards/{id}`.
