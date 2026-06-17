# academic_term.status_changed

Event published by `academic-config-service` after an academic term's lifecycle status changes via `PATCH /api/v1/academic-config/academic-terms/{id}/status`.

Consumed by:
- `grading-service`: upserts `valid_term` projection with the new status.
- `academic-ops-service`: upserts `known_academic_term` projection with the new status.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "academic_term.status_changed",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "term_id": "uuid",
  "academic_year_id": "uuid",
  "previous_status": "Draft",
  "status": "Active",
  "reason": "Semester dimulai resmi hari ini"
}
```

| Field               | Type   | Notes |
|---------------------|--------|-------|
| `tenant_id`         | uuid   | Owning tenant resolved from the JWT. |
| `term_id`           | uuid   | The term that changed status. |
| `academic_year_id`  | uuid   | Parent academic year. |
| `previous_status`   | string | Status before the transition. |
| `status`            | string | New status after the transition. |
| `reason`            | string | Operator-supplied reason (min 10 chars). |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `academic_term.status_changed`

## Idempotency

Consumers upsert the `valid_term` / `known_academic_term` row on `term_id`. Re-delivering the same event is a no-op.

## Versioning

Breaking changes use `academic_term.status_changed_v2`. No `_v2` exists today.
