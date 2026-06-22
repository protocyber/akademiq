# Event: student.account_unlinked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant admin unlinks a student profile from its IAM user account via
`DELETE /api/v1/academic-ops/students/:student_id/account`.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "student.account_unlinked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "student_id": "uuid",
    "user_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to remove the corresponding
`student_authz` projection row (relation `self`). After unlinking, the student
can no longer view their own report cards until a new account is linked via
`PATCH /api/v1/academic-ops/students/:student_id/account`.
