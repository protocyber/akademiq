## Context

`iam-service` already publishes user-management activity as domain events through a
transactional outbox: `tenant_user.invited`, `tenant_user.activated`,
`tenant_user.role_changed`, and `tenant_user.disabled` land on the `akademiq.events`
topic exchange (see `docs/internal/11_integration_contracts/events/tenant-user-events.md`).
`academic-config-service` similarly publishes `academic_year.created`,
`academic_year.status_changed`, `academic_term.created`, and
`academic_term.status_changed` to the same exchange.
Today nothing persists these for audit; there is no consolidated record of who changed what.

This change adds an audit trail by **consuming** those events into an append-only
`audit_log` store and exposing a tenant-scoped read API + admin UI. It depends on the
permission layer introduced by `rbac-custom-roles-multirole` (for the new `audit.view`
permission and `require_permission` gating) and reuses the paginated-list + URL-sync
conventions established by `improve-user-management-list`.

The current event payloads are minimal: `role_changed` carries only `{tenant_id,
user_id, role}` and `disabled` carries only `{user_id}` — neither carries the **actor**
(who performed it). Capturing "who" is a core audit goal, so the event payloads (or the
consumer's context) must surface the acting admin.

## Goals / Non-Goals

**Goals:**
- An immutable, tenant-scoped, queryable record of user-management and academic-config activity.
- Reuse existing events — no new emission plumbing for the actions already published.
- Idempotent consumption so redelivery never duplicates rows.
- A read API consistent with the user-list change (same filter/paginate/URL-sync shape).
- Gate read access on a dedicated `audit.view` permission.

**Non-Goals:**
- Auditing billing and grading actions.
- Retention/archival/rotation policy for audit rows.
- Exporting the audit log (possible follow-up).
- A generic platform-wide audit framework — this is scoped to IAM user-management and academic-config lifecycle events.

## Decisions

### D1: Consume existing events rather than write audit rows inline

A new consumer binds to `akademiq.events` with routing key `tenant_user.*` and inserts
one `audit_log` row per event. The command handlers are not modified to write audit
rows directly.

- **Why:** the events already exist and already capture the actions; consuming them
  keeps audit decoupled from the command path and automatically covers bulk actions
  (which emit one event per user).
- **Alternative rejected:** write audit rows inside each command handler — duplicates
  logic, misses any future emitter, and couples audit to every write path.
- **Trade-off:** audit is eventually consistent (consumer lag), acceptable for a trail.

### D2: Idempotent on `event_id`

The envelope carries `event_id`. The consumer upserts/guards on `event_id` (unique
constraint) so at-least-once delivery and redelivery do not create duplicate rows.

- **Why:** RabbitMQ delivery is at-least-once; without this, retries double-count.

### D3: Capture the actor ("who")

`role_changed` and `disabled` payloads do not currently include the acting admin. This
change extends the relevant `tenant_user.*` payloads to include `actor_user_id` (the
authenticated admin who performed the action), and the consumer records it as
`audit_log.actor_user_id`. Where an action is self-service (e.g. `activated` by the
invitee), the actor is the user themselves.

The same pattern applies to academic-config events: `academic_year.status_changed` and
`academic_term.status_changed` payloads are extended with `actor_user_id` (additive,
backward-compatible). `academic_year.created` and `academic_term.created` already carry
`actor_user_id` if added at creation time; if absent the consumer records system.

- **Why:** "who did it" is a primary audit question; a trail without the actor is of
  limited value.
- **Alternative rejected:** infer actor later — not recoverable after the fact.
- **Cross-change note:** payload additions are backward-compatible (additive fields);
  the events docs are updated.

### D4: `audit_log` schema — append-only, tenant-scoped, discriminator-based

Columns: `audit_id` (PK), `event_id` (unique, idempotency), `tenant_id`, `event_type`,
`target_kind VARCHAR(32) NOT NULL` (CHECK in `('tenant_user','academic_year','academic_term')`),
`target_id UUID NOT NULL`, `actor_user_id` (nullable for system), `occurred_at`,
`details JSONB` (the full event payload for forensic detail), `recorded_at`.
Indexed on `(tenant_id, occurred_at)`, `(tenant_id, event_type)`, and
`(tenant_id, target_kind, target_id)` for point lookups ("what happened to this year/term?").
The application never `UPDATE`s or `DELETE`s rows.

- **Why `target_kind`/`target_id` over per-domain columns:** a single polymorphic column
  pair replaces three sparse nullable UUID columns (`target_user_id`, `target_year_id`,
  `target_term_id`). One index pattern covers all point lookups; adding a new event
  family only requires a new CHECK value, not a new column.
- **Why JSONB details:** keeps full payload without a column per event variant.

### D5: Read API mirrors the user-list conventions

`GET /api/v1/iam/tenants/me/audit-log` accepts `event_type`, `actor`, `target`,
`from`/`to` (date range), `page`, `page_size`, `sort`, applies them server-side, and
returns `{ data, meta:{page,page_size,total} }`. `tenant_id` is resolved from the JWT,
never the client. Gated on `require_permission(audit.view)`.

- **Why:** consistency with `improve-user-management-list` so the web table and
  URL-sync logic are reusable.

### D6: New permission `audit.view`

Added to the `rbac-custom-roles-multirole` permission seed and mapped to the
`tenant_admin` built-in role in `role_permission`. The read API and the
`settings/audit-log` route/UI gate on it.

- **Why:** audit visibility is a distinct sensitivity from `role.manage`; a dedicated
  code lets tenants grant read-only audit access (e.g. a compliance role) without role
  management rights.

### D7: Multi-source consumer

One consumer in `iam-service` binds to `tenant_user.*`, `academic_year.*`, and
`academic_term.*` on the `akademiq.events` exchange and writes to the single `audit_log`
table. `target_kind` is derived from the routing key prefix.

- **Why:** one table + one service that owns audit persistence; avoids fan-out to
  per-domain consumers and keeps the read API in one place.
- **Alternative rejected:** a separate consumer per service domain — duplicates the
  schema and the read API; iam-service would need to query external DBs.

### D8: Read API filter on `target_kind`

The read API accepts optional `target_kind` and `target_id` filters alongside the
existing `event_type`, `actor`, `from`/`to` filters. Both are server-side with
`target_kind` validated against the allow-list `('tenant_user','academic_year','academic_term')`.

- **Why:** allows the audit screen to scope to e.g. "all events on this term" without
  a full table scan.

## Risks / Trade-offs

- **Consumer lag / eventual consistency** → acceptable for an audit trail; the UI can
  note "near-real-time". Monitor consumer health via existing observability.
- **Event payloads lack actor today** → D3 extends payloads (additive, backward-compat)
  and updates the events contract doc; the consumer tolerates missing actor (system).
- **Unbounded growth** → out of scope here, but flagged: a retention policy is a likely
  follow-up. Indexes are chosen to keep reads fast as the table grows.
- **Permission seed lives in another change** → `audit.view` must be added to the rbac
  seed; coordinate so the migration includes it. If rbac is already archived, add a
  follow-up migration.
- **Duplicate rows on redelivery** → mitigated by D2 unique `event_id`.

## Migration Plan

1. Apply `rbac-custom-roles-multirole` (permission layer) — add `audit.view` to its
   seed + `role_permission` mapping (or a follow-up migration if already archived).
2. Backend: migration for `audit_log` with `target_kind`/`target_id` discriminator schema;
   wire the consumer for `tenant_user.*`, `academic_year.*`, `academic_term.*`; add the
   read query + handler gated on `audit.view`; extend `tenant_user.*` payloads with
   `actor_user_id` and extend `academic_year.status_changed` + `academic_term.status_changed`
   with `actor_user_id` (additive); update the events docs and IAM ERD.
3. Web: add `settings/audit-log` page + query hook reusing the paginated/URL-sync
   pattern; guard the route on `audit.view`.
4. Rollback: stop/remove the consumer and drop the read route; the `audit_log` table
   can be retained (no other system depends on it) or dropped. Event emission is
   unaffected.

## Open Questions

- Should the audit log be exportable (CSV) in v1, or deferred? Proposed: deferred.
- Date-range param format — propose ISO-8601 `from`/`to` query params.
- Display of `details` payload in the UI — propose a collapsible/expandable per-row
  detail rather than dumping JSON inline.
