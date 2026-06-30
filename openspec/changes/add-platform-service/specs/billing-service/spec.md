## ADDED Requirements

### Requirement: Internal operator endpoints (X-Service-Token)

billing-service SHALL expose internal endpoints, authenticated by the existing
`X-Service-Token` mechanism, that let platform-service drive cross-tenant
operations. These endpoints MUST NOT be reachable with a tenant access token and
MUST validate the service token before acting. billing-service remains the source
of truth for tenant status, the plan catalog, and subscriptions.

#### Scenario: Internal call requires service token

- **WHEN** an internal operator endpoint is called without a valid `X-Service-Token`
- **THEN** billing-service returns `401` with code `UNAUTHORIZED_SERVICE_CALL` and
  performs no mutation

#### Scenario: Internal call ignores client-supplied tenant scope

- **WHEN** platform-service forwards a command targeting `tenant_id`
- **THEN** billing-service acts on exactly that tenant from the path/body and does
  not require a tenant-scoped JWT

### Requirement: Tenant suspend and reactivate

billing-service SHALL support suspending and reactivating any tenant via its
internal operator endpoints, flipping the tenant status and emitting the
corresponding event through the transactional outbox.

#### Scenario: Suspend emits event

- **WHEN** the internal suspend endpoint is called for an active tenant
- **THEN** billing-service sets the tenant status to suspended and emits
  `tenant.suspended` via the outbox

#### Scenario: Reactivate emits event

- **WHEN** the internal reactivate endpoint is called for a suspended tenant
- **THEN** billing-service restores the tenant status and emits `tenant.reactivated`
  via the outbox

#### Scenario: Suspend is idempotent on already-suspended tenant

- **WHEN** the suspend endpoint is called for an already-suspended tenant
- **THEN** billing-service does not emit a duplicate state change and reports the
  no-op without error

### Requirement: Plan-catalog management

billing-service SHALL support creating, updating, and deactivating subscription
plans and their feature matrix via internal operator endpoints, emitting a
plan-catalog event on each change.

#### Scenario: Create plan

- **WHEN** the internal create-plan endpoint receives a valid plan with a unique
  `code`
- **THEN** billing-service persists it, exposes it in `GET /plans` when active, and
  emits the plan-created event

#### Scenario: Reject duplicate plan code

- **WHEN** the create-plan endpoint receives a `code` that already exists
- **THEN** billing-service returns `409` and creates no plan

### Requirement: Tenant subscription override

billing-service SHALL let an operator change a tenant's active subscription plan
via an internal endpoint, updating the subscription and emitting the
subscription-change event.

#### Scenario: Override tenant plan

- **WHEN** the internal subscription-override endpoint assigns a different existing
  plan to a tenant
- **THEN** billing-service updates the subscription and emits the
  subscription-change event via the outbox

#### Scenario: Reject unknown plan on override

- **WHEN** the override targets a plan that does not exist
- **THEN** billing-service returns `400` with code `UNKNOWN_PLAN` and changes
  nothing
