# Event: teacher.account_linked

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service

## When It Is Emitted

When a tenant admin links a teacher profile to an IAM user account via
`PATCH /api/v1/academic-ops/teachers/:teacher_id/account`.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "teacher.account_linked",
  "occurred_at": "datetime",
  "payload": {
    "tenant_id": "uuid",
    "teacher_id": "uuid",
    "user_id": "uuid"
  }
}
```

## Notes

The grading service consumes this event to update the `teacher_user_id` column
on all `teaching_authz` projection rows belonging to this teacher. This ensures
that a teacher whose account was linked **after** they were assigned to a
class/subject can still record grades — the `teacher.assigned` event alone would
have projected `teacher_user_id: null` if the link did not exist at assignment
time.
