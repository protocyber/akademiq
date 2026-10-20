# tenant.school_profile_updated

Event published by `billing_service` whenever a tenant's school profile changes:
every successful `PATCH /api/v1/billing/tenants/me/school-profile`, every logo
upload (`POST .../school-profile/logo`) and every logo delete
(`DELETE .../school-profile/logo`). The outbox row is written in the same
transaction as the tenant update, so a committed change always has its event
and a rejected request (validation error, forbidden) publishes nothing.

The payload always carries the **full current state** of the fields below, not
only the fields that changed. Consumers replace their copy wholesale.

## Envelope

```json
{
  "event_id": "uuid",
  "event_type": "tenant.school_profile_updated",
  "occurred_at": "RFC3339 timestamp",
  "payload": { /* see below */ }
}
```

## Payload

```json
{
  "tenant_id": "uuid",
  "school_name": "SMP Negeri 1 Surabaya",
  "npsn": "20531234",
  "principal_name": "Dra. Siti Rahayu, M.Pd.",
  "principal_nip": "196805121993032004",
  "address_line": "Jl. Pemuda No. 1",
  "village": "Embong Kaliasin",
  "subdistrict": "Genteng",
  "city_regency": "Kota Surabaya",
  "province": "Jawa Timur",
  "postal_code": "60271",
  "phone_number": "031-123456",
  "email": "info@smpn1sby.sch.id",
  "logo_url": "/api/v1/billing/media/school/{media_id}",
  "updated_at": "RFC3339 timestamp"
}
```

| Field | Type | Notes |
|---|---|---|
| `tenant_id` | uuid | Tenant whose profile changed. |
| `school_name` | string | Always present. |
| `npsn`, `principal_name`, `principal_nip`, `address_line`, `village`, `subdistrict`, `city_regency`, `province`, `postal_code`, `phone_number`, `email` | string \| null | `null` when unset. |
| `logo_url` | string \| null | Resolved public serve path (`/api/v1/billing/media/school/{media_id}`, prefixed by `MEDIA_PUBLIC_BASE_URL` when set), never the stored `media://` URI. `null` when no logo. |
| `updated_at` | timestamp | `tenant.updated_at` after the change. **Ordering key** for consumers. |

`website`, `school_level`, `school_status` and `accreditation` are not carried;
no consumer needs them.

## Routing

- Exchange: `akademiq.events` (topic, durable)
- Routing key: `tenant.school_profile_updated`

## Consumers

- `academic_ops_service` — upserts `known_school_profile` (one row per tenant).
  A row is replaced only when the incoming `updated_at` is **newer** than the
  stored one; a late, older event is ignored. Used for the letterhead and the
  principal snapshot of promotion letters (SK Kenaikan Kelas, Surat Keterangan
  Lulus).

## Bootstrap

Tenants that existed before this event was introduced are seeded by
`apps/backend/scripts/bootstrap-projections.sh` (step `known_school_profile`),
which copies the same fields from `billing.tenant` and converts the stored
`media://{owner}/{media_id}.{ext}` logo into the serve path above.
