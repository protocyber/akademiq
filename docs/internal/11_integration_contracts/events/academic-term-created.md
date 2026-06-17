# academic_term.created

Event published by `academic-config-service` after an academic term is created — either auto-seeded when a year is created or explicitly via `POST /api/v1/academic-config/academic-years/{id}/terms`.

Consumed by:
- `grading-service`: upserts `valid_term` projection.
- `academic-ops-service`: upserts `known_academic_term` projection.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "academic_term.created",
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
  "name": "Semester 1",
  "start_date": "2026-07-01",
  "end_date": "2026-12-31",
  "status": "Draft"
}
```

| Field              | Type            | Notes |
|--------------------|-----------------|-------|
| `tenant_id`        | uuid            | Owning tenant resolved from the JWT. |
| `term_id`          | uuid            | Server-allocated term id. |
| `academic_year_id` | uuid            | Parent academic year. |
| `name`             | string          | Human-readable term name (e.g. "Semester 1"). |
| `start_date`       | date (ISO 8601) | First date of the term. |
| `end_date`         | date (ISO 8601) | Last date of the term. |
| `status`           | string          | Always `"Draft"` on creation. |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `academic_term.created`

## Ordering

Published from the academic-config outbox in `event_id` order after the `academic_term` row commits. When a year is created the `academic_year.created` and `academic_term.created` events are enqueued in the same transaction; `academic_year.created` is enqueued first.

## Versioning

Breaking changes use `academic_term.created_v2`. No `_v2` exists today.
