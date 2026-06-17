## ADDED Requirements

### Requirement: The service SHALL persist user-management and academic-config activity as an immutable audit trail

`iam-service` MUST consume `tenant_user.*`, `academic_year.*`, and `academic_term.*`
events from the `akademiq.events` exchange and write one row per event into an
append-only `audit_log` store recording at least `event_id`, `tenant_id`, `event_type`,
`target_kind`, `target_id`, `actor_user_id`, `occurred_at`, and the event `details`.
The application MUST NOT update or delete audit rows.

#### Scenario: A role change is recorded

- **WHEN** a `tenant_user.role_changed` event is published
- **THEN** an `audit_log` row is written with `target_kind = 'tenant_user'`, the target user as `target_id`, the acting admin, and the time it occurred

#### Scenario: A term status change is recorded

- **WHEN** an `academic_term.status_changed` event is published
- **THEN** an `audit_log` row is written with `target_kind = 'academic_term'`, the `term_id` as `target_id`, the actor, and the time it occurred

#### Scenario: An academic year status change is recorded

- **WHEN** an `academic_year.status_changed` event is published
- **THEN** an `audit_log` row is written with `target_kind = 'academic_year'`, the `academic_year_id` as `target_id`, the actor, and the time it occurred

#### Scenario: Audit rows are not mutable

- **WHEN** any subsequent operation runs
- **THEN** existing audit rows are neither updated nor deleted by the application

### Requirement: Event consumption SHALL be idempotent

The consumer MUST guard on the envelope `event_id` (e.g. a unique constraint) so that
at-least-once delivery and redelivery of the same event do not create duplicate audit
rows.

#### Scenario: Redelivered event does not duplicate

- **WHEN** the same `event_id` is delivered more than once
- **THEN** only a single `audit_log` row exists for that event

### Requirement: The audit trail SHALL capture the acting user

The `tenant_user.*` payloads MUST carry the `actor_user_id` of the admin who performed
the action (or the user themselves for self-service events such as activation), and the
consumer MUST record it. The `academic_year.status_changed` and
`academic_term.status_changed` payloads MUST also carry `actor_user_id` (additive,
backward-compatible). Additive payload fields MUST remain backward-compatible with
existing consumers. Where an actor is absent the consumer MUST record it as system
(null).

#### Scenario: Actor is recorded for an admin action

- **WHEN** an admin disables a user and the `tenant_user.disabled` event is consumed
- **THEN** the audit row's `actor_user_id` identifies the admin who disabled the account

#### Scenario: Actor is recorded for a term status change

- **WHEN** an admin transitions a term to `Active` and the `academic_term.status_changed` event is consumed
- **THEN** the audit row's `actor_user_id` identifies the admin who performed the transition

### Requirement: Admins SHALL read the audit trail with server-side search, filter, and pagination

The service MUST provide `GET /api/v1/iam/tenants/me/audit-log`, gated on the
`audit.view` permission, accepting `event_type`, `actor`, `target_kind`, `target_id`,
`from`/`to` date range, `page`, `page_size`, and `sort`, applied server-side, returning
the paginated envelope `{ "data": [...], "meta": { "page", "page_size", "total" } }`.
`tenant_id` MUST be resolved from the JWT and never from the client. `target_kind` MUST
be validated against the allow-list `('tenant_user','academic_year','academic_term')`.

#### Scenario: Filter the trail by event type and date

- **WHEN** an admin with `audit.view` requests `/tenants/me/audit-log?event_type=tenant_user.disabled&from=2026-06-01`
- **THEN** only disable events on or after that date for the caller's tenant are returned, paginated with totals

#### Scenario: Filter the trail by target

- **WHEN** an admin requests `/tenants/me/audit-log?target_kind=academic_term&target_id=<term_id>`
- **THEN** only audit rows for that specific term are returned

#### Scenario: Audit read requires permission

- **WHEN** a user without `audit.view` requests the audit log
- **THEN** the response is HTTP 403

#### Scenario: Tenant isolation

- **WHEN** an admin reads the audit log
- **THEN** only their own tenant's rows are returned, regardless of any client-supplied tenant value

### Requirement: The permission vocabulary SHALL include `audit.view`

The seeded permission set MUST include `audit.view`, mapped to the `tenant_admin`
built-in role, so audit read access can be granted independently of role-management
rights.

#### Scenario: tenant_admin can view audit

- **WHEN** a `tenant_admin` token is resolved
- **THEN** its effective permissions include `audit.view`
