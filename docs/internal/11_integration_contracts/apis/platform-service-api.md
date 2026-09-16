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

### `GET /tenants?search=&page=&page_size=`

Returns the local cross-tenant projection from `platform_tenant`.

`search` is an **optional** filter. A term matches either:

- `school_name` as a **case-insensitive substring**, or
- `tenant_id` by **prefix** (so the 8-character id the console displays, or a
  full UUID, both work).

An operator is not expected to know which kind of value they pasted, so one box
serves both. Absent, blank, or whitespace-only means "no filter" — never "match
the empty string". Terms are trimmed and capped at **128 characters**; a longer
term is rejected with `VALIDATION_ERROR` on field `search` rather than
truncated, since truncating would answer a question the operator did not ask.

`LIKE` metacharacters (`%`, `_`) in the term are matched as literal text.

> **Previously broken.** The parameter was accepted and silently ignored: the
> handler's query struct declared only `page`/`page_size` and serde drops
> unknown fields, so this endpoint returned every tenant regardless of the
> term. Clients that appeared to search were not searching.

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
      "attempted_at": "timestamp",
      "failure_reason": "string|null"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

`iam_user_id` and `tenant_id` are exposed so an operator can trace the orphaned
resources a half-finished saga left behind.

`failure_reason` explains why a `failed` row stopped. It is `null` for every
other state — a row still in flight has not failed, and a `completed` one never
does — so clients must treat it as nullable rather than keying off `state`
alone. Three properties of the value are contractual, all enforced in billing's
`domain::failure_reason`:

- **It is prefixed with the `AppError` code**, e.g.
  `CONFLICT: email is already registered` or
  `VALIDATION_ERROR: plan_id: plan_id is unknown`, so an operator can tell
  "already taken" from "unreachable" at a glance. Do not parse it — the prefix
  is for a human reader; the machine-readable signal is `state`.
- **It is sanitised.** The text of an `AppError::Internal` never reaches this
  field: it is replaced wholesale with the fixed string
  `INTERNAL_ERROR: registration failed unexpectedly; see service logs`. That
  variant wraps arbitrary driver, `reqwest`, and `anyhow` chains — including
  ones carrying a downstream response body, which on this path can contain a
  live activation link — so it is dropped rather than rendered. The detail still
  reaches the service log, which is the right audience for it.
- **It is truncated to 300 bytes**, on a character boundary, with a trailing
  `…` charged against the budget rather than appended to it.

`state` is optional; absent or blank means "every state". When supplied it is
validated against exactly four values — `user_created`, `tenant_created`,
`completed`, `failed` — mirroring billing's `pending_registration_state_chk`
constraint. Anything else returns `400 VALIDATION_ERROR` with the `state` field
key. This is a security boundary, not a convenience check: the value is
interpolated into the forwarded path, so an arbitrary string could otherwise
smuggle extra query parameters into billing's internal API.

**Operational reality — this is a live view, not a history.** Two caveats an
operator needs:

- **`failed` now has a producer.** Billing's `register_tenant` parks a
  registration in `failed` with a `failure_reason` at both of its failure
  points: when IAM refuses to create the admin, and when tenant/subscription
  creation fails afterwards (recorded *before* the compensating IAM delete, so
  the reason survives even if that delete itself fails). `user_created` and
  `completed` are written as before. `tenant_created` remains accepted by the
  constraint and by this filter with no code path producing it, so filtering on
  it returns an empty list; it is kept in the allowlist because the constraint
  allows it.
- Billing's janitor runs every 60 seconds and **deletes** any non-`completed` row
  older than ~5 minutes, after compensating (deleting the orphaned IAM user and
  tenant). `completed` rows are retained indefinitely. So a stalled registration
  is visible for about five minutes and then disappears — absence from this list
  does not mean it never happened. **`failed` rows are reaped on the same rule**:
  a `failure_reason` is a short-lived diagnostic for an operator watching the
  board, not a durable failure history.

Reads are not audited, matching `GET /plans`.

## User lookup

### `GET /users?search=&tenant=&page=&page_size=`

Cross-tenant directory from `platform_user`. `search` is an **optional**
filter. A term matches either:

- `email` as a **case-insensitive substring**, or
- `user_id` by **prefix** (the console's 8-character id display, or a full
  UUID).

Without `search` (or blank) the endpoint returns a paginated listing of the
directory, ordered by email. Trimming, the 128-character cap, the
`VALIDATION_ERROR` on an over-long term, and literal treatment of `LIKE`
metacharacters all match `GET /tenants` above.

`tenant` is a **second, independent optional filter** narrowing to users who
hold a membership in a matching tenant. A term matches either:

- a `tenant_name` inside `memberships` as a **case-insensitive substring**, or
- a `tenant_id` by **prefix**.

`search` and `tenant` are **ANDed**: they answer different questions ("which
user" vs "which school"), so supplying both returns the intersection rather
than one overriding the other. `tenant` gets the same trimming, 128-character
cap, and literal wildcard handling; its errors are field-scoped to `tenant`.

A user belonging to several tenants is matched by **any** of their
memberships. A user with no memberships matches no tenant term — belonging to
no tenant is not belonging to the one asked for.

> **Depends on the memberships projection.** `platform_user.memberships` used
> to be written **only** by `scripts/bootstrap-projections.sh`: the event
> consumer refreshed identity fields without touching the array, so any user
> created since the last backfill had `memberships: []` and would have been
> silently omitted by this filter. `tenant_user.created` / `tenant_user.updated`
> now project the membership directly (keyed on `tenant_id`, preserving other
> tenants' entries and idempotent under replay). `tenant_name` is resolved from
> `platform_tenant` at write time; if that row has not arrived yet the entry is
> still written with a null name, because the `tenant_id` is what this filter
> matches on.

`page_size` defaults to 20 and is clamped to 1-100. Filtered and unfiltered
responses are **both** paginated, so `meta` always describes what was returned.

**Parameter rename.** This filter was called `email`. It is now `search`,
because it no longer matches only an email. `email` remains accepted as a
**legacy alias** so an un-updated client does not lose its filter — with the
widened substring behaviour, not the old exact match. When both are supplied,
`search` wins.

> **Previously broken.** `email` was exact equality (`lower(email) =
> lower($1)`), so a partial address matched nothing and a user id never matched
> at all — an operator had to already know the complete address to find anyone.
> That path also ignored `LIMIT`/`OFFSET` while still reporting `meta.page` and
> `meta.page_size`, advertising a pagination it did not perform.

#### Search performance (both endpoints)

Both searches are **sequential scans**, deliberately.

A substring match compiles to `ILIKE '%term%'`, whose leading wildcard leaves
no prefix to seek on, so `idx_platform_user_email` — a btree on `lower(email)`
— **cannot** serve it. The id predicates compare `<id>::text`, an expression
rather than the raw primary-key column, so the PK index does not apply either.
Do not read these queries as index-assisted.

This is accepted because both tables are projections sized by the number of
schools and operators on the platform. Making them index-assisted means
`pg_trgm` plus a GIN index; that extension is **not** currently enabled for
platform-service and adding it is a migration decision of its own, not a
drive-by change.

Search terms reach Postgres only as **bind parameters**. They are never
formatted into a SQL string.

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

### `GET /audit?tenant=&page=&page_size=`

Read-only operator audit listing. There is no mutate/delete endpoint.

`tenant` is an **optional** filter narrowing to entries that target a matching
tenant. A term matches either the tenant's `school_name` as a
**case-insensitive substring** or its `tenant_id` by **prefix**. Trimming, the
128-character cap, the `VALIDATION_ERROR` on an over-long term (field-scoped to
`tenant`), and literal treatment of `LIKE` metacharacters all match
`GET /tenants`.

`operator_audit` stores no tenant name, so matching by name requires a join to
`platform_tenant`. Each entry therefore also carries **`target_name`**, the
resolved school name, so the console's Target column can show a name instead of
a raw UUID. It is `null` when the target is not a tenant or names a tenant the
projection does not know; `target_id` is always present for the copy button.

```json
{
  "data": [
    {
      "audit_id": "uuid",
      "actor_sub": "uuid",
      "action": "tenant.suspend",
      "target_type": "tenant",
      "target_id": "string",
      "target_name": "string|null",
      "outcome": "success",
      "metadata": {},
      "created_at": "timestamptz"
    }
  ],
  "meta": { "page": 1, "page_size": 20 }
}
```

> **`target_id` is TEXT and `target_type` is not always `'tenant'`.**
> `plan.create` stores a plan **code** (`"premium"`), and `plan.update` /
> `plan.deactivate` store a plan UUID under `target_type: "plan"`. The join
> therefore compares `platform_tenant.tenant_id::text` against `target_id`
> rather than casting `target_id::uuid`: the cast raises
> `invalid input syntax for type uuid` and fails the **entire** query, so the
> audit page would return 500 for every operator as soon as one plan existed.
> Casting the trusted column to text removes the failure mode instead of
> relying on `AND` short-circuiting, which the planner does not guarantee.

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

## Operator onboarding commands

Three write endpoints that let an operator stand a school up and rescue one
whose admin cannot get in, without touching SQL or the CLI. `POST /tenants`
forwards to billing; the other two forward to IAM. Both targets are called over
`X-Service-Token` at `BILLING_BASE_URL` / `IAM_BASE_URL`, and `operator_audit`
is written only after a 2xx from the downstream service — a refused command
leaves no audit row anywhere.

> **Every endpoint in this section returns a live credential, and the response
> is the only place it will ever exist.** IAM stores nothing but an Argon2 hash
> of each token, so no endpoint can read one back. **The link is shown once and
> is not retrievable afterwards.** It is therefore never logged, never persisted
> client-side, and specifically never written into `operator_audit` — a durable
> table any operator can read, where a link would be a standing account
> takeover. The audit rows below record the *fact* of each action from named
> fields, never the downstream envelope.
>
> A lost link cannot be recovered, only replaced: issue a fresh one with
> `POST /tenants/{tenant_id}/invitations` for a school admin, or
> `POST /users/{user_id}/reset-password` for any existing user. Note that the
> public `POST /auth/set-password/resend` is **not** a recovery path here — it
> refuses any account that is not `active`, which is every operator-created
> admin who has not activated yet. That refusal is what
> `POST /users/{user_id}/reset-password` exists to route around.

### `POST /tenants`

Creates a school and its first administrator, returning the one-time link that
admin uses to set their own password.

Request:

```json
{
  "school_name": "SMA Harapan",
  "admin_email": "kepala@harapan.test",
  "admin_full_name": "Kepala Harapan",
  "plan_id": "uuid"
}
```

**There is no `admin_password` field, by construction.** The forwarded body is
built explicitly from these four fields rather than round-tripped, and billing's
`POST /internal/tenants` does not accept a password either, so the operator
never chooses, sees, or transports a school's credential. The admin is created
`pending` and activates themselves through the link.

All four fields are forwarded and all four are validated by billing; an unknown
`plan_id` comes back as `VALIDATION_ERROR` on field `plan_id`.

Success (**201**) — billing's `RegisterTenantOutput` proxied verbatim:

```json
{
  "data": {
    "tenant_id": "uuid",
    "user_id": "uuid",
    "subscription_id": "uuid",
    "plan_code": "premium",
    "activation_link": "https://app.example/set-password?token=<token>"
  },
  "meta": {}
}
```

`activation_link` is `skip_serializing_if = "Option::is_none"` in billing, so it
is **absent from the wire** — not `null` — when no link was minted. Clients must
type it as optional. On this route a 201 always carries one (the passwordless
path is the only path), but the field is shared with billing's other
registration entry points, one of which attaches an already-authenticated user
and has no link to give. The URL points at `/set-password`, not
`/invitations/accept`: it carries a set-password token, and the invitation page
resolves a different table and would reject it.

Errors:

| Code                   | HTTP | Cause |
|------------------------|------|-------|
| `VALIDATION_ERROR`     | 400  | Billing's per-field map, forwarded intact (`school_name`, `admin_email`, `admin_full_name`, `plan_id`). |
| `EMAIL_ALREADY_EXISTS` | 409  | IAM already knows `admin_email`. The fix is another address. |

Audit: `tenant.create` on `target_type: "tenant"`, metadata `school_name` and
`admin_email` only.

### `POST /tenants/{tenant_id}/invitations`

Invites an administrator into an **existing** school. This is the recovery path
when the activation link minted at tenant creation is lost or has expired: IAM
will not re-issue the original, but it will mint a fresh invitation.

Request:

```json
{ "email": "admin2@harapan.test", "roles": ["tenant_admin"] }
```

`roles` accepts the five roles a tenant admin can assign — `teacher`,
`homeroom_teacher`, `principal`, `parent`, `student` — **plus `tenant_admin`**.
That last one is the operator's carve-out and the reason this route exists;
re-issuing a lost tenant-admin handover is exactly what it is for. `super_admin`
is assignable from neither path. A built-in role outside the operator's set
returns `VALIDATION_ERROR` on field `roles`, worded for a platform operator
rather than a tenant admin. Non-built-in (custom tenant) codes pass this check
and are resolved against the `role` table when the invitation row is written.

**Clients must not send `issued_by_operator`.** platform-service injects it from
the caller's JWT (`auth.user_id`) when it builds the forwarded body, and the
body is constructed field by field rather than round-tripped, so a
client-supplied value is dropped. IAM records it on the `tenant_user.invited`
event, which is how the invitation — whose `invited_by` column is a foreign key
and must therefore name a real tenant member — is joined back to the
`operator_audit` row naming the actual actor. See
`events/tenant-user-events.md`.

Success (**201**) — IAM's envelope proxied verbatim:

```json
{
  "data": {
    "invitation_id": "uuid",
    "email": "admin2@harapan.test",
    "roles": ["tenant_admin"],
    "status": "pending",
    "expires_at": "2026-09-21T12:00:00Z",
    "tenant_id": "uuid",
    "activation_link": "https://app.example/invitations/accept?token=<token>",
    "token": "<token>"
  },
  "meta": {}
}
```

`activation_link` here is **not** optional — every invitation mints a token, so
an absent link would be a contract break. `token` is the same secret unwrapped;
it is on the wire because IAM's tenant-scoped invitation response has always
carried it, and the console deliberately never renders it. An operator hands
over a link, not a bare token. This link points at `/invitations/accept`, the
opposite of `POST /tenants` above.

Errors:

| Code                        | HTTP | Cause |
|-----------------------------|------|-------|
| `VALIDATION_ERROR`          | 400  | IAM's per-field map (`email`, `roles`), forwarded intact. |
| `NOT_FOUND`                 | 404  | The school has no member who can be credited as the inviter. |
| `MEMBERSHIP_ALREADY_EXISTS` | 409  | The address already belongs to a member of this school. Use that account. |
| `PENDING_INVITATION_EXISTS` | 409  | The address already holds a pending invitation here. Revoke it, or hand over its link. |

The two conflicts are distinct on purpose and neither is a retry: they have
different operator fixes. The 404 is real, not theoretical — IAM must name a
tenant member as `invited_by`, and it resolves one itself (preferring a
`tenant_admin`, then an `active` account, then the oldest), which finds nothing
for a school whose only member has been deleted.

Audit: `tenant.invite` on `target_type: "tenant"`, metadata `email` and `roles`
only.

### `POST /users/{user_id}/reset-password`

Hands the operator a set-password link for an existing user. **No request
body.** The target is the path parameter; nothing about the account is
client-supplied.

Success (**200**):

```json
{
  "data": {
    "user_id": "uuid",
    "set_password_link": "https://app.example/set-password?token=<token>"
  },
  "meta": {}
}
```

The field is **`set_password_link`**, not `activation_link`. The two names mark
two different token types in two different tables, and the invitation page would
reject this one with `INVALID_INVITATION_TOKEN`.

**IAM decides who can be reset, and it is not the obvious rule.** The command
behind this route is `issue_operator_password_reset`, written specifically for
the operator path rather than reusing the public
`POST /auth/set-password/resend` — whose anti-abuse guard refuses any account
that already has a password, which is precisely what a reset is for. Three
outcomes:

- **A `pending` (passwordless) user succeeds** and gets a link. This is the
  stranded-admin recovery path and the main reason the endpoint exists; the
  operator has no reason to know whether the account ever activated. Redeeming
  the link activates them.
- An `active` user succeeds, with or without an existing password.
- A **`disabled`** account is the only refusal: `409 USER_DISABLED`. `login`
  rejects a non-active user before it ever checks a password, so a link would
  resolve successfully and still leave them locked out — a silent lie. The
  operator's fix is to enable the account first.

A `user_id` that does not exist is `404 NOT_FOUND`, kept distinct so a mistyped
id does not read as a domain refusal.

Issuing a link **revokes any set-password link still in flight** for that user,
so a holder of an older one cannot race the operator. Refresh tokens are
deliberately *not* revoked here: issuing a link does not yet change the
password, and logging the user out before the operator has even delivered it
would be a visible outage for a reset that may never be completed.
`POST /auth/set-password` revokes them on redemption, which is when the
credential actually changes.

Errors:

| Code            | HTTP | Cause |
|-----------------|------|-------|
| `NOT_FOUND`     | 404  | No such user. |
| `USER_DISABLED` | 409  | The account is disabled; enable it first. |

Audit: `user.reset_password` on `target_type: "user"`, metadata `user_id` only.

### Downstream error mapping

Every endpoint that forwards to billing or IAM normalises the reply through one
function: any non-2xx becomes an error, so each caller's post-forward code
(projection writes, audit rows) is unreachable after a downstream failure.

Downstream codes are preserved by an **allowlist**, not passed through wholesale.
The codes that survive verbatim are exactly:

| Downstream code             | HTTP | Where it comes from |
|-----------------------------|------|---------------------|
| `FEATURE_NOT_AVAILABLE`     | 403  | Billing: plan does not entitle the feature. |
| `SUBSCRIPTION_EXPIRED`      | 403  | Billing: no active subscription. |
| `EMAIL_ALREADY_EXISTS`      | 409  | Billing/IAM: admin address already registered. |
| `MEMBERSHIP_ALREADY_EXISTS` | 409  | IAM: invitee is already a member. |
| `PENDING_INVITATION_EXISTS` | 409  | IAM: invitee already has a pending invitation. |
| `USER_DISABLED`             | 409  | IAM: password reset on a disabled account. |

Everything else is treated as an internal detail and flattened:

- Any other 403 → `DOWNSTREAM_FORBIDDEN`.
- **Any other 409 → `PLAN_CODE_EXISTS`.** This arm has no code check: it is the
  trailing conflict case, and plan creation is the only *other* conflict this
  service forwards. A downstream that introduces a new 409 on any forwarded
  route will therefore report a plan-code conflict until it is given an arm of
  its own. Adding one is not optional bookkeeping — it is what stops an
  unrelated refusal from rendering as "a plan with this code already exists" on
  a user or tenant screen.
- 400 `VALIDATION_ERROR` → the downstream's `/error/fields` map, forwarded
  intact so the console can highlight the offending input. A downstream that
  sends no usable map falls back to a single `request` pseudo-field.
- Any other 400 → `DOWNSTREAM_BAD_REQUEST`; 401 → `UNAUTHORIZED_SERVICE_CALL`;
  404 → `NOT_FOUND`; anything else → `DOWNSTREAM_ERROR`.

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

Success: `204`. An unknown plan is billing's `400 UNKNOWN_PLAN`, which reaches
the operator as **`DOWNSTREAM_BAD_REQUEST`** carrying billing's message —
`UNKNOWN_PLAN` is not on the allowlist under "Downstream error mapping" above,
and only `VALIDATION_ERROR` is preserved among 400s. Clients must switch on
`DOWNSTREAM_BAD_REQUEST` here, not on `UNKNOWN_PLAN`.

Billing emits **only** `subscription.plan_changed` for this command, including
when it has to INSERT a subscription row for a tenant that had none —
`subscription.activated` never fires for an operator override. Consumers must not
treat `subscription.activated` as the guaranteed first subscription event for a
tenant; see `events/tenant.module_toggled.md` §Ordering.

The read sibling on this path is `GET /tenants/{tenant_id}/subscription`, under
"Subscription detail" above.
