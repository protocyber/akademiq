# AcademiQ ERD — Tenant & Subscription (Billing) Service

```mermaid
erDiagram
TENANT {
  uuid tenant_id PK
  string school_name
  string status
}

PLAN {
  uuid plan_id PK
  string name
  float price_monthly
  float price_yearly
}

SUBSCRIPTION {
  uuid subscription_id PK
  uuid tenant_id FK
  uuid plan_id FK
  date start_date
  date end_date
  string status
}

INVOICE {
  uuid invoice_id PK
  uuid subscription_id FK
  float amount
  string status
  datetime issued_at
}

TENANT ||--o{ SUBSCRIPTION : has
PLAN ||--o{ SUBSCRIPTION : defines
SUBSCRIPTION ||--o{ INVOICE : generates
```

## 🧠 What This Database Owns
This service manages the commercial relationship between schools and the platform.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Tenant | A subscribing school |
| Plan | Subscription package |
| Subscription | Active plan contract |
| Invoice | Billing transaction record |

## 🔗 Important Relationships
Tenants subscribe to plans via subscriptions, which generate invoices for payments.