## MODIFIED Requirements

### Requirement: Billing service SHALL expose tenant, school profile, and plan endpoints under `/api/v1/billing`

The service MUST provide `POST /tenants/register`, `GET /plans`,
`GET /tenants/me`, school profile read/update for the current tenant, and
`PATCH /tenants/me/modules` under the path prefix `/api/v1/billing`. All endpoints
MUST follow the success and error envelopes from
`13_engineering_standards/03_api_conventions.md`.

The tenant school profile MUST include school identity, contact, address, and
branding fields needed by admin sekolah: school name, address, phone number,
email, website, optional NPSN, logo reference, school level, public/private status,
accreditation, village/subdistrict/city-or-regency/province, and postal code. The
profile MUST NOT own kepala sekolah/head-teacher linkage in this change.

#### Scenario: Plan catalog is publicly accessible

- **WHEN** an unauthenticated client GETs `/api/v1/billing/plans`
- **THEN** the response is HTTP 200 with `data: [{ plan_id, name, price_monthly, price_yearly, features: [{ feature_code, enabled }] }]` for every active plan

#### Scenario: Tenant profile is tenant-scoped

- **WHEN** a tenant admin GETs `/api/v1/billing/tenants/me` with a valid access token
- **THEN** the response is HTTP 200 with `data: { tenant_id, school_name, status, current_plan: { plan_id, name }, modules: [{ feature_code, enabled }] }` for the tenant resolved from the JWT, and never another tenant's data

#### Scenario: School profile is updated for current tenant

- **WHEN** a tenant admin updates valid school profile fields
- **THEN** the response is HTTP 200 with the updated school profile for the tenant resolved from the JWT

#### Scenario: School profile excludes head teacher linkage

- **WHEN** a tenant admin reads or updates the school profile
- **THEN** the response does not require or expose `head_teacher_id`
