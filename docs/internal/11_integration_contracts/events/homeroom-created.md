# Event: homeroom.created

**Produced By:** Academic Operations Service
**Consumed By:** Academic Config Service

## When It Is Emitted

When a tenant successfully creates a homeroom scoped to an academic year.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "homeroom.created",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "homeroom_id": "uuid",
    "academic_year_id": "uuid"
  }
}
```

## Notes

The academic-config service consumes this event (keyed by `homeroom_id`) to
maintain a local usage projection that powers the `YEAR_IN_USE` referential
delete guard — an academic year cannot be deleted while any homeroom or
teaching assignment references it. Academic-config cannot read the ops tables
directly because they live in a separate database. The projection upsert is
idempotent so event redelivery is safe.
