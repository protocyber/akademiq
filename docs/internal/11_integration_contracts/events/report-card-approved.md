# Event: ReportCardApproved

**Produced By:** Grading Service  
**Consumed By:** Notification Service, Promotion Service  

## When It Is Emitted
After the principal approves a student's report card.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "academic_year_id": "uuid",
  "report_card_id": "uuid"
}
```

## Notes
Triggers parent notifications and promotion evaluation.