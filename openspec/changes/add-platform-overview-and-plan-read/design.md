## Context

platform-service is the cross-tenant control plane introduced by
`add-platform-service`. Its router (`services/platform-service/src/http.rs`) currently
exposes `/me`, `/tenants` (+ detail, usage, suspend, reactivate), `/users`, `/audit`,
plan mutations (`POST /plans`, `PUT|DELETE /plans/:id`), and the subscription
override. Reads come from local projections (`platform_tenant`,
`platform_subscription`, `platform_user`, `platform_tenant_stats`) fed by RabbitMQ
events; mutations are forwarded to billing-service or iam-service over an internal
`X-Service-Token` call via `forward_to_billing()`.

Three read paths the admin app depends on were never routed: an aggregate overview, a
plan-catalog listing, and an unfiltered user directory. The gap stayed hidden because
`apps/web-admin` bundles Nuxt server routes that mock the whole platform API on its
own origin. Behind the reverse proxy, `/api/v1/platform/*` is routed to the real
service, so the mock never answers and the screens are empty — the same build behaves
differently depending on the origin it is opened from.

Two data facts constrain the design, both verified against the running dev stack:

- `platform_tenant` has 2 rows; `platform_tenant_stats` has **0** rows, while
  `academic_ops` holds 195 students and 15 teachers for one of those tenants. The
  stats projection is fed by `student.enrolled` / `teacher.assigned`
  (`src/events.rs:21-22`), but RabbitMQ does not replay history and
  `scripts/bootstrap-projections.sh` never backfills this table.
- `platform_plan_catalog` also has 0 rows. Unlike the stats table it *does* have a
  writer — the consumer binds `plan-catalog.*` and upserts into it
  (`src/events.rs:111-121`, `repo.rs:307`) — but no plan-catalog event has been
  published in this environment, and the table has no reader anywhere in the service.

## Goals / Non-Goals

**Goals:**
- Route the three missing reads so the operator app works against the real backend.
- Keep reads inside the projection pattern: no synchronous cross-service call for
  data platform-service already projects, no cross-schema SQL in service code.
- Make the plan catalog read consistent with how plan mutations already work.
- Backfill `platform_tenant_stats` so the overview shows real numbers on existing
  environments.

**Non-Goals:**
- Removing the web-admin mock, or any `apps/web-admin` change — that is
  `remove-web-admin-mock-backend`, which depends on this change.
- Time-series or historical usage metrics; the overview is a point-in-time snapshot.
- Resolving the fate of the unused `platform_plan_catalog` table (see D4).
- Closing the 8 deferred verification tasks in `add-platform-service`.

## Decisions

### D1: Overview aggregates in SQL over the projections, not in the handler

`GET /overview` runs aggregate queries against `platform_tenant` (total count and
`GROUP BY status`) and `platform_tenant_stats` (`SUM(student_count)`,
`SUM(teacher_count)`), returning `{ tenants_by_status, totals: { tenants, students,
teachers } }` — the shape `apps/web-admin` already types in
`app/lib/api/types.ts` and renders in `app/pages/index.vue`.

- **Why:** matching the existing frontend contract avoids a second breaking change,
  and aggregation in SQL keeps the handler trivial at a table size of one row per
  tenant.
- **Alternative rejected:** compute counts live from `academic_ops` — violates the
  projection rule in `CONVENTIONS.md` and reintroduces cross-service coupling that
  `add-platform-service` explicitly designed out.
- **Trade-off:** the numbers are only as fresh as the projection and the backfill.

### D2: Plan read forwards to billing-service instead of reading a projection

`GET /plans` calls `forward_to_billing(GET, "/api/v1/billing/plans")`, reusing the
helper that already backs `create_plan`, `update_plan`, and `deactivate_plan`.

- **Why:** billing-service owns the catalog. Mutations already round-trip there, so
  serving reads from a local copy could show an operator a catalog that disagrees
  with the one their own edits just wrote. billing-service already exposes
  `GET /api/v1/billing/plans`.
- **Alternative rejected:** project the catalog into `platform_plan_catalog` and read
  locally. The consumer half already exists (`plan-catalog.*` → `upsert_plan_catalog`),
  so this is closer than it looks, but it still needs a backfill for pre-existing
  plans and it introduces a staleness window on the exact screen used to edit plans.
- **Trade-off:** an extra hop, and the screen depends on billing-service being up.
  Acceptable: the plan *editing* flow on the same screen already has that dependency.
- **Response adaptation:** billing's view is reshaped at the forwarding boundary to
  the platform plan contract the admin client already types — `features[].feature_code`
  becomes `features[].code`, and each plan carries an explicit `active: true`
  (billing's public listing returns active plans only). platform-service still owns no
  plan data; the adapter is presentation-only.

### D3: Reads are not audited

No `operator_audit` row is written for the three read endpoints.

- **Why:** consistent with existing reads (`GET /tenants`, `GET /users`,
  `GET /audit`). `operator_audit` is specified as a record of operator *mutations*;
  auditing list views would flood it and change the meaning of the table.

### D4: `platform_plan_catalog` is left in place, written but unread

The table stays. Its consumer keeps upserting on `plan-catalog.*` events; nothing
reads it, and this change does not backfill or drop it.

- **Why:** it is the natural landing spot if plan reads ever move to a projection (the
  rejected half of D2), and its writer already works — removing it would mean also
  removing a functioning consumer branch. Dropping it should be its own decision.
- **Trade-off:** a write-only table remains in the schema. Recorded here so it reads
  as a deliberate deferral rather than an oversight.

### D5: `email` becomes an optional filter rather than a new endpoint

`GET /users` handles both listing and lookup instead of adding `GET /users/list`.

- **Why:** one resource, one collection endpoint; the filter is the query parameter,
  which is the REST-conventional shape and what the frontend query hook already
  builds.
- **BREAKING:** callers relying on `VALIDATION_ERROR` for an empty `email` now get a
  page of results. The only consumer is `apps/web-admin`, so the blast radius is
  contained; recorded in the delta spec.
- **Guard:** page size is clamped, so an unfiltered call cannot dump the directory.

### D6: Stats backfill is a script concern, not a service concern

`platform_tenant_stats` is backfilled by a new `run_upsert` block in
`scripts/bootstrap-projections.sh`, counting `academic_ops.student` and
`academic_ops.teacher` grouped by `tenant_id`.

- **Why:** the script already exists for exactly this problem and already backfills
  the three sibling projections with the same `run_upsert` helper and
  `table_exists` guard. Event replay is not available, and a one-off migration would
  be wrong — this needs re-running whenever an environment predates the consumer.
- **Alternative rejected:** a startup reconciliation job in platform-service — adds a
  cross-schema read to service code, which D1 exists to avoid.

## Risks / Trade-offs

- **Backfill is a required manual step** → Overview reports zeros until
  `scripts/bootstrap-projections.sh` (or `make seed`) is re-run. Called out in
  proposal Impact and as an explicit task, and the endpoint is specified to succeed
  with zeros rather than error.
- **Overview totals drift from tenant reality** → the projection only advances on new
  events; a tenant whose data changed before the consumer existed stays stale until
  the next backfill. Same trade-off already accepted for the other three projections.
- **Plan screen now depends on billing-service uptime** (D2) → downstream errors are
  mapped through the existing `map_downstream_error()` path and surfaced, rather than
  showing a silently empty catalog.
- **Tenants with no `academic_ops` rows report zero** → correct, not a bug. One of the
  two dev tenants is in exactly this state, so expect an asymmetric dashboard.
- **Unfiltered user listing could be large** → page size clamp (D5); the directory is
  10 rows in dev but is unbounded in principle.

## Migration Plan

1. Land the service changes; no database migration is required — every table already
   exists from `V1__init.sql`.
2. Re-run `scripts/bootstrap-projections.sh` on each environment (or `make seed`) to
   populate `platform_tenant_stats`. Safe to re-run: the block is an idempotent
   upsert guarded by `table_exists`, matching the sibling blocks.
3. Verify with an operator token against the three endpoints before
   `remove-web-admin-mock-backend` proceeds.

Rollback: revert the service commit. The backfill leaves data behind but nothing
reads it after a revert, so no cleanup is needed.

## Open Questions

- Should `GET /overview` also return a plan-distribution breakdown
  (`tenants_by_plan`)? `platform_tenant.current_plan_code` makes it nearly free, but
  the current dashboard does not render it, so it is left out until the UI asks.
- Should the user directory expose sorting (by email, by membership count)? Deferred
  until the listing screen has a real dataset to sort.
