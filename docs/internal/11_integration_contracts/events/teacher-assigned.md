# Event: teacher.assigned

**Produced By:** Academic Operations Service
**Consumed By:** Grading Service, Academic Config Service

## When It Is Emitted

When a tenant successfully assigns a teacher to teach a subject in a homeroom
for an academic year.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "teacher.assigned",
  "occurred_at": "datetime",
  "payload": {
    "assignment_id": "uuid",
    "tenant_id": "uuid",
    "teacher_id": "uuid",
    "teacher_user_id": "uuid-or-null",
    "subject_id": "uuid",
    "homeroom_id": "uuid",
    "academic_year_id": "uuid"
  }
}
```

## Notes

The grading service uses this tuple as its authorization projection for who may
record grades for a subject in a class. `teacher_user_id` is the IAM user id
linked to the teacher profile. When it is `null`, grading stores the assignment
but rejects writes with `TEACHER_ACCOUNT_NOT_LINKED` so admins know the profile
must be linked before the teacher can enter grades.

The academic-config service also consumes this event (keyed by `assignment_id`)
to maintain a local usage projection that powers the `YEAR_IN_USE` and
`SUBJECT_IN_USE` referential delete guards — it cannot read the ops tables
directly because they live in a separate database.

`teacher_user_id` is also refreshed by the `teacher.account_linked` and
`teacher.account_unlinked` events, which fire when the teacher's IAM account is
linked or unlinked independently of the assignment. See those event contracts
for details.
