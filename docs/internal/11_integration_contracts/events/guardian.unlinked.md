# Event: guardian.unlinked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant admin unlinks a guardian from a student profile.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "guardian.unlinked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "student_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to remove the corresponding authorization record from the `student_authz` projection table.
