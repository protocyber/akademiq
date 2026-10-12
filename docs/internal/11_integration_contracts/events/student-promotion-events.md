# Events: student promotion moves

**Event types:** `student.promoted`, `student.retained`, `student.graduated`  
**Produced By:** Academic Operations Service (promotion execution,
`POST /api/v1/academic-ops/promotion-runs/:run_id/execute`)  
**Consumed By:** Grading Service (`enrolled_student` projection)  

## When They Are Emitted
Executing an `approved` promotion run emits exactly one event per decision,
through the outbox, in the same transaction that moves the student. A run
either commits all its moves and all its events, or none. Execution happens
once per run; a second attempt is rejected (`409`), so a run never emits a
second set.

| Decision result | Event | Academic-ops effect in the same transaction |
|---|---|---|
| `promote` | `student.promoted` | old enrollment → `promoted`; new `active` enrollment in the target homeroom (grade-level ordinal + 1) |
| `retain` | `student.retained` | old enrollment → `promoted`; new `active` enrollment in the target homeroom (same ordinal); a `retention_record` |
| `graduate` | `student.graduated` | old enrollment → `promoted`; a `graduation_record`; `student.status` → `lulus` |

`promoted` on an enrollment means "this year is finished, the student moved
on"; it is used for retained and graduating students too.

## Payload Schemas (v1)

`student.promoted` and `student.retained` share one shape:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "run_id": "uuid",
  "from": { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "to":   { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "full_name": "string",
  "nis": "string"
}
```

`student.graduated` has no `to`:

```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "run_id": "uuid",
  "from": { "enrollment_id": "uuid", "homeroom_id": "uuid", "academic_year_id": "uuid" },
  "graduation_date": "date",
  "student_status": "lulus"
}
```

## Notes
- Execution does **not** emit `student.enrolled` / `student.unenrolled`.
  Those drive platform-service's student statistics, and a promotion does not
  change a tenant's student count. platform-service does not subscribe to
  these three events.
- `full_name` and `nis` let a consumer fill a new projection row exactly as it
  would from `student.enrolled`.
- `graduation_date` is the execution date (UTC).
- Grading Service, per event, in one transaction: sets the `from` row of
  `enrolled_student` to `promoted`; for `promoted` / `retained` it then upserts
  the `to` row as `active` (key `(tenant_id, student_id, academic_year_id)`).
  A missing `from` row logs a warning and the `to` row is still upserted.
  Redelivery leaves the same rows.
- Graduates become `alumni` later, without an event: when the graduating
  year's `academic_year.status_changed` arrives with status `Closed`,
  academic-ops sets that year's `lulus` graduates (by `graduation_record`) to
  `alumni` in the same transaction that stores the year status.
- RabbitMQ does not replay events published before a consumer's queue
  existed; there is no backfill script for these events.
