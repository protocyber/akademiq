# Event: AcademicYearClosed

**Produced By:** Academic Config Service  
**Consumed By:** Promotion Service, Reporting modules

## When It Is Emitted
When an academic year transitions to Closed state.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "academic_year_id": "uuid"
}
```