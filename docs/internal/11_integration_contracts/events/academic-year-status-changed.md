# Event: academic_year.status_changed

**Produced By:** Academic Config Service
**Consumed By:** Academic Operations Service, Grading Service

## When It Is Emitted

When an academic year successfully transitions to a new lifecycle status.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "academic_year.status_changed",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "academic_year_id": "uuid",
    "previous_status": "Draft",
    "status": "Active",
    "reason": "Alasan transisi ke aktif yang sah"
  }
}
```

## Notes

- **Bidirectional Transitions Warning**: Unlike traditional linear lifecycles, status changes in AcademiQ are bidirectional: `Draft ↔ Active` and `Active ↔ Closed`. Consumers must NOT assume transitions only move forward.
- Academic Operations uses this event to keep `known_academic_year.status` current and only allow homeroom creation for `Active` years.
- Grading Service uses this event to allow/reject grades and trigger long-term report-card archival when transitioning to `Archived`.

