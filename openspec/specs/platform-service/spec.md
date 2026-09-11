# platform-service Specification

## Purpose
TBD - created by archiving change add-platform-service. Update Purpose after archive.

## Requirements
### Requirement: Cross-tenant tenant directory

The platform-service SHALL expose a read-only directory of every tenant in the
system, sourced from a local projection (`platform_tenant`) populated by consuming
`tenant.registered` and tenant-status events. It MUST NOT query other services'
databases directly.

#### Scenario: List all tenants

- **WHEN** an authenticated operator requests `GET /api/v1/platform/tenants`
- **THEN** the service returns a paginated list of all tenants with `tenant_id`,
  `school_name`, `status`, `current_plan_code`, and `registered_at` from the
  local projection

#### Scenario: View one tenant detail

- **WHEN** an operator requests `GET /api/v1/platform/tenants/{tenant_id}`
- **THEN** the service returns that tenant's profile, current subscription, module
  entitlements, and usage stats from local projections

#### Scenario: Unknown tenant

- **WHEN** an operator requests a `tenant_id` not present in the projection
- **THEN** the service returns `404` with code `NOT_FOUND`

### Requirement: Tenant lifecycle commands

The platform-service SHALL let an operator suspend and reactivate any tenant. The
service MUST forward the mutation to billing-service over an internal
`X-Service-Token` call rather than writing tenant status in `platform_db`;
billing-service remains the source of truth and emits the resulting event.

#### Scenario: Suspend a tenant

- **WHEN** an operator calls `POST /api/v1/platform/tenants/{tenant_id}/suspend`
  with a reason
- **THEN** platform-service calls billing-service's internal suspend endpoint,
  billing-service flips the tenant status and emits `tenant.suspended`, and the
  operator action is written to `operator_audit`

#### Scenario: Reactivate a tenant

- **WHEN** an operator calls `POST /api/v1/platform/tenants/{tenant_id}/reactivate`
- **THEN** billing-service restores the tenant status, emits `tenant.reactivated`,
  and the action is audited

#### Scenario: Downstream forwarding fails

- **WHEN** the internal call to billing-service fails
- **THEN** platform-service returns a non-2xx error, does not write a success
  audit row, and does not report the tenant as changed

### Requirement: Subscription-plan catalog management

The platform-service SHALL let an operator create, update, and deactivate
subscription plans and their feature matrix. The catalog remains owned by
billing-service; platform-service forwards the mutation over `X-Service-Token`.

#### Scenario: Create a plan

- **WHEN** an operator submits a valid new plan with code, prices, and feature
  flags
- **THEN** billing-service persists the plan, emits the plan-created event, and the
  action is audited

#### Scenario: Reject duplicate plan code

- **WHEN** an operator submits a plan whose `code` already exists
- **THEN** the service returns a `409` conflict and no plan is created

### Requirement: Tenant subscription override

The platform-service SHALL let an operator change a specific tenant's subscription
plan, forwarding the change to billing-service.

#### Scenario: Change a tenant plan

- **WHEN** an operator assigns a different plan to a tenant
- **THEN** billing-service updates the subscription, emits the subscription-change
  event, and the action is audited

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

### Requirement: System usage monitoring

The platform-service SHALL aggregate per-tenant usage counts (e.g. student and
teacher totals) into a local projection (`platform_tenant_stats`) fed by
`student-enrolled` and `teacher-assigned` events, and expose them to operators.

#### Scenario: View usage stats

- **WHEN** an operator requests usage for a tenant
- **THEN** the service returns current student and teacher counts from the
  projection without calling other services synchronously

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

### Requirement: Operator audit log

The platform-service SHALL record every operator mutation (actor, action, target
resource, timestamp, outcome) in `platform_db` (`operator_audit`), separate from
any in-tenant audit log.

#### Scenario: Mutation is audited

- **WHEN** any operator command (suspend, reactivate, plan CRUD, subscription
  override) succeeds
- **THEN** an `operator_audit` row is written with the operator's `sub`, the action
  type, and the target identifier

#### Scenario: Audit log is read-only to operators

- **WHEN** an operator requests `GET /api/v1/platform/audit`
- **THEN** the service returns audit entries; there is no API to mutate or delete
  them

### Requirement: Health endpoint

The platform-service SHALL expose `GET /api/v1/platform/healthz` returning the
standard success envelope after a database connectivity check.

#### Scenario: Health check

- **WHEN** `GET /api/v1/platform/healthz` is called and the database responds
- **THEN** the service returns `200` with the standard success envelope

### Requirement: Standard envelopes and conventions

The platform-service SHALL follow the repo-wide API conventions: success envelope
`{ "data": ..., "meta": ... }`, error envelope
`{ "error": { "code": ..., "message": ... } }`, and `VALIDATION_ERROR` with a
`fields` map for per-field validation failures.

#### Scenario: Validation failure shape

- **WHEN** an operator submits an invalid plan payload
- **THEN** the service returns `400` with code `VALIDATION_ERROR` and a `fields`
  map keyed by request-body field name
