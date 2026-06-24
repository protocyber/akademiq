# Event: StudentProfileUpdated

**Produced By:** Academic Operations Service  
**Consumed By:** Grading Service

## When It Is Emitted
When a student's display profile is updated.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "full_name": "string",
  "nis": "string"
}
```

## Notes
Used by grading-service to refresh display fields in its `enrolled_student` projection.
