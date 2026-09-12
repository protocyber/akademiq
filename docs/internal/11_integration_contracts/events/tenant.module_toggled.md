# tenant.module_toggled

Event published by `billing_service` after a tenant module is successfully
toggled on or off. Emitted on **every** successful toggle, whether it was
initiated by a tenant admin via
`PATCH /api/v1/billing/tenants/me/modules` or by a platform operator via
`PATCH /api/v1/billing/internal/tenants/:id/modules`.

A rejected toggle publishes nothing. The command enforces the plan
entitlement (`FEATURE_NOT_AVAILABLE`) and subscription-status
(`SUBSCRIPTION_EXPIRED`) rules before any write, so an unentitled or expired
tenant produces neither a `tenant_module` row nor an event.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "tenant.module_toggled",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "feature_code": "grading",
  "enabled": false
}
```

| Field          | Type    | Notes |
|----------------|---------|-------|
| `tenant_id`    | uuid    | Tenant whose module changed. |
| `feature_code` | string  | Feature code from `features.toml`, e.g. `grading`, `attendance`. |
| `enabled`      | bool    | The module's state *after* the toggle. |

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `tenant.module_toggled`

## Consumers

- `platform_service` — updates its tenant module projection.

## Ordering

**This event may arrive before any subscription event for the same
`tenant_id`.** Do not assume a preceding `subscription.activated`.

A toggle does require an active subscription, but not every active
subscription announces itself with `subscription.activated`. When a platform
operator calls `POST /internal/tenants/{tenant_id}/subscription` for a tenant
that has no subscription row yet, `internal_override_subscription` INSERTs one
and emits only `subscription.plan_changed` — `subscription.activated` never
fires for that tenant. A subsequent module toggle is therefore the first
`tenant_id`-bearing event some consumers will see.

Consumers must **UPSERT** their projection row rather than assume it already
exists, and must be idempotent: the payload carries the resulting state rather
than a delta, so replaying it is safe.

The module row and this event are written in the same transaction, so a
committed toggle is always observable downstream.

## Versioning

Breaking changes use `tenant.module_toggled_v2`. No `_v2` exists today.
