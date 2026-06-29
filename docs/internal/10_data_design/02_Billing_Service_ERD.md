# AkademiQ ERD — Tenant & Subscription (Billing) Service

```mermaid
erDiagram
TENANT {
  uuid tenant_id PK
  string school_name
  string status
  string phone_number
  string email
  string website
  string npsn
  string logo_media_id
  string school_level
  string school_status
  string accreditation
  string address_line
  string village
  string subdistrict
  string city_regency
  string province
  string postal_code
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

MEDIA_ASSET {
  uuid media_id PK
  uuid tenant_id
  string owner_type
  uuid owner_id
  string file_url
  string content_type
  int size_bytes
  boolean is_active
  datetime uploaded_at
}

TENANT ||--o{ SUBSCRIPTION : has
PLAN ||--o{ SUBSCRIPTION : defines
SUBSCRIPTION ||--o{ INVOICE : generates
TENANT ||--o{ MEDIA_ASSET : "owns school logo history"
```

## 🧠 What This Database Owns
This service manages the commercial relationship between schools and the platform,
and owns the **school profile** (identity/contact/address/branding) for the tenant.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Tenant | A subscribing school, plus complete school profile identity/contact/address/branding |
| Plan | Subscription package |
| Subscription | Active plan contract |
| Invoice | Billing transaction record |
| MediaAsset | Logo upload history for the school (owner_type = `school`) |

## 🔗 Important Relationships
Tenants subscribe to plans via subscriptions, which generate invoices for payments.
The tenant row carries the complete school profile (school level, NPSN, accreditation,
address components, logo reference, public/private status). School profile does **not**
include kepala sekolah / head-teacher linkage in the current design — that coupling is
deferred until document/signature requirements need it.

## School profile ownership
The tenant represents the subscribing school, so Billing owns the school's
identity/contact/branding profile. Academic people data (students, teachers, family
profiles) is owned by Academic Ops. Media assets for school logos live here; media for
people photos lives in Academic Ops because the owner entities live there.