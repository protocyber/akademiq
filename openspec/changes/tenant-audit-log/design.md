## Context

`iam-service` already publishes user-management activity as domain events through a
transactional outbox: `tenant_user.invited`, `tenant_user.activated`,
`tenant_user.role_changed`, and `tenant_user.disabled` land on the `akademiq.events`
topic exchange (see `docs/internal/11_integration_contracts/events/tenant-user-events.md`).
Today nothing persists these for audit; there is no record of who changed what.

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
- An immutable, tenant-scoped, queryable record of user-management activity.
- Reuse existing events — no new emission plumbing for the actions already published.
- Idempotent consumption so redelivery never duplicates rows.
- A read API consistent with the user-list change (same filter/paginate/URL-sync shape).
- Gate read access on a dedicated `audit.view` permission.

**Non-Goals:**
- Auditing actions outside user management (billing, academic config, grading).
- Retention/archival/rotation policy for audit rows.
- Exporting the audit log (possible follow-up).
- A generic platform-wide audit framework — this is scoped to IAM user-management.

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

- **Why:** "who did it" is a primary audit question; a trail without the actor is of
  limited value.
- **Alternative rejected:** infer actor later — not recoverable after the fact.
- **Cross-change note:** payload additions are backward-compatible (additive fields);
  the events doc is updated.

### D4: `audit_log` schema — append-only, tenant-scoped

Columns: `audit_id` (PK), `event_id` (unique, idempotency), `tenant_id`, `event_type`,
`actor_user_id` (nullable for system), `target_user_id` (nullable), `occurred_at`,
`details JSONB` (the event payload for forensic detail), `recorded_at`. Indexed on
`(tenant_id, occurred_at)` and `(tenant_id, event_type)` for the read filters. The
application never `UPDATE`s or `DELETE`s rows.

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
2. Backend: migration for `audit_log`; wire the `tenant_user.*` consumer; add the
   read query + handler gated on `audit.view`; extend `tenant_user.*` payloads with
   `actor_user_id` and update the events doc + IAM ERD.
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
