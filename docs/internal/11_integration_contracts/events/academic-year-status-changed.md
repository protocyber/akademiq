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

- **Bidirectional Transitions Warning**: Unlike traditional linear lifecycles, status changes in AkademiQ are bidirectional: `Draft ↔ Active` and `Active ↔ Closed`. Consumers must NOT assume transitions only move forward.
- Academic Operations uses this event to keep `known_academic_year.status` current and only allow homeroom creation for `Active` years.
- Academic Operations also turns graduates into alumni on this event: when the new status is `Closed`, in the same transaction that stores it, students of this tenant with status `lulus` and a `graduation_record` for this year become `alumni`. The move is idempotent (a redelivery finds no `lulus` rows left) and, because transitions are bidirectional, reopening the year does not turn alumni back into `lulus`. See `student-promotion-events.md`.
- Grading Service uses this event to allow/reject grades and trigger long-term report-card archival when transitioning to `Archived`.

