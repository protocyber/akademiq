# subscription.activated

Event published by `billing-service` after a subscription is activated.
The phase 1 registration saga emits this event for the very first
subscription a tenant receives. Future flows (renewal, plan change) emit
the same event with a different `subscription_id`.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "subscription.activated",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "subscription_id": "uuid",
  "plan_id": "uuid",
  "start_date": "YYYY-MM-DD",
  "end_date": null,
  "payment_method": "manual"
}
```

| Field             | Type            | Notes |
|-------------------|-----------------|-------|
| `tenant_id`       | uuid            | Owning tenant. |
| `subscription_id` | uuid            | Newly active subscription row. |
| `plan_id`         | uuid            | Plan id at activation. |
| `start_date`      | date (ISO 8601) | Activation date. |
| `end_date`        | date \| null    | `null` for open-ended subscriptions. |
| `payment_method`  | string          | `manual` for phase 1 (no payment provider yet). Future values: `stripe`, `xendit`, etc. |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `subscription.activated`

## Ordering

Always published after `tenant.registered` for the same `tenant_id`.

## Versioning

Breaking changes use `subscription.activated_v2`. No `_v2` exists today.
