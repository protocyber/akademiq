## Why

The operator admin app (`apps/web-admin`) renders empty screens for Overview, Plans,
and Users against the live backend. Verified against a running stack with a real
operator token:

| Screen   | Request                        | Result                                    |
|----------|--------------------------------|-------------------------------------------|
| Tenants  | `GET /api/v1/platform/tenants` | `200`, 2 rows — works                     |
| Overview | `GET /api/v1/platform/overview`| **`404`** — route does not exist          |
| Plans    | `GET /api/v1/platform/plans`   | **`405`** — only `POST`/`PUT`/`DELETE`    |
| Users    | `GET /api/v1/platform/users`   | `400` unless `email` is supplied          |

`add-platform-service` already requires "System usage monitoring" to expose per-tenant
counts to operators, but no read endpoint was ever routed — the gap went unnoticed
because `apps/web-admin` shipped a bundled mock backend that answered these three
routes with fabricated data (including hard-coded `students: 960, teachers: 72`). The
mock only applies on the app's own origin, so the same build shows data on
`localhost:3010` and empty screens behind the reverse proxy. The read side of the
platform plane has to exist before that mock can be removed
(`remove-web-admin-mock-backend`).

A second gap sits underneath: `platform_tenant_stats` is empty (0 rows) even though
the source data exists (195 students, 15 teachers for one tenant). RabbitMQ does not
replay past events, and `scripts/bootstrap-projections.sh` backfills
`platform_tenant`, `platform_subscription`, and `platform_user` but never
`platform_tenant_stats`. Without a backfill the new endpoint would correctly return
zeros.

## What Changes

- **NEW `GET /api/v1/platform/overview`** returning tenant totals, a
  `tenants_by_status` breakdown, and aggregate student/teacher counts, read purely
  from the `platform_tenant` and `platform_tenant_stats` projections. Operator-gated
  like every other platform route.
- **NEW `GET /api/v1/platform/plans`** returning the subscription-plan catalog.
  platform-service does **not** own plan data: the request is forwarded to
  billing-service over `X-Service-Token`, matching how plan create/update/deactivate
  already forward via `forward_to_billing()`. Read operations are not audited,
  consistent with the existing `GET /tenants` behaviour.
- **MODIFIED `GET /api/v1/platform/users`** — `email` becomes an optional filter
  instead of a required parameter. With no `email`, the endpoint returns a paginated
  directory of users from the `platform_user` projection; with `email`, it keeps
  today's matching behaviour. **BREAKING** for the previous contract, which returned
  `VALIDATION_ERROR` when `email` was empty. The only consumer is `apps/web-admin`.
- **NEW `GET /api/v1/platform/users/{user_id}`** — the admin app already links each
  directory row to a detail view, but the service never routed it (the mock answered
  instead). Returns the projected user with tenant memberships; unknown ids return
  `404`.
- **NEW backfill for `platform_tenant_stats`** in `scripts/bootstrap-projections.sh`,
  following the existing `run_upsert` pattern, sourced from `academic_ops.student` and
  `academic_ops.teacher` grouped by tenant. This is a read-model backfill only — no
  cross-schema query is introduced into service code.
- **Contract documentation** for all three endpoints in
  `docs/internal/11_integration_contracts/apis/platform-service-api.md`.

Not included: `platform_plan_catalog` stays in place and stays empty. Its consumer
(`plan-catalog.*`) keeps writing to it, but since plan reads are proxied to
billing-service the table has no reader; dropping it belongs in a separate change
(see design.md D4).

## Capabilities

### New Capabilities

<!-- None. This change completes the read surface of an existing capability. -->

### Modified Capabilities

- `platform-service`: adds an explicit requirement for an aggregate usage/overview
  read endpoint (today's "System usage monitoring" requirement mandates the
  projection and per-tenant exposure but never a routed aggregate read), adds a
  plan-catalog read requirement to the existing catalog-management requirement (which
  covers mutations only), and relaxes "Global user lookup" so the directory is
  listable without a search term.

## Impact

- **`apps/backend/services/platform-service`** — two new handlers plus one modified
  handler in `src/http.rs`; new repository methods in `src/repo.rs` for the aggregate
  counts and the paginated user listing. No migration: `platform_tenant`,
  `platform_tenant_stats`, and `platform_user` already exist from `V1__init.sql`.
- **`apps/backend/scripts/bootstrap-projections.sh`** — one new `run_upsert` block.
  Operators must re-run the script (or `make seed`) for existing environments;
  otherwise Overview reports zero students and teachers.
- **API contract** — `platform-service-api.md` gains `GET /overview` and
  `GET /plans`, and the `GET /users` entry changes from required to optional `email`.
- **`apps/web-admin`** — unblocked, but not modified here. The UI changes and mock
  removal live in `remove-web-admin-mock-backend`, which depends on this change
  landing first.
- **Out of scope:** the 8 open tasks in `add-platform-service` (integration tests and
  manual smoke verification that were deferred, tasks 2.8, 2.9, 3.7, 5.7, 7.7,
  9.1-9.3). They are unrelated to these read paths and are recorded here only so they
  are not lost. Tenants with no `academic_ops` data legitimately report zero after the
  backfill.
