# tenant.registered

Event published by `billing-service` after a tenant successfully completes
registration through `POST /api/v1/billing/tenants/register`. Phase 2's
academic-config service consumes it to gate academic-year creation.

## Envelope

Standard event envelope per
`docs/internal/13_engineering_standards/04_event_standards.md`:

```json
{
  "event_id": "uuid",
  "event_type": "tenant.registered",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "school_name": "string",
  "created_by_user_id": "uuid"
}
```

| Field                | Type   | Notes |
|----------------------|--------|-------|
| `tenant_id`          | uuid   | New tenant id (server-allocated). |
| `school_name`        | string | Submitted by the registration form. |
| `created_by_user_id` | uuid   | IAM user id of the tenant admin created during the saga. |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `tenant.registered`

## Ordering

`tenant.registered` MUST be published before `subscription.activated` for
the same tenant so consumers can assume the tenant exists when handling
the subscription event.

## Versioning

Breaking changes use `tenant.registered_v2` per the global event
standard. No `_v2` exists today.
