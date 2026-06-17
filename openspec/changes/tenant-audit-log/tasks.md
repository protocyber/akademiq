## 0. Prerequisite

- [ ] 0.1 Confirm `rbac-custom-roles-multirole` is applied (permission layer + seed) before gating on `audit.view`
- [ ] 0.2 Confirm bulk-action events from `improve-user-management-list` emit one `tenant_user.*` per user (source of bulk audit rows)

## 1. Backend — schema & permission (iam-service)

- [ ] 1.1 Add migration creating append-only `audit_log` (`audit_id`, `event_id` unique, `tenant_id`, `event_type`, `actor_user_id`, `target_user_id`, `occurred_at`, `details` JSONB, `recorded_at`)
- [ ] 1.2 Add indexes `(tenant_id, occurred_at)` and `(tenant_id, event_type)`
- [ ] 1.3 Add `audit.view` to the rbac permission seed and map it to `tenant_admin` in `role_permission` (or a follow-up migration if rbac is already archived)

## 2. Backend — actor in events (iam-service)

- [ ] 2.1 Extend `tenant_user.role_changed` and `tenant_user.disabled` payloads with `actor_user_id` (additive, backward-compatible)
- [ ] 2.2 Ensure `invited`/`activated` carry an actor (admin or self) consistently
- [ ] 2.3 Update `docs/internal/11_integration_contracts/events/tenant-user-events.md` for the added field

## 3. Backend — consumer (iam-service)

- [ ] 3.1 Wire a RabbitMQ consumer binding `akademiq.events` routing key `tenant_user.*`
- [ ] 3.2 Insert one `audit_log` row per event, idempotent on `event_id` (unique-constraint guard / upsert)
- [ ] 3.3 Tolerate missing actor (record as system) and malformed/unknown event variants without crashing the consumer

## 4. Backend — read API (iam-service)

- [ ] 4.1 Add query for `audit_log` with server-side `event_type`/`actor`/`target`/`from`/`to`/`page`/`page_size`/`sort`, parameterized, tenant resolved from JWT
- [ ] 4.2 Add `GET /tenants/me/audit-log` handler returning the `{ data, meta:{page,page_size,total} }` envelope, gated on `require_permission(audit.view)`
- [ ] 4.3 Clamp `page_size` and validate `sort` against an allow-list

## 5. Backend — tests & docs

- [ ] 5.1 Tests: consuming each `tenant_user.*` event writes the expected row with actor/target
- [ ] 5.2 Tests: idempotency on duplicate `event_id`
- [ ] 5.3 Tests: read API filter/paginate correctness, `audit.view` gate (403 without), tenant isolation
- [ ] 5.4 Update IAM ERD in `docs/internal/10_data_design/` for `audit_log`
- [ ] 5.5 Run backend `make test` for iam-service

## 6. Web — audit-log screen (apps/web)

- [ ] 6.1 Add query hook for `GET /tenants/me/audit-log` reusing the paginated/URL-sync params pattern from `improve-user-management-list`
- [ ] 6.2 Add `settings/audit-log` page: server-driven table with event-type/actor/target/date-range filters and pagination
- [ ] 6.3 Sync filters/page/sort to the browser URL and restore on load
- [ ] 6.4 Show actor, target, event type, time; expandable per-row detail for the `details` payload
- [ ] 6.5 Guard the route and hide the entry point unless `perms[]` includes `audit.view`

## 7. Web — tests & checks

- [ ] 7.1 Tests: route/entry-point hidden without `audit.view`; URL sync restores view
- [ ] 7.2 Run web lint/typecheck and `make test` for web

## 8. Backend — academic-config event payload extensions

- [ ] 8.1 Extend `academic_year.status_changed` payload with `actor_user_id` (additive) in `academic-config-service/src/commands.rs`. Update payload struct and outbox enqueue call.
- [ ] 8.2 Extend `academic_term.status_changed` payload with `actor_user_id` (additive). Same file, same pattern.
- [ ] 8.3 Extend `academic_year.created` and `academic_term.created` payloads with `actor_user_id` where available from JWT context; fall back to null (system).
- [ ] 8.4 Update event docs: `docs/internal/11_integration_contracts/events/academic-year-created.md`, `academic-year-status-changed.md`, `academic-term-created.md`, `academic-term-status-changed.md` — add `actor_user_id` field to payload table.

## 9. Backend — multi-source consumer & schema (iam-service)

- [ ] 9.1 Update `audit_log` schema in migration (task 1.1): replace `target_user_id` with `target_kind VARCHAR(32) NOT NULL CHECK (target_kind IN ('tenant_user','academic_year','academic_term'))` and `target_id UUID NOT NULL`; add index `(tenant_id, target_kind, target_id)`.
- [ ] 9.2 Wire consumer to also bind `academic_year.*` and `academic_term.*` routing keys on `akademiq.events` (alongside existing `tenant_user.*` binding in task 3.1).
- [ ] 9.3 Map each event family to its `target_kind`/`target_id`: `tenant_user.*` → kind `tenant_user`, target = `user_id`; `academic_year.*` → kind `academic_year`, target = `academic_year_id`; `academic_term.*` → kind `academic_term`, target = `term_id`.
- [ ] 9.4 Update read query (task 4.1) to accept optional `target_kind` and `target_id` filters (server-side, allow-listed against CHECK values).
- [ ] 9.5 Tests: each event family writes the expected row with correct `target_kind`/`target_id`; idempotency on `event_id`; missing `actor_user_id` recorded as null.

## 10. Web — audit UI accommodation

- [ ] 10.1 Update read query hook (task 6.1) to forward optional `target_kind` and `target_id` params.
- [ ] 10.2 Audit-log table (task 6.2): add `target_kind` column with localized labels (`tenant_user` → Pengguna, `academic_year` → Tahun Ajaran, `academic_term` → Semester); expandable row detail shows the `details` JSONB payload.
