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
