# Event Messaging Standards

## Transport
RabbitMQ (initial implementation)

## Event Naming
`domain.action.past`

Example:
`student.enrolled`
`report_card.approved`

## Envelope Format
```json
{
  "event_id": "uuid",
  "event_type": "string",
  "occurred_at": "datetime",
  "payload": {}
}
```

## Versioning
Use `event_type_v2` for breaking changes.