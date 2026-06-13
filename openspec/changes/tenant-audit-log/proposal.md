## Why

AcademiQ has no record of *who did what* to user accounts. An admin can invite,
disable, change roles, and reset passwords, but there is no trail to answer "who
disabled this teacher?" or "when was this user's role changed and by whom?" For a
multi-tenant school platform handling staff and student accounts, that is both a
security gap and an operational one.

The good news: `iam-service` already runs a transactional **outbox** and already
publishes `tenant_user.invited / activated / role_changed / disabled` to the
`akademiq.events` topic exchange. The audit log does not need new emission plumbing —
it can **consume** the events that already flow and persist them as an immutable,
tenant-scoped, queryable trail. This change adds that consumer, an `audit_log` store,
a read API, and an admin UI.

## What Changes

- **NEW `audit_log` table** (tenant-scoped, append-only) recording at minimum:
  `audit_id`, `tenant_id`, `event_type`, `actor_user_id`, `target_user_id`,
  `occurred_at`, and a `details` payload. Rows are never updated or deleted by the
  application (immutable trail).
- **NEW event consumer** binding to `akademiq.events` routing keys `tenant_user.*`
  that writes one `audit_log` row per consumed event. Consumption MUST be idempotent
  on `event_id` so redelivery does not duplicate rows.
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

- `tenant-audit-log`: the IAM-side audit trail — `audit_log` store, the `tenant_user.*`
  event consumer (idempotent), and the `GET /tenants/me/audit-log` read API with
  search/filter/pagination gated on `audit.view`.
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
- **Backend (`iam-service`):** new migration for `audit_log`; new consumer wiring
  (RabbitMQ binding on `akademiq.events` for `tenant_user.*`); new query + handler for
  the read API; add `audit.view` to the permission seed and `role_permission` mapping.
- **API contract / docs:** document the read endpoint and confirm the consumed event
  set in `docs/internal/11_integration_contracts/events/tenant-user-events.md`; note
  the data store in the IAM ERD (`docs/internal/10_data_design/`).
- **Web (`apps/web`):** new `settings/audit-log` page + query hook reusing the
  paginated/URL-sync params pattern.
- **Out of scope:** auditing non-user-management actions (billing, academic config,
  grading), log retention/archival policy, and exporting the audit log (can be a
  follow-up).
