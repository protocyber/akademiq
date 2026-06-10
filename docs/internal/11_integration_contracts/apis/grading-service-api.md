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

## POST /grades

Record a grade for an enrolled student. The recording teacher is the JWT
subject. The route requires the `grading` entitlement and an active subscription.

**Request**

```json
{
  "student_id": "uuid",
  "subject_id": "uuid",
  "academic_year_id": "uuid",
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
    "subject_id": "uuid",
    "academic_year_id": "uuid",
    "homeroom_id": "uuid",
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
- `403 NOT_ASSIGNED` when the teacher is not assigned to the student's homeroom/subject/year.
- `409 TEACHER_ACCOUNT_NOT_LINKED` when a teaching assignment exists but is not linked to a teacher user account.
- `422 STUDENT_NOT_ENROLLED` when the student is not actively enrolled for the year.

## PATCH /grades/{id}

Update an existing grade score. The route requires the `grading` entitlement,
checks the grade editability checkpoint, and re-applies teacher assignment
authorization.

**Request**

```json
{ "score": 91 }
```

**Response 200**

Same grade shape as `POST /grades`.

## GET /grades?homeroom_id=&subject_id=&academic_year_id=

Return the grade grid for one homeroom, subject, and academic year.

**Response 200**

```json
{
  "data": [
    {
      "grade_id": "uuid",
      "student_id": "uuid",
      "subject_id": "uuid",
      "academic_year_id": "uuid",
      "homeroom_id": "uuid",
      "score": 88,
      "recorded_by": "uuid"
    }
  ],
  "meta": {}
}
```

## GET /students/{id}/grades?academic_year_id=

Return every subject grade for a student in an academic year. This is the raw
input consumed by the report-card workflow.

**Response 200**

```json
{
  "data": [
    { "subject_id": "uuid", "score": 88 }
  ],
  "meta": {}
}
```

## POST /report-cards/{id}/approve

Deferred to `mvp-report-card-workflow`.
