# Integration Contracts

This folder defines cross-service communication contracts. Every event
or API a service depends on MUST be documented here before the
delivering openspec change is archived.

## APIs (synchronous REST)

| Service                 | File                                       |
|-------------------------|--------------------------------------------|
| Identity & Access (IAM) | [`apis/iam-service-api.md`](./apis/iam-service-api.md) |
| Tenant & Subscription   | [`apis/billing-service-api.md`](./apis/billing-service-api.md) |
| Academic Configuration  | [`apis/academic-config-api.md`](./apis/academic-config-api.md) |
| Academic Operations     | [`apis/academic-operations-api.md`](./apis/academic-operations-api.md) |
| Attendance              | [`apis/attendance-service-api.md`](./apis/attendance-service-api.md) |
| Grading                 | [`apis/grading-service-api.md`](./apis/grading-service-api.md) |
| Promotion               | [`apis/promotion-service-api.md`](./apis/promotion-service-api.md) |

All endpoints follow `13_engineering_standards/03_api_conventions.md`
envelopes:

- Success: `{ "data": ..., "meta": ... }`
- Error: `{ "error": { "code", "message", "fields?" } }`

Validation errors follow
`13_engineering_standards/14_validation_contract.md` (`fields` map keyed
by request-body field name, aligned with the frontend Zod schemas).

## Events (asynchronous, RabbitMQ)

Standard envelope per `13_engineering_standards/04_event_standards.md`:

```json
{
  "event_id": "uuid",
  "event_type": "domain.action.past",
  "occurred_at": "RFC3339",
  "payload": { /* per-event */ }
}
```

Events are published to the `akademiq.events` topic exchange. Routing
key matches `event_type`. Breaking changes use `event_type_v2`.

| Event name                | Producer            | File                                        |
|---------------------------|---------------------|---------------------------------------------|
| `tenant.registered`       | billing-service     | [`events/tenant.registered.md`](./events/tenant.registered.md) |
| `subscription.activated`  | billing-service     | [`events/subscription.activated.md`](./events/subscription.activated.md) |
| `subscription-upgraded`   | billing-service     | [`events/subscription-upgraded.md`](./events/subscription-upgraded.md) |
| `student.enrolled`        | academic-ops        | [`events/student-enrolled.md`](./events/student-enrolled.md) |
| `attendance.recorded`     | attendance          | [`events/attendance-recorded.md`](./events/attendance-recorded.md) |
| `report_card.approved`    | grading             | [`events/report-card-approved.md`](./events/report-card-approved.md) |
| `academic_year.closed`    | academic-config     | [`events/academic-year-closed.md`](./events/academic-year-closed.md) |
