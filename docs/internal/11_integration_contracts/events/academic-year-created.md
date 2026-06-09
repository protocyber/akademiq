# academic_year.created

Event published by `academic-config-service` after a tenant successfully
creates an academic year through `POST /api/v1/academic-config/academic-years`.
Academic Operations consumes this event before creating year-scoped homerooms.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "academic_year.created",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "academic_year_id": "uuid",
  "name": "2026/2027",
  "start_date": "2026-07-01",
  "end_date": "2027-06-30"
}
```

| Field              | Type            | Notes |
|--------------------|-----------------|-------|
| `tenant_id`        | uuid            | Owning tenant resolved from the JWT. |
| `academic_year_id` | uuid            | Server-allocated academic year id. |
| `name`             | string          | Human-readable academic year name. |
| `start_date`       | date (ISO 8601) | First date in the academic year. |
| `end_date`         | date (ISO 8601) | Last date in the academic year. |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `academic_year.created`

## Ordering

Published from the academic-config outbox in `event_id` order after the
`academic_year` row commits.

## Versioning

Breaking changes use `academic_year.created_v2`. No `_v2` exists today.
