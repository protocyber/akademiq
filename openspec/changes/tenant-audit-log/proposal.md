## Why

AcademiQ has no record of *who did what* to user accounts or academic configuration.
An admin can invite, disable, change roles, and reset passwords — or activate and
close an academic year or semester — but there is no consolidated trail to answer
"who disabled this teacher?" or "when was this semester closed and by whom?" For a
multi-tenant school platform handling staff accounts and academic calendars, that is
both a security gap and an operational one.

The good news: both `iam-service` and `academic-config-service` already run
transactional **outboxes** and already publish their domain events to the
`akademiq.events` topic exchange. The audit log does not need new emission plumbing —
it can **consume** the events that already flow and persist them as an immutable,
tenant-scoped, queryable trail. This change adds that consumer, an `audit_log` store,
a read API, and an admin UI.

`academic-config-service` already maintains service-local `academic_year_status_transition`
and `academic_term_status_transition` tables as domain history. This change adds a
**consolidated cross-domain view** via the audit-log consumer, without replacing those
tables.

## What Changes

- **NEW `audit_log` table** (tenant-scoped, append-only) recording at minimum:
  `audit_id`, `tenant_id`, `event_type`, `actor_user_id`, `target_user_id`,
  `occurred_at`, and a `details` payload. Rows are never updated or deleted by the
  application (immutable trail).
- **NEW event consumer** binding to `akademiq.events` routing keys `tenant_user.*`,
  `academic_year.*`, and `academic_term.*` that writes one `audit_log` row per
  consumed event. Consumption MUST be idempotent on `event_id` so redelivery does
  not duplicate rows.
- **Discriminator schema** — `audit_log` uses `target_kind` (`tenant_user` |
  `academic_year` | `academic_term`) + generic `target_id` UUID so one table serves
  all three event families without sparse nullable columns per type.
- **NEW read API** `GET /api/v1/iam/tenants/me/audit-log` with the **same**
  server-side search/filter/pagination shape and paginated envelope as the user-list
  change (consistency): filter by `event_type`, `actor`, `target`, date range; paginate
  and sort; URL-syncable on the web.
- **NEW permission `audit.view`** added to the `rbac-custom-roles-multirole` permission
  seed and mapped to `tenant_admin`. The read API and UI are gated on it.
- **NEW web screen** `settings/audit-log`: a server-driven table (filters,
  pagination, URL-synced state) showing the activity trail, visible only to holders of
  `audit.view`.
- Bulk actions from `improve-user-management-list` already emit one `tenant_user.*`
  event per affected user, so bulk operations are recorded here for free — no extra
  coupling beyond consuming those events.

## Capabilities

### New Capabilities

- `tenant-audit-log`: the audit trail — `audit_log` store, idempotent consumer for
  `tenant_user.*`, `academic_year.*`, and `academic_term.*` events, and the
  `GET /tenants/me/audit-log` read API with search/filter/pagination gated on `audit.view`.
- `web-audit-log`: the `settings/audit-log` admin screen — a server-driven, URL-synced
  table of the activity trail, gated on `audit.view`.

### Modified Capabilities

- `iam-service`: adds the `audit.view` permission to the seeded permission vocabulary
  and maps it to the `tenant_admin` built-in role (the permission layer itself is
  introduced by `rbac-custom-roles-multirole`).

## Impact

- **Depends on `rbac-custom-roles-multirole`** (permission layer + seed) for the
  `audit.view` permission code and `require_permission` gating.
- **Soft dependency on `improve-user-management-list`** for the shared paginated-list +
  URL-sync conventions, and as the source of bulk-action events; not a hard build
  blocker since single-user events already exist.
- **Backend (`iam-service`):** new migration for `audit_log` with `target_kind`/`target_id`
  discriminator schema; new consumer wiring (RabbitMQ bindings on `akademiq.events` for
  `tenant_user.*`, `academic_year.*`, `academic_term.*`); new query + handler for the read
  API; add `audit.view` to the permission seed and `role_permission` mapping.
- **API contract / docs:** document the read endpoint; confirm the consumed event set in
  `docs/internal/11_integration_contracts/events/`; extend `academic_year.*` and
  `academic_term.*` event payloads with `actor_user_id` (additive, backward-compatible);
  note the data store in the IAM ERD (`docs/internal/10_data_design/`).
- **Web (`apps/web`):** new `settings/audit-log` page + query hook reusing the
  paginated/URL-sync params pattern; `target_kind` shown as localized label in the table.
- **Out of scope:** auditing billing and grading actions, log retention/archival policy,
  and exporting the audit log (can be a follow-up). The `academic_year_status_transition`
  and `academic_term_status_transition` tables in `academic-config-service` are retained
  as domain history; the audit log is the consolidated operational/forensic view.
