# Event: student.account_linked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant successfully links a student profile to an IAM user account.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "student.account_linked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "student_id": "uuid",
    "user_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to maintain the `student_authz` projection mapping the owner to their student profile with relation `self`.
