# Event: academic_year.status_changed

**Produced By:** Academic Config Service
**Consumed By:** Academic Operations Service

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
    "previous_status": "Planning",
    "status": "Configuration"
  }
}
```

## Notes

Academic Operations uses this event to keep `known_academic_year.status` current
and only allow homeroom creation for `Active` years.
