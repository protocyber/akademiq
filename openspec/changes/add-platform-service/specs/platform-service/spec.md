## ADDED Requirements

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
projection (`platform_user`) fed by `tenant-user-events`, so an operator can find a
user by email and see which tenants they belong to.

#### Scenario: Search user by email

- **WHEN** an operator searches `GET /api/v1/platform/users?email=...`
- **THEN** the service returns matching users with their tenant memberships from
  the projection

### Requirement: System usage monitoring

The platform-service SHALL aggregate per-tenant usage counts (e.g. student and
teacher totals) into a local projection (`platform_tenant_stats`) fed by
`student-enrolled` and `teacher-assigned` events, and expose them to operators.

#### Scenario: View usage stats

- **WHEN** an operator requests usage for a tenant
- **THEN** the service returns current student and teacher counts from the
  projection without calling other services synchronously

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
