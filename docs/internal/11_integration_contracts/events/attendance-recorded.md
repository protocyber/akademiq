# Event: AttendanceRecorded

**Produced By:** Attendance Service  
**Consumed By:** Notification Service, Analytics (future)

## When It Is Emitted
Each time a student's attendance is recorded.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "session_id": "uuid",
  "status": "present | absent | late"
}
```