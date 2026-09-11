## ADDED Requirements

### Requirement: Aggregate usage overview endpoint

The platform-service SHALL expose `GET /api/v1/platform/overview` returning
platform-wide aggregates for the operator dashboard: the total tenant count, a
breakdown of tenants by status, and the summed student and teacher counts. The
response MUST be computed only from the service's own projections
(`platform_tenant`, `platform_tenant_stats`) without synchronous calls to other
services. The endpoint MUST require a `typ:"platform"` token carrying the
`platform_admin` role.

#### Scenario: Operator requests the overview

- **WHEN** an operator requests `GET /api/v1/platform/overview`
- **THEN** the service returns the total tenant count, a `tenants_by_status` map, and
  aggregate student and teacher totals in the standard success envelope

#### Scenario: Counts reflect an empty stats projection

- **WHEN** `platform_tenant_stats` holds no row for a tenant
- **THEN** that tenant contributes zero to the student and teacher totals and the
  request still succeeds

#### Scenario: Non-operator is rejected

- **WHEN** a caller without the `platform_admin` role requests the overview
- **THEN** the service returns `403` and no aggregate data

### Requirement: Plan catalog read

The platform-service SHALL expose `GET /api/v1/platform/plans` returning the
subscription-plan catalog so an operator can review plans before assigning or editing
them. The catalog remains owned by billing-service: platform-service MUST forward the
read over the internal `X-Service-Token` channel rather than serving it from a local
projection, so the operator view cannot diverge from the billing source of truth.
Read requests MUST NOT be written to `operator_audit`.

#### Scenario: Operator lists plans

- **WHEN** an operator requests `GET /api/v1/platform/plans`
- **THEN** the service returns the plan catalog as forwarded by billing-service

#### Scenario: Downstream failure is surfaced

- **WHEN** billing-service is unreachable or returns an error for the catalog read
- **THEN** the operator receives the mapped downstream error and no partial catalog

#### Scenario: Reads are not audited

- **WHEN** an operator lists plans
- **THEN** no `operator_audit` row is written

## MODIFIED Requirements

### Requirement: Global user lookup

The platform-service SHALL expose a cross-tenant user directory built from a local
projection (`platform_user`) fed by `tenant-user-events`, so an operator can browse
the directory or find a user by email and see which tenants they belong to. The
`email` parameter is an optional filter: when omitted the service returns a paginated
listing of the directory, and when supplied it returns the matching users. Listing
MUST be paginated with a clamped page size so an unfiltered request cannot return the
whole directory in one response.

#### Scenario: Search user by email

- **WHEN** an operator searches `GET /api/v1/platform/users?email=...`
- **THEN** the service returns matching users with their tenant memberships from
  the projection

#### Scenario: Browse the directory without a search term

- **WHEN** an operator requests `GET /api/v1/platform/users` with no `email`
- **THEN** the service returns a paginated page of the user directory with tenant
  memberships, instead of a validation error

#### Scenario: Fetch one user by id

- **WHEN** an operator requests `GET /api/v1/platform/users/{user_id}` for a user
  present in the projection
- **THEN** the service returns that user with their tenant memberships, and an
  unknown id returns `404`

#### Scenario: Page size is clamped

- **WHEN** an operator requests a page size above the allowed maximum
- **THEN** the service clamps it to the maximum and returns that many rows at most
