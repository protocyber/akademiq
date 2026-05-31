# Event: StudentEnrolled

**Produced By:** Academic Operations Service  
**Consumed By:** Notification Service, Attendance Service, Grading Service  

## When It Is Emitted
When a student is successfully enrolled into a homeroom for an academic year.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "homeroom_id": "uuid",
  "academic_year_id": "uuid"
}
```

## Notes
Used to initialize attendance eligibility and grading records.