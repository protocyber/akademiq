# Billing Service API

## POST /subscriptions/upgrade
Request:
```json
{ "tenant_id": "uuid", "new_plan_id": "uuid" }
```

## GET /invoices/{tenant_id}
Returns list of invoices.