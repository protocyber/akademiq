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

## GET /evaluations?homeroom_id=&subject_id=&academic_year_id=

List evaluations for a class+subject+year in column order (`position` asc).
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

Create an evaluation column for a class+subject+year. Requires the `grading`
entitlement. The caller must be assigned to the subject+homeroom+year or be a
tenant admin.

**Request**

```json
{
  "homeroom_id": "uuid",
  "subject_id": "uuid",
  "academic_year_id": "uuid",
  "code": "UH1",
  "name": "Ulangan Harian 1",
  "position": 1
}
```

**Response 201** — same evaluation shape as the list item above.

**Errors**

- `403 NOT_ASSIGNED` when caller is not assigned to this scope.
- `409 DUPLICATE_EVALUATION_CODE` when `code` already exists for this class+subject+year.

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
- `409 GRADES_LOCKED` when a report card for the student/year has left `Draft`.
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

## POST /report-cards/generate

Generate or refresh Draft report cards for every active student in a homeroom.
Cards already past `Draft` are skipped and reported in the response.

**Request**

```json
{ "homeroom_id": "uuid", "academic_year_id": "uuid" }
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
        "status": "Draft",
        "summary": {
          "evaluations": [
            { "evaluation_id": "uuid", "score": 88, "passed": true }
          ],
          "average_score": 88,
          "pass_count": 1,
          "total_evaluations": 1,
          "incomplete": false
        }
      }
    ],
    "skipped": ["student_uuid"]
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

## GET /report-cards?homeroom_id=&academic_year_id=

Return the staff workflow board for a homeroom/year.

## GET /report-cards/{id}

Return report-card detail, raw grades, and approval history.

**Response 200**

```json
{
  "data": {
    "report_card": { "report_card_id": "uuid", "status": "HomeroomReview" },
    "grades": [{ "evaluation_id": "uuid", "score": 88 }],
    "approvals": [{ "action": "submit", "role": "subject_teacher" }]
  },
  "meta": {}
}
```

## GET /students/{id}/report-card?academic_year_id=

Return a report card to student/parent callers only when the card is `Published`
or `Archived`. Pre-publish cards return `404` to avoid revealing existence.
