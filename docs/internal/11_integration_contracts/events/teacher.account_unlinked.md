# Event: teacher.account_unlinked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant admin unlinks a teacher profile from its IAM user account via
`DELETE /api/v1/academic-ops/teachers/:teacher_id/account`.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "teacher.account_unlinked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "teacher_id": "uuid",
    "user_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to set `teacher_user_id = NULL` on all
`teaching_authz` projection rows belonging to this teacher. Subsequent grade
recording attempts by the formerly-linked user will be rejected with
`TEACHER_ACCOUNT_NOT_LINKED` until a new account is linked.
