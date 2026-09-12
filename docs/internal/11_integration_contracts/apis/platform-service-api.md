# Platform Service API

Base path: `/api/v1/platform`. All protected endpoints require
`Authorization: Bearer <platform_token>` where the JWT has `typ:"platform"` and
`platform_admin`. Tenant `access`, `identity`, and `refresh` tokens are rejected.

All endpoints follow the standard envelopes:

- Success: `{ "data": {...}, "meta": {...} }`
- Error: `{ "error": { "code": "...", "message": "...", "fields?": {...} } }`

## Health

### `GET /healthz`

Performs `SELECT 1` against `platform_db`. This is platform-service's **own**
liveness probe and is the only unauthenticated endpoint here. It is also served
at the bare path `/healthz` so fleet-wide probes can reach every service at the
same address.

Success: `{ "data": { "status": "ok" }, "meta": {} }`

## Service health

### `GET /health`

Aggregate liveness board for the backend fleet. Probes each service's `/healthz`
live over HTTP — this is the one platform endpoint that makes synchronous
cross-service calls by design, because "is it answering *now*" is the entire
question and a projection could only report what a service last told us.

> **Naming hazard.** `/api/v1/platform/healthz` (above) is platform-service's own
> liveness probe. `/api/v1/platform/health` (this endpoint) is the aggregate
> board. The two differ by one character and mean completely different things.

Six services are probed: `iam`, `billing`, `academic-config`, `academic-ops`,
`grading`, and `platform` itself. Each target's base URL is overridable via
`<NAME>_BASE_URL` (dashes folded to underscores, e.g.
`ACADEMIC_CONFIG_BASE_URL`); `docker-compose.yml` sets all six.

The probes are awaited together, so the handler's worst case is **one** 2-second
timeout rather than one per target. A `down` service never fails the request —
reporting the outage is the endpoint's whole purpose.

```json
{
  "data": {
    "services": [
      { "name": "iam",             "status": "up",   "latency_ms": 4 },
      { "name": "billing",         "status": "up",   "latency_ms": 7 },
      { "name": "academic-config", "status": "down", "latency_ms": null }
    ]
  },
  "meta": {}
}
```

| Field        | Type              | Notes |
|--------------|-------------------|-------|
| `name`       | string            | Service name as configured, not the container name. |
| `status`     | `"up"` \| `"down"`| `up` only when the probe returned a 2xx within the timeout. |
| `latency_ms` | number \| null    | Round-trip milliseconds for a **successful** probe only. |

`latency_ms: null` does **not** mean "unreachable". It is null for every
non-`up` outcome, which includes a service that answered promptly with a 500 or
503. The wire response deliberately carries no failure detail (that is an
internal detail per `CONVENTIONS.md` §2); each failure is logged server-side with
its cause, so a timeout, a refused connection, and a 503 are distinguishable in
the logs but not in the response.

## Operator identity

### `GET /me`

Returns the authenticated platform operator.

```json
{
  "data": { "user_id": "uuid", "roles": ["platform_admin"] },
  "meta": {}
}
```

## Usage overview

### `GET /overview`

Platform-wide aggregates for the operator dashboard, computed only from local
projections (`platform_tenant`, `platform_tenant_stats`) with no synchronous
calls to other services.

```json
{
  "data": {
    "tenants_by_status": { "active": 2 },
    "totals": { "tenants": 2, "students": 195, "teachers": 15 }
  },
  "meta": {}
}
```

Tenants with no `platform_tenant_stats` row contribute zero to the student and
teacher totals. The endpoint is a point-in-time snapshot: freshness follows the
projection (events + `scripts/bootstrap-projections.sh` backfill).

## Tenant directory

### `GET /tenants?page=&page_size=`

Returns the local cross-tenant projection from `platform_tenant`.

```json
{
  "data": [
    {
      "tenant_id": "uuid",
      "school_name": "string",
      "status": "active|suspended|cancelled",
      "current_plan_code": "premium",
      "registered_at": "timestamp"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

### `GET /tenants/{tenant_id}`

Returns tenant profile plus usage stats from local projections. Unknown tenants
return `404 NOT_FOUND`.

### `GET /tenants/{tenant_id}/usage`

Returns `student_count` and `teacher_count` from `platform_tenant_stats`.

## Subscription detail

### `GET /tenants/{tenant_id}/subscription`

Returns the tenant's subscription as projected locally into
`platform_subscription`. No call to billing is made.

```json
{
  "data": {
    "tenant_id": "uuid",
    "plan_code": "premium",
    "status": "active",
    "modules": { "grading": true, "attendance": false },
    "started_at": "timestamp|null",
    "ends_at": "timestamp|null"
  },
  "meta": {}
}
```

Contract notes:

- **`data` is `null` when no projection row exists** — not `404`, not an error.
  A tenant that exists but has never had a subscription event projected is a
  normal state for this endpoint, and the caller renders "no subscription"
  rather than an error.
- `started_at` and `ends_at` are projected from `subscription.activated`'s
  `start_date` / `end_date`. `subscription.plan_changed` carries neither, and a
  plan change deliberately preserves the dates an activation already projected.
- `started_at` is nullable: the row can be created by a module toggle before any
  subscription event arrives (see below).
- **`ends_at` is always `null` today, and that is not a projection bug.** Billing
  sets `end_date = None` at both subscription creation sites and no code path
  ever updates it, so the event never carries one. Anything downstream that keys
  off `ends_at` — notably the console's "<30 days to expiry" warning — is
  therefore unreachable until subscription lifecycle work (renewal, expiry,
  cancellation) exists. That UI is kept deliberately: it is correct code waiting
  on a producer, not dead code. Do not read a null `ends_at` as "the projection
  dropped it".
- **`payment_method` is intentionally not exposed.** Billing owns it and does not
  project it, so there is no value platform-service could return. Do not add it
  to the client contract without first projecting it.
- A tenant whose projection row was created by `tenant.module_toggled` before any
  subscription event reads back `plan_code: "unknown"` and `status: "unknown"` —
  the column defaults. A later subscription event overwrites both.

## Module entitlements

### `GET /tenants/{tenant_id}/modules`

Operator view of a tenant's modules: what is switched on now, and what the
tenant's plan allows.

```json
{
  "data": {
    "modules": [
      { "code": "academic_config", "enabled": true,  "entitled": true  },
      { "code": "attendance",      "enabled": false, "entitled": true  },
      { "code": "grading",         "enabled": true,  "entitled": false }
    ]
  },
  "meta": {}
}
```

| Field      | Source | Meaning |
|------------|--------|---------|
| `code`     | billing's `feature_code` | Feature code from `features.toml`. |
| `enabled`  | billing's `enabled`      | Is the module switched on right now. |
| `entitled` | billing's `plan_entitled` | Does the tenant's plan include the feature. |

**Both fields are read live from billing**, via
`GET /api/v1/billing/internal/tenants/{tenant_id}/modules` over
`X-Service-Token`. Neither is derived from the local projection.

That is the whole point of this endpoint, and it is a correction of an earlier
design. `platform_subscription.modules` is written *only* by
`tenant.module_toggled` — i.e. only for features somebody has explicitly
toggled, since no subscription event carries a modules map. Reading `enabled`
from it forced "key absent" to mean **off**, while billing resolves an absent
override to the **plan default**. For a premium tenant nobody had ever toggled,
billing ran `grading` and this endpoint reported it off: the console
contradicting the system it monitors, on its only write surface.

Billing computes the answer in one place (`queries::resolve_modules`), which
also serves the tenant-facing `GET /billing/tenants/me`, so the operator view
and the tenant view cannot drift.

The list is the **union** of the tenant's plan features and its explicit
overrides, sorted by `code`. That is deliberate: a module can be
`enabled: true, entitled: false` — drift, typically a feature switched on under
a plan the tenant has since left — and the union is what makes that visible
instead of silently dropping it. `entitled: true, enabled: false` (available but
off) is equally representable.

**If billing is unreachable, this endpoint fails rather than degrading.**
Returning an all-off board would be indistinguishable from a tenant that
genuinely runs nothing, and would invite an operator to "fix" a healthy system.
Failing loudly is also what the sibling `GET /plans` already does. A 200 whose
body cannot be parsed is treated the same way: an empty list would assert
something about the tenant that we have no basis for.

A tenant billing knows nothing about returns an empty `modules` array with HTTP
200, matching the sibling `GET /subscription`'s `data: null` rather than `404`.

The `tenant.module_toggled` event and its projection remain — they still serve
`GET /tenants/{tenant_id}/subscription` above.

### `PUT /tenants/{tenant_id}/modules`

Toggles one module. Forwarded to billing's
`PATCH /api/v1/billing/internal/tenants/{tenant_id}/modules` over
`X-Service-Token`.

Request:

```json
{ "feature_code": "grading", "enabled": false }
```

Success (200): `{ "data": { "ok": true }, "meta": {} }`

Errors:

| Code                    | HTTP | Cause |
|-------------------------|------|-------|
| `FEATURE_NOT_AVAILABLE` | 403  | Billing: the tenant's plan does not entitle `feature_code`. |
| `SUBSCRIPTION_EXPIRED`  | 403  | Billing: the tenant has no subscription, or it is not `active`. |
| `DOWNSTREAM_FORBIDDEN`  | 403  | Any *other* downstream 403. |

**Billing is the sole authority.** platform-service performs no entitlement check
of its own; it forwards the request and reports billing's verdict.
`FEATURE_NOT_AVAILABLE` and `SUBSCRIPTION_EXPIRED` propagate **unchanged** — they
are part of the platform contract so the UI can explain *why* a toggle was
refused. This is an explicit allowlist of exactly those two codes; every other
downstream 403 is an internal detail and flattens to `DOWNSTREAM_FORBIDDEN`.

Note the ordering inside billing: the entitlement gate runs **before** billing
inspects the requested value. An unentitled module therefore cannot be switched
*off* either — `{"enabled": false}` on an unentitled feature is still
`FEATURE_NOT_AVAILABLE`. This is why the `GET` above reports drift instead of
offering to clean it up.

A rejected toggle writes nothing anywhere: no `tenant_module` row in billing, no
event, and no `operator_audit` row here. The audit row is written only after a
2xx from billing, and records `tenant.module_toggle` with the `feature_code` and
`enabled` that were requested.

On success billing emits `tenant.module_toggled`, which platform-service consumes
back into `platform_subscription.modules`, feeding `GET /subscription`. The `GET
/modules` endpoint above reads billing directly, so it reflects the new value
immediately rather than waiting on the projection.

## Registration troubleshooting

### `GET /registrations?state=&page=&page_size=`

Operator listing of registration saga rows, newest first. Proxied live from
billing's `GET /api/v1/billing/internal/registrations` over `X-Service-Token`,
in the same pattern as `GET /plans`. **platform-service keeps no local copy.**

A projection would be actively harmful here: these rows exist because onboarding
got stuck, an operator acts on them precisely while they are still stuck, and a
lagging projection would show registrations that have since completed or hide
ones that just failed.

```json
{
  "data": [
    {
      "registration_id": "uuid",
      "email": "string",
      "iam_user_id": "uuid|null",
      "tenant_id": "uuid|null",
      "state": "user_created|tenant_created|completed|failed",
      "attempted_at": "timestamp"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

`iam_user_id` and `tenant_id` are exposed so an operator can trace the orphaned
resources a half-finished saga left behind.

`state` is optional; absent or blank means "every state". When supplied it is
validated against exactly four values — `user_created`, `tenant_created`,
`completed`, `failed` — mirroring billing's `pending_registration_state_chk`
constraint. Anything else returns `400 VALIDATION_ERROR` with the `state` field
key. This is a security boundary, not a convenience check: the value is
interpolated into the forwarded path, so an arbitrary string could otherwise
smuggle extra query parameters into billing's internal API.

**Operational reality — this is a live view, not a history.** Two caveats an
operator needs:

- Only `user_created` and `completed` are ever written today. `tenant_created`
  and `failed` are accepted by the constraint and by this filter, but no code
  path produces them, so filtering on either returns an empty list. They are kept
  in the allowlist because the constraint allows them.
- Billing's janitor runs every 60 seconds and **deletes** any non-`completed` row
  older than ~5 minutes, after compensating (deleting the orphaned IAM user and
  tenant). `completed` rows are retained indefinitely. So a stalled registration
  is visible for about five minutes and then disappears — absence from this list
  does not mean it never happened.

Reads are not audited, matching `GET /plans`.

## User lookup

### `GET /users?email=&page=&page_size=`

Cross-tenant directory from `platform_user`. `email` is an **optional** filter:

- With `email`: returns users whose email matches (case-insensitive).
- Without `email` (or blank): returns a paginated listing of the directory,
  ordered by email. Previously this returned `VALIDATION_ERROR`; the contract
  changed when the listing was added.

`page_size` defaults to 20 and is clamped to 1-100.

```json
{
  "data": [
    {
      "user_id": "uuid",
      "email": "string",
      "display_name": "string|null",
      "memberships": [
        { "tenant_id": "uuid", "tenant_name": "string", "roles": ["tenant_admin"] }
      ]
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

### `GET /users/{user_id}`

Returns one projected user with tenant memberships. Unknown ids return `404
NOT_FOUND`.

## Audit

### `GET /audit?page=&page_size=`

Read-only operator audit listing. There is no mutate/delete endpoint.

## Tenant lifecycle commands

These endpoints forward to billing-service internal endpoints with
`X-Service-Token`. platform-service writes `operator_audit` only after a 2xx
billing response.

### `POST /tenants/{tenant_id}/suspend`

Request:

```json
{ "reason": "string|null" }
```

Success: forwards billing's `{ "data": { "changed": true|false }, "meta": {} }`.

### `POST /tenants/{tenant_id}/reactivate`

Success: forwards billing's `{ "data": { "changed": true|false }, "meta": {} }`.

## Plan catalog

### `GET /plans`

Returns the subscription-plan catalog. The request is forwarded to
billing-service's `GET /api/v1/billing/plans` over `X-Service-Token` —
platform-service keeps no local copy, so the operator view cannot diverge from
the billing source of truth. Reads are not audited.

The billing response is adapted to the platform plan contract: feature entries
use `code` (billing's `feature_code`), and each plan carries an explicit
`active: true` (billing lists active plans only).

```json
{
  "data": [
    {
      "plan_id": "uuid",
      "code": "standard",
      "name": "Standard",
      "price_monthly": 199000.0,
      "price_yearly": 1990000.0,
      "features": [{ "code": "grading", "enabled": true }],
      "active": true
    }
  ],
  "meta": {}
}
```

Downstream billing failures surface as the mapped error (e.g.
`DOWNSTREAM_ERROR`), never as an empty catalog.

### `POST /plans`

Request:

```json
{
  "code": "premium",
  "name": "Premium",
  "price_monthly": 499000.0,
  "price_yearly": 4990000.0,
  "features": [["academic_config", true]]
}
```

Success: `201` with billing's plan envelope. Duplicate codes surface as `409`.
Validation failures use `VALIDATION_ERROR` with field keys such as `code` and
`name`.

### `PUT /plans/{plan_id}`

Partial update forwarded to billing-service. Success: `204`.

### `DELETE /plans/{plan_id}`

Deactivates the plan through billing-service. Success: `204`.

## Subscription override

### `POST /tenants/{tenant_id}/subscription`

Request:

```json
{ "plan_id": "uuid" }
```

Success: `204`. Unknown plans surface billing's `UNKNOWN_PLAN` error.

Billing emits **only** `subscription.plan_changed` for this command, including
when it has to INSERT a subscription row for a tenant that had none —
`subscription.activated` never fires for an operator override. Consumers must not
treat `subscription.activated` as the guaranteed first subscription event for a
tenant; see `events/tenant.module_toggled.md` §Ordering.

The read sibling on this path is `GET /tenants/{tenant_id}/subscription`, under
"Subscription detail" above.
