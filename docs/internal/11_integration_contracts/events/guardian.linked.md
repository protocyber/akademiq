# Event: guardian.linked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant admin links a guardian (parent/guardian user account) to a student profile.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "guardian.linked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "student_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to maintain the `student_authz` projection mapping the guardian to the student profile with relation `guardian`.
