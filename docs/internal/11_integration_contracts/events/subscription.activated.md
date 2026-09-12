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
  "plan_code": "premium",
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
| `plan_code`       | string          | Plan code at activation (`starter` / `standard` / `premium` / operator-created). See note below. |
| `start_date`      | date (ISO 8601) | Activation date. |
| `end_date`        | date \| null    | `null` for open-ended subscriptions. **Always `null` today** — no code path sets or updates it, so subscription expiry is not yet observable. |
| `payment_method`  | string          | `manual` for phase 1 (no payment provider yet). Future values: `stripe`, `xendit`, etc. |

`plan_code` is **not** redundant with `plan_id`. No consumer can resolve a
billing plan UUID to a code on its own, and consumers key on the code:
platform-service projects it into `platform_subscription.plan_code` and
`platform_tenant.current_plan_code`. It was originally omitted, which left every
event-born tenant on the `'unknown'` placeholder — a value that matches no real
plan. `subscription.plan_changed` has always carried it; the two are now
consistent.

Both producers must stay in lockstep: the registration saga
(`billing-service/src/commands.rs`) and the demo seeder
(`billing-service/src/bin/seed.rs`), which replays this event for seeded
tenants.

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `subscription.activated`

## Ordering

Always published after `tenant.registered` for the same `tenant_id`.

## Versioning

Breaking changes use `subscription.activated_v2`. No `_v2` exists today.
