# Event: SubscriptionUpgraded

**Produced By:** Billing Service  
**Consumed By:** All feature-based services  

## When It Is Emitted
When a tenant successfully upgrades to a higher plan.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "old_plan_id": "uuid",
  "new_plan_id": "uuid"
}
```