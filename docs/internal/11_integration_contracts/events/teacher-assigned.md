# Event: teacher.assigned

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant successfully assigns a teacher to teach a subject in a homeroom
for an academic year.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "teacher.assigned",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "teacher_id": "uuid",
    "subject_id": "uuid",
    "homeroom_id": "uuid",
    "academic_year_id": "uuid"
  }
}
```

## Notes

The grading service uses this tuple as its authorization projection for who may
record grades for a subject in a class.
