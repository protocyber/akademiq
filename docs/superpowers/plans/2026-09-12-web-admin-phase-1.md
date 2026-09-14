# Web Admin Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give platform operators visibility into tenant subscriptions, module entitlements, failed registrations, and service health from the web-admin console.

**Architecture:** Four read surfaces (plus one write) in `apps/web-admin`, backed by five new platform-service endpoints. Reads come from existing local projections; the registration board proxies billing over `X-Service-Token`; the health board is the one place a synchronous cross-service fan-out is correct. Billing gains a `tenant.module_toggled` outbox event so operator toggles reach the projection.

**Tech Stack:** Rust + Axum + SQLx (PostgreSQL 18), refinery migrations, RabbitMQ outbox; Nuxt 4 + Nuxt UI 4 + TanStack Vue Query; Vitest + Playwright; `cargo test` with testcontainers + wiremock.

**Spec:** `docs/superpowers/specs/2026-09-12-web-admin-roadmap-design.md`

## Global Constraints

- Backend rules are authoritative in `apps/backend/CONVENTIONS.md`; web-admin rules in `apps/web-admin/CONVENTIONS.md`. Read both before starting.
- API base path `/api/v1/platform`. Success envelope `{ "data": ..., "meta": ... }`. Error envelope `{ "error": { "code": "...", "message": "..." } }`.
- Every platform endpoint calls `require_platform_admin(&auth)?` as its first statement.
- Never trust a client-supplied `tenant_id` for authorization; the platform token carries no tenant scope, so tenant ids arrive as path params and are used only as lookup keys.
- Migrations use refinery. New platform migration file: `apps/backend/services/platform-service/migrations/V2__module_projection.sql`. Never edit `V1__init.sql`.
- Web-admin: no raw `fetch`/`$fetch`/`useFetch` in pages or components. All I/O goes through `apiFetch` inside `app/lib/queries/` or `app/lib/mutations/`.
- Web-admin: no native `<button>`, `<input>`, `<select>`, `<textarea>`, `<form>` in pages/components/layouts. Use Nuxt UI (`UButton`, `UInput`, `USwitch`, ...).
- Error copy lives only in `app/lib/errors/messages.ts`; components call `getErrorMessage(error, { fallback })`.
- Loading: action-bound controls use `:loading`; first-paint layout regions use `<RegionSkeleton />` (via `DataTableCard`'s `loading` prop).
- Do not run `git commit` unless the user explicitly asks. Commit steps below are written for when they do; otherwise stop at a green test run.

## Task Order and Dependencies

```
Task 1 (subscription read) ─────────────────> Task 7 (subscription UI) ─┐
                                                                        │
Task 2 (billing event) ─> Task 3 (projection) ─> Task 4 (module API) ─> Task 8 (module UI)

Task 5 (registration proxy) ────────────────> Task 9  (registration UI)

Task 6 (health fan-out) ────────────────────> Task 10 (health UI)

Task 11 (docs) depends on Tasks 1-6
```

Tasks 1, 2, 5, 6 are independent and may run in parallel. Task 3 depends on 2;
Task 4 depends on 3 (and on Task 1's `get_subscription`).

Task 8 depends on **both** Task 4 (the endpoints) and Task 7 — its mutation
invalidates `tenantKeys.subscription(tenantId)`, which Task 7 adds to
`tenantKeys`. Running Task 8 first would reference an undefined key.

Tasks 9 and 10 each depend only on their endpoint task and may run in parallel
with the 7→8 chain.

---

### Task 1: Subscription read endpoint

**Files:**
- Modify: `apps/backend/services/platform-service/src/repo.rs` (add `SubscriptionRow` + `get_subscription`)
- Modify: `apps/backend/services/platform-service/src/http.rs` (add route + handler)
- Test: `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: existing `PlatformProjectionRepo`, `require_platform_admin`, `AppState`.
- Produces: `GET /api/v1/platform/tenants/:tenant_id/subscription` returning
  `{ "data": { plan_code, status, modules, started_at, ends_at } | null, "meta": {} }`.
  Also produces `repo::SubscriptionRow` and
  `PlatformProjectionRepo::get_subscription(&self, tenant_id: Uuid) -> Result<Option<SubscriptionRow>, sqlx::Error>`,
  used by Task 4.

Background: `platform_subscription` already exists (see `migrations/V1__init.sql`) with
columns `tenant_id, plan_code, status, modules JSONB, started_at, ends_at, updated_at`.
No migration is needed. There is no `payment_method` column — do not invent one.

- [ ] **Step 1: Write the failing test**

Append to `apps/backend/services/platform-service/tests/integration.rs`:

```rust
async fn seed_subscription(
    pool: &PgPool,
    tenant_id: uuid::Uuid,
    plan_code: &str,
    status: &str,
    modules: Value,
) {
    sqlx::query(
        r#"
        INSERT INTO platform_subscription
            (tenant_id, plan_code, status, modules, started_at, ends_at, updated_at)
        VALUES ($1, $2, $3, $4, now(), now() + interval '30 days', now())
        ON CONFLICT (tenant_id) DO UPDATE
           SET plan_code = EXCLUDED.plan_code,
               status = EXCLUDED.status,
               modules = EXCLUDED.modules
        "#,
    )
    .bind(tenant_id)
    .bind(plan_code)
    .bind(status)
    .bind(modules)
    .execute(pool)
    .await
    .unwrap();
}

#[tokio::test]
async fn subscription_returns_projection_row() {
    let (pool, state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    seed_subscription(&pool, tenant_id, "premium", "active", json!({ "grading": true })).await;

    let (status, json) = get(
        state.clone(),
        &format!("/api/v1/platform/tenants/{tenant_id}/subscription"),
        &operator_token(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"]["plan_code"], "premium");
    assert_eq!(json["data"]["status"], "active");
    assert_eq!(json["data"]["modules"]["grading"], true);
    assert!(json["data"]["started_at"].is_string());
    assert!(json["data"]["ends_at"].is_string());
}

#[tokio::test]
async fn subscription_returns_null_when_no_row() {
    let (pool, state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    // Deliberately no platform_subscription row.

    let (status, json) = get(
        state.clone(),
        &format!("/api/v1/platform/tenants/{tenant_id}/subscription"),
        &operator_token(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert!(json["data"].is_null());
}

#[tokio::test]
async fn subscription_requires_platform_admin() {
    let (pool, state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;

    let (status, _json) = get(
        state.clone(),
        &format!("/api/v1/platform/tenants/{tenant_id}/subscription"),
        &platform_token(&["support"]),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration subscription_`
Expected: FAIL — the route does not exist, so the handler returns 404 and the
`assert_eq!(status, StatusCode::OK)` assertions fail.

- [ ] **Step 3: Add the repo row type and query**

In `apps/backend/services/platform-service/src/repo.rs`, add next to the other
row structs:

```rust
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SubscriptionRow {
    pub tenant_id: Uuid,
    pub plan_code: String,
    pub status: String,
    pub modules: Value,
    pub started_at: Option<DateTime<Utc>>,
    pub ends_at: Option<DateTime<Utc>>,
}
```

And inside `impl PlatformProjectionRepo`, next to `get_tenant_stats`:

```rust
    pub async fn get_subscription(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<SubscriptionRow>, sqlx::Error> {
        sqlx::query_as::<_, SubscriptionRow>(
            r#"
            SELECT tenant_id, plan_code, status, modules, started_at, ends_at
              FROM platform_subscription
             WHERE tenant_id = $1
            "#,
        )
        .bind(tenant_id)
        .fetch_optional(&self.pool)
        .await
    }
```

- [ ] **Step 4: Add the route and handler**

`/api/v1/platform/tenants/:tenant_id/subscription` already exists in `router()`
as a `post(override_subscription)` route. Axum panics at startup if two separate
`.route()` calls register the same path, so do **not** add a new `.route()`
line. Merge the method into the existing registration instead: change

```rust
        .route(
            "/api/v1/platform/tenants/:tenant_id/subscription",
            post(override_subscription),
        )
```

to

```rust
        .route(
            "/api/v1/platform/tenants/:tenant_id/subscription",
            get(get_tenant_subscription).post(override_subscription),
        )
```

and add no other route line. Then add the handler next to `get_tenant_usage`:

```rust
async fn get_tenant_subscription(
    State(state): State<AppState>,
    auth: PlatformAuthContext,
    Path(tenant_id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    require_platform_admin(&auth)?;
    let subscription = state
        .projection_repo
        .get_subscription(tenant_id)
        .await
        .map_err(AppError::internal)?;
    Ok(Json(json!({ "data": subscription, "meta": {} })))
}
```

`Option<SubscriptionRow>` serialises to `null` when absent, which is exactly
the "no subscription on record" contract.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/backend && cargo test -p platform-service --test integration subscription_`
Expected: 3 passed.

- [ ] **Step 6: Verify nothing else broke**

Run: `cd apps/backend && cargo test -p platform-service && cargo clippy -p platform-service -- -D warnings`
Expected: all tests pass, no clippy warnings.

- [ ] **Step 7: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/platform-service/src/repo.rs \
        apps/backend/services/platform-service/src/http.rs \
        apps/backend/services/platform-service/tests/integration.rs
git commit -m "feat(platform): expose tenant subscription projection endpoint"
```

---

### Task 2: Billing emits `tenant.module_toggled`

**Files:**
- Modify: `apps/backend/services/billing-service/src/commands.rs` (`toggle_module`, ~line 278)
- Modify: `apps/backend/services/billing-service/src/http.rs` (add internal route + handler)
- Test: `apps/backend/services/billing-service/tests/integration.rs`

**Interfaces:**
- Consumes: existing `state.tenant_module_repo.upsert`, `state.outbox_repo.enqueue`, `state.subscription_repo`, `state.plan_repo`.
- Produces:
  - Event `tenant.module_toggled` with payload `{ "tenant_id": Uuid, "feature_code": String, "enabled": bool }`, consumed by Task 3.
  - `PATCH /api/v1/billing/internal/tenants/:id/modules` (X-Service-Token) with body `{ "feature_code": String, "enabled": bool }`, called by Task 4.
  - `commands::internal_toggle_module(state: &AppState, tenant_id: Uuid, feature_code: &str, enabled: bool) -> Result<(), AppError>`.

Background: today `toggle_module` writes `tenant_module` and publishes nothing, so
no projection ever learns about a toggle. It already enforces the domain rules —
`SUBSCRIPTION_EXPIRED` when the subscription is missing or inactive, and
`FEATURE_NOT_AVAILABLE` when the plan does not entitle the feature. Do not
duplicate those rules anywhere else.

- [ ] **Step 1: Write the failing test**

Append to `apps/backend/services/billing-service/tests/integration.rs`. Match the
existing helpers in that file for booting state and seeding a tenant with a plan;
read the top of the file first and reuse its `boot()`/seed helpers rather than
inventing new ones.

```rust
#[tokio::test]
async fn internal_module_toggle_enqueues_event() {
    let (pool, state, _c) = boot().await;
    let tenant_id = seed_tenant_with_active_plan(&pool, "premium", &["grading"]).await;

    billing_service::commands::internal_toggle_module(&state, tenant_id, "grading", false)
        .await
        .expect("toggle succeeds");

    let row: (String, serde_json::Value) = sqlx::query_as(
        "SELECT event_type, payload FROM outbox WHERE event_type = 'tenant.module_toggled'",
    )
    .fetch_one(&pool)
    .await
    .expect("outbox row exists");

    assert_eq!(row.0, "tenant.module_toggled");
    assert_eq!(row.1["tenant_id"], tenant_id.to_string());
    assert_eq!(row.1["feature_code"], "grading");
    assert_eq!(row.1["enabled"], false);
}

#[tokio::test]
async fn internal_module_toggle_rejects_unentitled_feature() {
    let (pool, state, _c) = boot().await;
    let tenant_id = seed_tenant_with_active_plan(&pool, "basic", &["grading"]).await;

    let err = billing_service::commands::internal_toggle_module(
        &state,
        tenant_id,
        "academic_config",
        true,
    )
    .await
    .expect_err("unentitled feature is rejected");

    assert_eq!(err.code(), "FEATURE_NOT_AVAILABLE");

    let count: (i64,) = sqlx::query_as(
        "SELECT count(*) FROM outbox WHERE event_type = 'tenant.module_toggled'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 0, "rejected toggle must not enqueue an event");
}
```

If `AppError` exposes its code under a different accessor than `err.code()`,
check `apps/backend/libs/common-errors/src/lib.rs` and use the real one; do not
add an accessor just for the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p billing-service --test integration internal_module_toggle`
Expected: FAIL to compile — `internal_toggle_module` does not exist.

- [ ] **Step 3: Enqueue the event in the shared command path**

In `apps/backend/services/billing-service/src/commands.rs`, at the end of
`toggle_module`, replace the trailing `Ok(())` so the upsert and the outbox
write happen together:

```rust
    state
        .outbox_repo
        .enqueue(
            &state.pool,
            Uuid::new_v4(),
            "tenant.module_toggled",
            &json!({
                "tenant_id": tenant_id,
                "feature_code": feature_code,
                "enabled": enabled,
            }),
        )
        .await
        .map_err(AppError::internal)?;
    Ok(())
```

Then add the operator-facing wrapper directly below `toggle_module`:

```rust
/// Operator-initiated module toggle. Delegates to `toggle_module` so the
/// entitlement and subscription-status rules are enforced in exactly one
/// place.
pub async fn internal_toggle_module(
    state: &AppState,
    tenant_id: Uuid,
    feature_code: &str,
    enabled: bool,
) -> Result<(), AppError> {
    toggle_module(state, tenant_id, feature_code, enabled).await
}
```

- [ ] **Step 4: Add the internal route and handler**

In `apps/backend/services/billing-service/src/http.rs`, add to `router()` after
the `internal/tenants/:id/reactivate` route:

```rust
        .route(
            "/api/v1/billing/internal/tenants/:id/modules",
            patch(internal_toggle_module_handler),
        )
```

Add the handler next to `internal_reactivate_handler`, following that handler's
`ServiceToken` signature exactly:

```rust
async fn internal_toggle_module_handler(
    State(state): State<AppState>,
    _token: ServiceToken,
    Path(tenant_id): Path<Uuid>,
    Json(body): Json<ToggleBody>,
) -> Result<Json<Value>, AppError> {
    internal_toggle_module(&state, tenant_id, &body.feature_code, body.enabled).await?;
    Ok(Json(json!({ "data": { "ok": true }, "meta": {} })))
}
```

Add `internal_toggle_module` to the `use crate::commands::{...}` import list at
the top of the file. `ToggleBody` already exists in this file — reuse it.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/backend && cargo test -p billing-service --test integration internal_module_toggle`
Expected: 2 passed.

- [ ] **Step 6: Verify the tenant-facing toggle still works**

Run: `cd apps/backend && cargo test -p billing-service && cargo clippy -p billing-service -- -D warnings`
Expected: all pass. The tenant endpoint now also enqueues the event — that is
intended, and any existing test asserting an empty outbox after a toggle should
be updated to expect the new event.

- [ ] **Step 7: Document the event**

Create `docs/internal/11_integration_contracts/events/tenant.module_toggled.md`,
matching the structure of the sibling files in that directory (read
`subscription.activated.md` first). Content must state: producer
`billing_service`; payload fields `tenant_id` (uuid), `feature_code` (string),
`enabled` (bool); emitted on every successful module toggle, whether initiated
by a tenant admin or a platform operator; consumers: `platform_service`.

- [ ] **Step 8: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/billing-service/src/commands.rs \
        apps/backend/services/billing-service/src/http.rs \
        apps/backend/services/billing-service/tests/integration.rs \
        docs/internal/11_integration_contracts/events/tenant.module_toggled.md
git commit -m "feat(billing): emit tenant.module_toggled and add internal toggle endpoint"
```

---

### Task 3: Platform projection consumes `tenant.module_toggled`

**Files:**
- Create: `apps/backend/services/platform-service/migrations/V2__module_projection.sql`
- Modify: `apps/backend/services/platform-service/src/repo.rs` (add `patch_subscription_module`)
- Modify: `apps/backend/services/platform-service/src/events.rs` (handle the event)
- Test: `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: `tenant.module_toggled` from Task 2; `SubscriptionRow` / `get_subscription` from Task 1.
- Produces: `PlatformProjectionRepo::patch_subscription_module(&self, tenant_id: Uuid, feature_code: &str, enabled: bool) -> Result<(), sqlx::Error>`.

Design note: the projection patches a single key inside
`platform_subscription.modules` rather than replacing the object, so a toggle
never clobbers the other modules written by `subscription.activated`.

The migration exists only to guarantee a `platform_subscription` row can be
created by a toggle arriving before any subscription event, by relaxing the
`plan_code` NOT NULL requirement with a default.

- [ ] **Step 1: Write the failing test**

Append to `apps/backend/services/platform-service/tests/integration.rs`:

```rust
#[tokio::test]
async fn module_toggle_patches_single_key() {
    let (pool, _state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    seed_subscription(
        &pool,
        tenant_id,
        "premium",
        "active",
        json!({ "grading": true, "academic_config": true }),
    )
    .await;

    let repo = platform_service::repo::PlatformProjectionRepo::new(pool.clone());
    repo.patch_subscription_module(tenant_id, "grading", false)
        .await
        .expect("patch succeeds");

    let row = repo
        .get_subscription(tenant_id)
        .await
        .unwrap()
        .expect("subscription row");

    assert_eq!(row.modules["grading"], false, "toggled key is updated");
    assert_eq!(
        row.modules["academic_config"], true,
        "other keys are left intact"
    );
    assert_eq!(row.plan_code, "premium", "plan code is untouched");
}

#[tokio::test]
async fn module_toggle_creates_row_when_absent() {
    let (pool, _state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    // No platform_subscription row yet.

    let repo = platform_service::repo::PlatformProjectionRepo::new(pool.clone());
    repo.patch_subscription_module(tenant_id, "grading", true)
        .await
        .expect("patch succeeds");

    let row = repo
        .get_subscription(tenant_id)
        .await
        .unwrap()
        .expect("row was created");
    assert_eq!(row.modules["grading"], true);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration module_toggle`
Expected: FAIL to compile — `patch_subscription_module` does not exist.

- [ ] **Step 3: Write the migration**

Create `apps/backend/services/platform-service/migrations/V2__module_projection.sql`:

```sql
-- A tenant.module_toggled event can arrive before any subscription event for
-- the same tenant. Allow the projection to create the row with a placeholder
-- plan code, which a later subscription event overwrites.
ALTER TABLE platform_subscription
    ALTER COLUMN plan_code SET DEFAULT 'unknown';

ALTER TABLE platform_subscription
    ALTER COLUMN status SET DEFAULT 'unknown';
```

- [ ] **Step 4: Add the repo method**

In `apps/backend/services/platform-service/src/repo.rs`, inside
`impl PlatformProjectionRepo`, next to `upsert_subscription`:

```rust
    /// Patch one key inside `platform_subscription.modules`, leaving the other
    /// keys untouched. Creates the row when the tenant has no subscription
    /// projection yet.
    pub async fn patch_subscription_module(
        &self,
        tenant_id: Uuid,
        feature_code: &str,
        enabled: bool,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            r#"
            INSERT INTO platform_subscription (tenant_id, modules, updated_at)
            VALUES ($1, jsonb_build_object($2::text, $3::boolean), now())
            ON CONFLICT (tenant_id) DO UPDATE
               SET modules = platform_subscription.modules
                             || jsonb_build_object($2::text, $3::boolean),
                   updated_at = now()
            "#,
        )
        .bind(tenant_id)
        .bind(feature_code)
        .bind(enabled)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
```

- [ ] **Step 5: Handle the event in the consumer**

In `apps/backend/services/platform-service/src/events.rs`, add a match arm
inside `handle`, after the `"tenant.reactivated"` arm:

```rust
            "tenant.module_toggled" => {
                let payload: ModuleToggledPayload = serde_json::from_value(envelope.payload)?;
                self.repo
                    .patch_subscription_module(
                        payload.tenant_id,
                        &payload.feature_code,
                        payload.enabled,
                    )
                    .await?;
            }
```

And add the payload struct next to the other payload structs at the bottom of
the file:

```rust
#[derive(Debug, Deserialize)]
struct ModuleToggledPayload {
    tenant_id: Uuid,
    feature_code: String,
    enabled: bool,
}
```

- [ ] **Step 6: Subscribe the routing key**

`ROUTING_KEYS` at the top of `apps/backend/services/platform-service/src/events.rs`
enumerates event names explicitly, so the consumer will not receive the new
event until it is listed. Add it after `"tenant.reactivated"`:

```rust
const ROUTING_KEYS: &[&str] = &[
    "tenant.registered",
    "subscription.activated",
    "subscription.plan_changed",
    "tenant.suspended",
    "tenant.reactivated",
    "tenant.module_toggled",
    "tenant_user.created",
    "tenant_user.updated",
    "student.enrolled",
    "teacher.assigned",
    "plan-catalog.*",
];
```

Note for the deployer: the `platform.projections` queue already exists in
running environments with the old binding set. The new binding is added on
consumer startup, so events published before the new build is deployed are not
retroactively delivered. Use `scripts/bootstrap-projections.sh` if a backfill
is needed.

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd apps/backend && cargo test -p platform-service --test integration module_toggle`
Expected: 2 passed.

- [ ] **Step 8: Verify the whole service**

Run: `cd apps/backend && cargo test -p platform-service && cargo clippy -p platform-service -- -D warnings`
Expected: all pass.

- [ ] **Step 9: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/platform-service/migrations/V2__module_projection.sql \
        apps/backend/services/platform-service/src/repo.rs \
        apps/backend/services/platform-service/src/events.rs \
        apps/backend/services/platform-service/tests/integration.rs
git commit -m "feat(platform): project tenant.module_toggled into subscription modules"
```

---

### Task 4: Platform module read + toggle endpoints

**Files:**
- Modify: `apps/backend/services/platform-service/src/repo.rs` (add `get_plan_catalog_entry`)
- Modify: `apps/backend/services/platform-service/src/http.rs` (routes, handlers, `map_downstream_error` fix)
- Test: `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: `get_subscription` (Task 1), `patch_subscription_module` (Task 3), billing's `PATCH /internal/tenants/:id/modules` (Task 2), existing `forward_to_billing` and `write_audit`.
- Produces:
  - `GET /api/v1/platform/tenants/:tenant_id/modules` returning
    `{ "data": { "modules": [{ "code": String, "enabled": bool, "entitled": bool }] }, "meta": {} }`
  - `PUT /api/v1/platform/tenants/:tenant_id/modules` with body `{ "feature_code": String, "enabled": bool }`
  - `PlatformProjectionRepo::get_plan_catalog_entry(&self, code: &str) -> Result<Option<PlanCatalogRow>, sqlx::Error>`

Design note: `entitled` comes from `platform_plan_catalog.features` for the
tenant's current plan. A feature that is not entitled renders disabled in the UI
(Task 8) so the operator does not submit a toggle billing will reject.

Important bug to fix in this task: `map_downstream_error` currently maps every
downstream 403 to `DOWNSTREAM_FORBIDDEN` and every 409 to `PLAN_CODE_EXISTS`.
That would mask billing's `FEATURE_NOT_AVAILABLE` and `SUBSCRIPTION_EXPIRED`
codes, which the spec requires to surface as-is.

- [ ] **Step 1: Write the failing test**

Append to `apps/backend/services/platform-service/tests/integration.rs`:

```rust
async fn seed_plan_catalog(pool: &PgPool, code: &str, features: Value) {
    sqlx::query(
        r#"
        INSERT INTO platform_plan_catalog (code, name, active, features, updated_at)
        VALUES ($1, $1, true, $2, now())
        ON CONFLICT (code) DO UPDATE SET features = EXCLUDED.features
        "#,
    )
    .bind(code)
    .bind(features)
    .execute(pool)
    .await
    .unwrap();
}

async fn send(
    state: AppState,
    method: axum::http::Method,
    uri: &str,
    token: &str,
    body: Value,
) -> (StatusCode, Value) {
    let app = router(state);
    let resp = app
        .oneshot(
            Request::builder()
                .method(method)
                .uri(uri)
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    (status, body_to_json(resp).await)
}

#[tokio::test]
async fn modules_list_marks_entitlement() {
    let (pool, state, _billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    seed_plan_catalog(
        &pool,
        "premium",
        json!({ "grading": true, "academic_config": true }),
    )
    .await;
    seed_subscription(
        &pool,
        tenant_id,
        "premium",
        "active",
        json!({ "grading": true }),
    )
    .await;

    let (status, json) = get(
        state.clone(),
        &format!("/api/v1/platform/tenants/{tenant_id}/modules"),
        &operator_token(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    let modules = json["data"]["modules"].as_array().unwrap();
    let grading = modules.iter().find(|m| m["code"] == "grading").unwrap();
    assert_eq!(grading["enabled"], true);
    assert_eq!(grading["entitled"], true);
    let config = modules
        .iter()
        .find(|m| m["code"] == "academic_config")
        .unwrap();
    assert_eq!(config["enabled"], false, "entitled but not switched on");
    assert_eq!(config["entitled"], true);
}

#[tokio::test]
async fn module_toggle_forwards_and_audits_on_success() {
    let (pool, state, billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;
    seed_subscription(&pool, tenant_id, "premium", "active", json!({})).await;

    Mock::given(method("PATCH"))
        .and(path(format!(
            "/api/v1/billing/internal/tenants/{tenant_id}/modules"
        )))
        .and(header_exists("X-Service-Token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "data": { "ok": true }, "meta": {}
        })))
        .mount(&billing)
        .await;

    let (status, _json) = send(
        state.clone(),
        axum::http::Method::PUT,
        &format!("/api/v1/platform/tenants/{tenant_id}/modules"),
        &operator_token(),
        json!({ "feature_code": "grading", "enabled": true }),
    )
    .await;

    assert_eq!(status, StatusCode::OK);

    let count: (i64,) = sqlx::query_as(
        "SELECT count(*) FROM operator_audit WHERE action = 'tenant.module_toggle'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 1, "audit written after 2xx");
}

#[tokio::test]
async fn module_toggle_surfaces_feature_not_available_and_skips_audit() {
    let (pool, state, billing, _c) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_tenant(&pool, tenant_id, "active").await;

    Mock::given(method("PATCH"))
        .and(path(format!(
            "/api/v1/billing/internal/tenants/{tenant_id}/modules"
        )))
        .respond_with(ResponseTemplate::new(403).set_body_json(json!({
            "error": {
                "code": "FEATURE_NOT_AVAILABLE",
                "message": "feature not entitled by current plan"
            }
        })))
        .mount(&billing)
        .await;

    let (status, json) = send(
        state.clone(),
        axum::http::Method::PUT,
        &format!("/api/v1/platform/tenants/{tenant_id}/modules"),
        &operator_token(),
        json!({ "feature_code": "academic_config", "enabled": true }),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(
        json["error"]["code"], "FEATURE_NOT_AVAILABLE",
        "billing's domain code must not be rewritten"
    );

    let count: (i64,) = sqlx::query_as("SELECT count(*) FROM operator_audit")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count.0, 0, "no audit row on failure");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration module`
Expected: FAIL — routes missing (404), and the entitlement assertions fail.

- [ ] **Step 3: Add the plan catalog lookup**

In `apps/backend/services/platform-service/src/repo.rs`, add the row type next
to the other row structs:

```rust
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PlanCatalogRow {
    pub code: String,
    pub name: String,
    pub active: bool,
    pub features: Value,
}
```

And the query inside `impl PlatformProjectionRepo`:

```rust
    pub async fn get_plan_catalog_entry(
        &self,
        code: &str,
    ) -> Result<Option<PlanCatalogRow>, sqlx::Error> {
        sqlx::query_as::<_, PlanCatalogRow>(
            r#"
            SELECT code, name, active, features
              FROM platform_plan_catalog
             WHERE code = $1
            "#,
        )
        .bind(code)
        .fetch_optional(&self.pool)
        .await
    }
```

- [ ] **Step 4: Fix the downstream error mapping**

In `apps/backend/services/platform-service/src/http.rs`, replace the body of
`map_downstream_error` so domain codes from billing pass through untouched:

```rust
fn map_downstream_error(status: StatusCode, value: Value) -> AppError {
    let code = value
        .pointer("/error/code")
        .and_then(Value::as_str)
        .unwrap_or("DOWNSTREAM_ERROR");
    let message = value
        .pointer("/error/message")
        .and_then(Value::as_str)
        .unwrap_or("billing-service request failed");
    match status {
        // Billing's domain codes are part of the platform contract; preserve
        // them rather than flattening to a generic downstream code.
        StatusCode::FORBIDDEN
            if matches!(code, "FEATURE_NOT_AVAILABLE" | "SUBSCRIPTION_EXPIRED") =>
        {
            AppError::forbidden(code, message)
        }
        StatusCode::CONFLICT if code == "PLAN_CODE_EXISTS" => {
            AppError::conflict("PLAN_CODE_EXISTS", message)
        }
        StatusCode::CONFLICT => AppError::conflict(code, message),
        StatusCode::BAD_REQUEST if code == "VALIDATION_ERROR" => {
            AppError::validation_error_single("request", message)
        }
        StatusCode::BAD_REQUEST => AppError::bad_request("DOWNSTREAM_BAD_REQUEST", message),
        StatusCode::UNAUTHORIZED => AppError::unauthenticated("UNAUTHORIZED_SERVICE_CALL", message),
        StatusCode::FORBIDDEN => AppError::forbidden("DOWNSTREAM_FORBIDDEN", message),
        StatusCode::NOT_FOUND => AppError::not_found(message),
        _ => AppError::bad_request("DOWNSTREAM_ERROR", message),
    }
}
```

Check `AppError::conflict`'s signature in `apps/backend/libs/common-errors/src/lib.rs`
before assuming it accepts a dynamic code; if it takes `&'static str`, keep the
`PLAN_CODE_EXISTS` arm and drop the generic `CONFLICT` arm.

- [ ] **Step 5: Add the routes and handlers**

In `router()`, after the `/tenants/:tenant_id/subscription` route:

```rust
        .route(
            "/api/v1/platform/tenants/:tenant_id/modules",
            get(list_tenant_modules).put(toggle_tenant_module),
        )
```

Add the handlers near `override_subscription`:

```rust
#[derive(Debug, Deserialize)]
struct ToggleModuleBody {
    feature_code: String,
    enabled: bool,
}

async fn list_tenant_modules(
    State(state): State<AppState>,
    auth: PlatformAuthContext,
    Path(tenant_id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    require_platform_admin(&auth)?;
    let subscription = state
        .projection_repo
        .get_subscription(tenant_id)
        .await
        .map_err(AppError::internal)?;

    let enabled_map = subscription
        .as_ref()
        .and_then(|s| s.modules.as_object().cloned())
        .unwrap_or_default();

    let entitled_map = match subscription.as_ref() {
        Some(s) => state
            .projection_repo
            .get_plan_catalog_entry(&s.plan_code)
            .await
            .map_err(AppError::internal)?
            .and_then(|p| p.features.as_object().cloned())
            .unwrap_or_default(),
        None => serde_json::Map::new(),
    };

    // Union of both key sets so the operator sees entitled-but-off features
    // as well as anything switched on outside the current plan.
    let mut codes: Vec<String> = entitled_map
        .keys()
        .chain(enabled_map.keys())
        .cloned()
        .collect();
    codes.sort();
    codes.dedup();

    let modules: Vec<Value> = codes
        .into_iter()
        .map(|code| {
            let enabled = enabled_map
                .get(&code)
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let entitled = entitled_map
                .get(&code)
                .and_then(Value::as_bool)
                .unwrap_or(false);
            json!({ "code": code, "enabled": enabled, "entitled": entitled })
        })
        .collect();

    Ok(Json(json!({ "data": { "modules": modules }, "meta": {} })))
}

async fn toggle_tenant_module(
    State(state): State<AppState>,
    auth: PlatformAuthContext,
    Path(tenant_id): Path<Uuid>,
    Json(body): Json<ToggleModuleBody>,
) -> Result<Json<Value>, AppError> {
    require_platform_admin(&auth)?;
    let value = forward_to_billing(
        &state,
        reqwest::Method::PATCH,
        &format!("/api/v1/billing/internal/tenants/{tenant_id}/modules"),
        Some(json!({
            "feature_code": body.feature_code,
            "enabled": body.enabled,
        })),
    )
    .await?;
    write_audit(
        &state,
        auth.user_id,
        "tenant.module_toggle",
        "tenant",
        tenant_id,
        &json!({
            "feature_code": body.feature_code,
            "enabled": body.enabled,
        }),
    )
    .await?;
    Ok(Json(value))
}
```

`forward_to_billing` returns `Err` on any non-2xx, so `write_audit` is
unreachable on failure — that is what satisfies the "audit only after 2xx"
requirement.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/backend && cargo test -p platform-service --test integration module`
Expected: 5 passed (3 from this task, 2 from Task 3).

- [ ] **Step 7: Verify the whole service**

Run: `cd apps/backend && cargo test -p platform-service && cargo clippy -p platform-service -- -D warnings`
Expected: all pass. Existing plan tests must still pass — the `PLAN_CODE_EXISTS`
mapping was preserved deliberately.

- [ ] **Step 8: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/platform-service/src/repo.rs \
        apps/backend/services/platform-service/src/http.rs \
        apps/backend/services/platform-service/tests/integration.rs
git commit -m "feat(platform): add tenant module read and toggle endpoints"
```

---

### Task 5: Failed-registration listing (billing endpoint + platform proxy)

**Files:**
- Modify: `apps/backend/services/billing-service/src/queries.rs` (add `list_pending_registrations`)
- Modify: `apps/backend/services/billing-service/src/http.rs` (internal route + handler)
- Modify: `apps/backend/services/platform-service/src/http.rs` (proxy route + handler)
- Test: `apps/backend/services/billing-service/tests/integration.rs`, `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: existing `forward_to_billing`, `ServiceToken`, `pagination`.
- Produces:
  - `GET /api/v1/billing/internal/registrations?state=&page=&page_size=` (X-Service-Token)
  - `GET /api/v1/platform/registrations?state=&page=&page_size=`
  - Both return `{ "data": [{ registration_id, email, iam_user_id, tenant_id, state, attempted_at }], "meta": { page, page_size } }`

Design note: no projection. `pending_registration` lives in `billing_db`, is
low-volume, and its whole value is freshness — a stale projection of stuck
registrations would be worse than useless. platform-service proxies over
`X-Service-Token`, the same pattern already used for `GET /plans`.

If `apps/backend/services/billing-service/src/queries.rs` does not exist, put
the query function in the module where the other read functions live; check
`get_school_profile`'s home first and follow it.

- [ ] **Step 1: Write the failing billing test**

Append to `apps/backend/services/billing-service/tests/integration.rs`:

```rust
#[tokio::test]
async fn internal_registrations_lists_and_filters_by_state() {
    let (pool, state, _c) = boot().await;

    for (email, reg_state) in [
        ("stuck@example.com", "user_created"),
        ("done@example.com", "completed"),
        ("broken@example.com", "failed"),
    ] {
        sqlx::query(
            r#"
            INSERT INTO pending_registration (registration_id, email, state, attempted_at)
            VALUES (gen_random_uuid(), $1, $2, now())
            "#,
        )
        .bind(email)
        .bind(reg_state)
        .execute(&pool)
        .await
        .unwrap();
    }

    let all = billing_service::queries::list_pending_registrations(&state, None, 20, 0)
        .await
        .expect("list all");
    assert_eq!(all.len(), 3);

    let failed =
        billing_service::queries::list_pending_registrations(&state, Some("failed"), 20, 0)
            .await
            .expect("list failed");
    assert_eq!(failed.len(), 1);
    assert_eq!(failed[0].email, "broken@example.com");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p billing-service --test integration internal_registrations`
Expected: FAIL to compile — `list_pending_registrations` does not exist.

- [ ] **Step 3: Add the billing query**

```rust
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct PendingRegistrationRow {
    pub registration_id: Uuid,
    pub email: String,
    pub iam_user_id: Option<Uuid>,
    pub tenant_id: Option<Uuid>,
    pub state: String,
    pub attempted_at: DateTime<Utc>,
}

pub async fn list_pending_registrations(
    state: &AppState,
    filter: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<PendingRegistrationRow>, AppError> {
    sqlx::query_as::<_, PendingRegistrationRow>(
        r#"
        SELECT registration_id, email, iam_user_id, tenant_id, state, attempted_at
          FROM pending_registration
         WHERE ($1::text IS NULL OR state = $1)
         ORDER BY attempted_at DESC
         LIMIT $2 OFFSET $3
        "#,
    )
    .bind(filter)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.pool)
    .await
    .map_err(AppError::internal)
}
```

Add whatever imports the file is missing (`chrono::{DateTime, Utc}`,
`serde::Serialize`, `uuid::Uuid`).

- [ ] **Step 4: Add the billing internal route and handler**

Route, added to the internal endpoint group in `router()` (Task 2 adds an
`internal/tenants/:id/modules` route to the same group; place this one after it
if present, otherwise after `internal/tenants/:id/reactivate`):

```rust
        .route(
            "/api/v1/billing/internal/registrations",
            get(internal_list_registrations_handler),
        )
```

Handler:

```rust
#[derive(Debug, Deserialize)]
struct RegistrationQuery {
    state: Option<String>,
    page: Option<u32>,
    page_size: Option<u32>,
}

async fn internal_list_registrations_handler(
    State(state): State<AppState>,
    _token: ServiceToken,
    Query(query): Query<RegistrationQuery>,
) -> Result<Json<Value>, AppError> {
    let page = query.page.unwrap_or(1).max(1);
    let page_size = query.page_size.unwrap_or(20).clamp(1, 100);
    let offset = (page - 1) * page_size;
    let filter = query.state.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let rows =
        list_pending_registrations(&state, filter, page_size as i64, offset as i64).await?;
    Ok(Json(json!({
        "data": rows,
        "meta": { "page": page, "page_size": page_size }
    })))
}
```

- [ ] **Step 5: Write the failing platform proxy test**

Append to `apps/backend/services/platform-service/tests/integration.rs`:

```rust
#[tokio::test]
async fn registrations_proxy_forwards_state_filter() {
    let (_pool, state, billing, _c) = boot().await;

    Mock::given(method("GET"))
        .and(path("/api/v1/billing/internal/registrations"))
        .and(header_exists("X-Service-Token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "data": [{
                "registration_id": "11111111-1111-1111-1111-111111111111",
                "email": "stuck@example.com",
                "iam_user_id": null,
                "tenant_id": null,
                "state": "user_created",
                "attempted_at": "2026-09-12T00:00:00Z"
            }],
            "meta": { "page": 1, "page_size": 20 }
        })))
        .mount(&billing)
        .await;

    let (status, json) = get(
        state.clone(),
        "/api/v1/platform/registrations?state=user_created",
        &operator_token(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"][0]["email"], "stuck@example.com");
    assert_eq!(json["data"][0]["state"], "user_created");
}

#[tokio::test]
async fn registrations_requires_platform_admin() {
    let (_pool, state, _billing, _c) = boot().await;
    let (status, _json) = get(
        state.clone(),
        "/api/v1/platform/registrations",
        &platform_token(&["support"]),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration registrations`
Expected: FAIL — route missing, 404 instead of 200.

- [ ] **Step 7: Add the platform proxy route and handler**

Route, after the `/audit` route:

```rust
        .route("/api/v1/platform/registrations", get(list_registrations))
```

Handler:

```rust
#[derive(Debug, Deserialize)]
struct RegistrationQuery {
    state: Option<String>,
    page: Option<u32>,
    page_size: Option<u32>,
}

async fn list_registrations(
    State(app_state): State<AppState>,
    auth: PlatformAuthContext,
    Query(query): Query<RegistrationQuery>,
) -> Result<Json<Value>, AppError> {
    require_platform_admin(&auth)?;
    let (page, page_size, _offset) = pagination(query.page, query.page_size);
    let mut path = format!("/api/v1/billing/internal/registrations?page={page}&page_size={page_size}");
    if let Some(filter) = query.state.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        path.push_str(&format!("&state={}", urlencoding::encode(filter)));
    }
    let value = forward_to_billing(&app_state, reqwest::Method::GET, &path, None).await?;
    Ok(Json(value))
}
```

If `urlencoding` is not already a dependency of platform-service, do not add it
— the `state` values are a closed set (`user_created`, `tenant_created`,
`completed`, `failed`). Reject anything else with
`AppError::validation_error_single("state", "unknown registration state")` and
interpolate the validated value directly. Prefer this; it avoids a new
dependency and is stricter.

- [ ] **Step 8: Run both suites**

Run: `cd apps/backend && cargo test -p billing-service --test integration internal_registrations && cargo test -p platform-service --test integration registrations`
Expected: 3 passed total.

- [ ] **Step 9: Verify and lint**

Run: `cd apps/backend && cargo clippy -p billing-service -p platform-service -- -D warnings`
Expected: no warnings.

- [ ] **Step 10: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/billing-service/src \
        apps/backend/services/billing-service/tests/integration.rs \
        apps/backend/services/platform-service/src/http.rs \
        apps/backend/services/platform-service/tests/integration.rs
git commit -m "feat(platform): expose pending registration listing via billing proxy"
```

---

### Task 6: Service health fan-out endpoint

**Files:**
- Modify: `apps/backend/services/platform-service/Cargo.toml` (add `futures-util`)
- Modify: `apps/backend/services/platform-service/src/state.rs` (add `service_health_targets`)
- Modify: `apps/backend/services/platform-service/src/config.rs` (read target URLs from env)
- Modify: `apps/backend/services/platform-service/src/main.rs` (populate the targets)
- Modify: `apps/backend/services/platform-service/src/http.rs` (route + handler)
- Modify: `apps/backend/.env.example` (document the new variables)
- Test: `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: `state.http_client`.
- Produces: `GET /api/v1/platform/health` returning
  `{ "data": { "services": [{ "name": String, "status": "up"|"down", "latency_ms": u64|null }] }, "meta": {} }`

Design note: this is the one endpoint where a synchronous cross-service call is
correct — checking liveness is the entire purpose. Each probe gets a 2-second
timeout and they run concurrently, so the endpoint's worst case stays ~2s.

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn health_reports_up_and_down_services() {
    let (_pool, mut state, billing, _c) = boot().await;

    let healthy = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/healthz"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "data": { "status": "ok" }, "meta": {}
        })))
        .mount(&healthy)
        .await;

    let broken = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/healthz"))
        .respond_with(ResponseTemplate::new(503))
        .mount(&broken)
        .await;

    state.service_health_targets = vec![
        ("iam".to_string(), healthy.uri()),
        ("grading".to_string(), broken.uri()),
    ];
    let _ = &billing;

    let (status, json) = get(state.clone(), "/api/v1/platform/health", &operator_token()).await;

    assert_eq!(status, StatusCode::OK);
    let services = json["data"]["services"].as_array().unwrap();
    let iam = services.iter().find(|s| s["name"] == "iam").unwrap();
    assert_eq!(iam["status"], "up");
    let grading = services.iter().find(|s| s["name"] == "grading").unwrap();
    assert_eq!(grading["status"], "down");
}

#[tokio::test]
async fn health_marks_unreachable_service_down() {
    let (_pool, mut state, _billing, _c) = boot().await;
    // Port 1 is reserved and refuses connections immediately.
    state.service_health_targets = vec![("ghost".to_string(), "http://127.0.0.1:1".to_string())];

    let (status, json) = get(state.clone(), "/api/v1/platform/health", &operator_token()).await;

    assert_eq!(status, StatusCode::OK, "one dead service must not 500 the board");
    assert_eq!(json["data"]["services"][0]["status"], "down");
    assert!(json["data"]["services"][0]["latency_ms"].is_null());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration health_`
Expected: FAIL to compile — `service_health_targets` does not exist on `AppState`.

- [ ] **Step 3: Add the field to AppState**

In `apps/backend/services/platform-service/src/state.rs`, add to the struct:

```rust
    pub service_health_targets: Vec<(String, String)>,
```

And initialise it in `AppState::new`'s returned struct literal:

```rust
            service_health_targets: Vec::new(),
```

Keeping `new()`'s signature unchanged means every existing caller and test
still compiles; `main.rs` populates the field after construction.

- [ ] **Step 4: Populate targets from config**

In `apps/backend/services/platform-service/src/config.rs`, add a function that
reads one base URL per service from the environment, defaulting to the local
dev ports documented in the root `AGENTS.md`:

```rust
/// Base URLs probed by `GET /api/v1/platform/health`, as (name, base_url).
/// Each entry is overridable via `<NAME>_BASE_URL`.
pub fn service_health_targets() -> Vec<(String, String)> {
    [
        ("iam", "http://localhost:8081"),
        ("billing", "http://localhost:8082"),
        ("academic-config", "http://localhost:8083"),
        ("academic-ops", "http://localhost:8084"),
        ("grading", "http://localhost:8086"),
        ("platform", "http://localhost:8087"),
    ]
    .into_iter()
    .map(|(name, default)| {
        let key = format!(
            "{}_BASE_URL",
            name.to_uppercase().replace('-', "_")
        );
        let url = std::env::var(&key).unwrap_or_else(|_| default.to_string());
        (name.to_string(), url)
    })
    .collect()
}
```

In `apps/backend/services/platform-service/src/main.rs`, after building the
state, set the field:

```rust
    state.service_health_targets = config::service_health_targets();
```

Make the `state` binding `mut`. Then add to `apps/backend/.env.example`, under
the existing service port section:

```
# Base URLs probed by platform-service's GET /api/v1/platform/health.
# Defaults match the local dev ports; override in containerised environments.
# IAM_BASE_URL=http://iam-service:8081
# BILLING_BASE_URL=http://billing-service:8082
# ACADEMIC_CONFIG_BASE_URL=http://academic-config-service:8083
# ACADEMIC_OPS_BASE_URL=http://academic-ops-service:8084
# GRADING_BASE_URL=http://grading-service:8086
# PLATFORM_BASE_URL=http://platform-service:8087
```

- [ ] **Step 5: Add the route and handler**

Route, after `/overview`:

```rust
        .route("/api/v1/platform/health", get(get_service_health))
```

Handler:

```rust
async fn get_service_health(
    State(state): State<AppState>,
    auth: PlatformAuthContext,
) -> Result<Json<Value>, AppError> {
    require_platform_admin(&auth)?;

    let probes = state.service_health_targets.iter().map(|(name, base)| {
        let client = state.http_client.clone();
        let url = format!("{}/healthz", base.trim_end_matches('/'));
        let name = name.clone();
        async move {
            let started = std::time::Instant::now();
            let outcome = client
                .get(&url)
                .timeout(std::time::Duration::from_secs(2))
                .send()
                .await;
            let (status, latency) = match outcome {
                Ok(resp) if resp.status().is_success() => {
                    ("up", Some(started.elapsed().as_millis() as u64))
                }
                _ => ("down", None),
            };
            json!({ "name": name, "status": status, "latency_ms": latency })
        }
    });

    let services: Vec<Value> = futures_util::future::join_all(probes).await;
    Ok(Json(json!({ "data": { "services": services }, "meta": {} })))
}
```

Dependency: the workspace root `apps/backend/Cargo.toml` declares
`futures-util = "0.3"`, but platform-service does not yet depend on it. Add to
`apps/backend/services/platform-service/Cargo.toml` under `[dependencies]`:

```toml
futures-util = { workspace = true }
```

If the workspace does not expose it under `[workspace.dependencies]`, use
`futures-util = "0.3"` instead. Do **not** probe sequentially — that serialises
a 12-second worst case.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/backend && cargo test -p platform-service --test integration health_`
Expected: 2 passed.

- [ ] **Step 7: Verify and lint**

Run: `cd apps/backend && cargo test -p platform-service && cargo clippy -p platform-service -- -D warnings`
Expected: all pass.

- [ ] **Step 8: Commit (only if the user asked for commits)**

```bash
git add apps/backend/services/platform-service/src \
        apps/backend/services/platform-service/tests/integration.rs \
        apps/backend/.env.example
git commit -m "feat(platform): add service health fan-out endpoint"
```

---

### Task 7: Subscription card on tenant detail (UI)

**Files:**
- Modify: `apps/web-admin/app/lib/api/types.ts` (add `TenantSubscription`)
- Modify: `apps/web-admin/app/lib/queries/tenants.ts` (add `useTenantSubscriptionQuery`)
- Create: `apps/web-admin/app/components/subscription-expiry.ts`
- Create: `apps/web-admin/app/components/SubscriptionCard.vue`
- Modify: `apps/web-admin/app/pages/tenants/[id].vue` (render the card)
- Test: `apps/web-admin/tests/unit/subscription-card.spec.ts`

**Interfaces:**
- Consumes: `GET /tenants/:id/subscription` from Task 1.
- Produces: `useTenantSubscriptionQuery(id)`, `tenantKeys.subscription(id)`, and `<SubscriptionCard>`.

Note: `TenantDetail` in `types.ts` already declares an optional `subscription`
field with a `renews_at` key. That shape was speculative and is **not** what the
endpoint returns. Leave `TenantDetail` alone (other code may read it) and add a
separate, accurate type.

- [ ] **Step 1: Add the type**

In `apps/web-admin/app/lib/api/types.ts`, after `TenantDetail`:

```ts
export type TenantSubscription = {
  tenant_id: string
  plan_code: string
  status: string
  modules: Record<string, boolean>
  started_at: string | null
  ends_at: string | null
}
```

- [ ] **Step 2: Write the failing test**

Create `apps/web-admin/tests/unit/subscription-card.spec.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { expiryWarning } from '~/components/subscription-expiry'

describe('expiryWarning', () => {
  it('returns null when there is no end date', () => {
    expect(expiryWarning(null, new Date('2026-09-12T00:00:00Z'))).toBeNull()
  })

  it('warns when the subscription ends within 30 days', () => {
    const result = expiryWarning('2026-10-01T00:00:00Z', new Date('2026-09-12T00:00:00Z'))
    expect(result).toEqual({ level: 'warning', days: 19 })
  })

  it('flags an already expired subscription as an error', () => {
    const result = expiryWarning('2026-09-01T00:00:00Z', new Date('2026-09-12T00:00:00Z'))
    expect(result).toEqual({ level: 'error', days: -11 })
  })

  it('stays silent when the end date is far away', () => {
    expect(expiryWarning('2027-01-01T00:00:00Z', new Date('2026-09-12T00:00:00Z'))).toBeNull()
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/subscription-card.spec.ts`
Expected: FAIL — module `~/components/subscription-expiry` not found.

- [ ] **Step 4: Implement the pure helper**

Create `apps/web-admin/app/components/subscription-expiry.ts`:

```ts
export type ExpiryWarning = { level: 'warning' | 'error'; days: number }

const DAY_MS = 24 * 60 * 60 * 1000

/**
 * Returns a warning when a subscription ends within 30 days, or an error when
 * it has already lapsed. A null `endsAt` means an open-ended subscription,
 * which is never a warning.
 */
export function expiryWarning(endsAt: string | null, now: Date = new Date()): ExpiryWarning | null {
  if (!endsAt) return null
  const days = Math.round((new Date(endsAt).getTime() - now.getTime()) / DAY_MS)
  if (days < 0) return { level: 'error', days }
  if (days <= 30) return { level: 'warning', days }
  return null
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/subscription-card.spec.ts`
Expected: 4 passed.

- [ ] **Step 6: Add the query hook**

In `apps/web-admin/app/lib/queries/tenants.ts`, extend `tenantKeys`:

```ts
  subscription: (id: string) => ['tenants', 'subscription', id] as const,
```

Add the import of `TenantSubscription` to the existing `import type { ... }`
line, then append the hook:

```ts
export function useTenantSubscriptionQuery(id: MaybeRefOrGetter<string>) {
  return useQuery<TenantSubscription | null, ApiHttpError>({
    queryKey: computed(() => tenantKeys.subscription(toValue(id))),
    queryFn: () =>
      apiFetch<TenantSubscription | null>({
        service: 'platform',
        path: `/tenants/${toValue(id)}/subscription`,
        authenticated: true,
      }),
    enabled: computed(() => Boolean(toValue(id))),
  })
}
```

- [ ] **Step 7: Build the card component**

Create `apps/web-admin/app/components/SubscriptionCard.vue`:

```vue
<script setup lang="ts">
import type { TenantSubscription } from '~/lib/api/types'
import { expiryWarning } from '~/components/subscription-expiry'

const props = defineProps<{
  subscription: TenantSubscription | null | undefined
  loading?: boolean
}>()

const warning = computed(() => expiryWarning(props.subscription?.ends_at ?? null))

function formatDate(value: string | null): string {
  if (!value) return '—'
  return new Date(value).toLocaleDateString()
}
</script>

<template>
  <UCard>
    <template #header>
      <h2 class="text-base font-semibold text-highlighted">Subscription</h2>
    </template>

    <RegionSkeleton v-if="loading" :rows="3" />

    <EmptyState
      v-else-if="!subscription"
      title="No subscription on record"
      message="This tenant has no subscription in the platform projection yet."
    />

    <div v-else class="flex flex-col gap-3">
      <UAlert
        v-if="warning"
        :color="warning.level === 'error' ? 'error' : 'warning'"
        :title="warning.level === 'error'
          ? `Expired ${Math.abs(warning.days)} day(s) ago`
          : `Ends in ${warning.days} day(s)`"
      />

      <dl class="grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt class="text-muted">Plan</dt>
          <dd class="font-medium text-highlighted">{{ subscription.plan_code }}</dd>
        </div>
        <div>
          <dt class="text-muted">Status</dt>
          <dd><StatusBadge :status="subscription.status" /></dd>
        </div>
        <div>
          <dt class="text-muted">Started</dt>
          <dd class="font-mono text-xs">{{ formatDate(subscription.started_at) }}</dd>
        </div>
        <div>
          <dt class="text-muted">Ends</dt>
          <dd class="font-mono text-xs">
            {{ subscription.ends_at ? formatDate(subscription.ends_at) : 'No end date' }}
          </dd>
        </div>
      </dl>
    </div>
  </UCard>
</template>
```

- [ ] **Step 8: Render it on the tenant detail page**

In `apps/web-admin/app/pages/tenants/[id].vue`, add to the imports:

```ts
import { useTenantDetailQuery, useTenantUsageQuery, useTenantSubscriptionQuery } from '~/lib/queries/tenants'
```

Add below the existing `usage` query:

```ts
const { data: subscription, isPending: subscriptionPending } = useTenantSubscriptionQuery(tenantId)
```

And place the card in the template, inside the loaded branch alongside the
other cards:

```vue
      <SubscriptionCard :subscription="subscription" :loading="subscriptionPending" />
```

- [ ] **Step 9: Verify lint, types, and tests**

Run: `cd apps/web-admin && pnpm lint && pnpm vitest run`
Expected: no lint errors, all unit tests pass.

- [ ] **Step 10: Manual check**

Run: `make dev-backend` in one shell and `cd apps/web-admin && pnpm dev` in
another. Sign in, open a tenant detail page, and confirm the card renders both
for a tenant with a subscription and one without.

- [ ] **Step 11: Commit (only if the user asked for commits)**

```bash
git add apps/web-admin/app apps/web-admin/tests/unit/subscription-card.spec.ts
git commit -m "feat(web-admin): show tenant subscription card on detail page"
```

---

### Task 8: Tenant module panel (UI)

**Files:**
- Modify: `apps/web-admin/app/lib/api/types.ts` (add `TenantModule`)
- Modify: `apps/web-admin/app/lib/queries/tenants.ts` (add `useTenantModulesQuery`)
- Modify: `apps/web-admin/app/lib/mutations/tenants.ts` (add `useToggleModuleMutation`)
- Modify: `apps/web-admin/app/lib/errors/messages.ts` (add two codes)
- Create: `apps/web-admin/app/components/module-ordering.ts`
- Create: `apps/web-admin/app/components/ModulePanel.vue`
- Modify: `apps/web-admin/app/pages/tenants/[id].vue`
- Test: `apps/web-admin/tests/unit/module-panel.spec.ts`

**Interfaces:**
- Consumes: `GET`/`PUT /tenants/:id/modules` from Task 4.
- Produces: `useTenantModulesQuery(id)`, `useToggleModuleMutation(tenantId)`, `<ModulePanel>`.

- [ ] **Step 1: Add the type**

In `apps/web-admin/app/lib/api/types.ts`:

```ts
export type TenantModule = {
  code: string
  enabled: boolean
  entitled: boolean
}
```

- [ ] **Step 2: Add the error messages**

In `apps/web-admin/app/lib/errors/messages.ts`, add to `ERROR_MESSAGES`:

```ts
  FEATURE_NOT_AVAILABLE: 'This feature is not included in the tenant\u2019s current plan.',
  SUBSCRIPTION_EXPIRED: 'The tenant has no active subscription, so modules cannot be changed.',
```

- [ ] **Step 3: Write the failing test**

Create `apps/web-admin/tests/unit/module-panel.spec.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { sortModules } from '~/components/module-ordering'
import type { TenantModule } from '~/lib/api/types'

const mod = (code: string, enabled: boolean, entitled: boolean): TenantModule => ({
  code,
  enabled,
  entitled,
})

describe('sortModules', () => {
  it('lists entitled modules before unentitled ones', () => {
    const result = sortModules([
      mod('zeta', false, false),
      mod('alpha', false, true),
    ])
    expect(result.map((m) => m.code)).toEqual(['alpha', 'zeta'])
  })

  it('sorts alphabetically within the same entitlement group', () => {
    const result = sortModules([
      mod('grading', true, true),
      mod('academic_config', false, true),
    ])
    expect(result.map((m) => m.code)).toEqual(['academic_config', 'grading'])
  })

  it('does not mutate the input array', () => {
    const input = [mod('b', false, false), mod('a', false, true)]
    sortModules(input)
    expect(input.map((m) => m.code)).toEqual(['b', 'a'])
  })
})
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/module-panel.spec.ts`
Expected: FAIL — module `~/components/module-ordering` not found.

- [ ] **Step 5: Implement the pure helper**

Create `apps/web-admin/app/components/module-ordering.ts`:

```ts
import type { TenantModule } from '~/lib/api/types'

/**
 * Entitled modules first (those are the actionable ones), then alphabetical
 * within each group. Returns a new array; the input is left untouched.
 */
export function sortModules(modules: TenantModule[]): TenantModule[] {
  return [...modules].sort((a, b) => {
    if (a.entitled !== b.entitled) return a.entitled ? -1 : 1
    return a.code.localeCompare(b.code)
  })
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/module-panel.spec.ts`
Expected: 3 passed.

- [ ] **Step 7: Add the query hook**

In `apps/web-admin/app/lib/queries/tenants.ts`, extend `tenantKeys`:

```ts
  modules: (id: string) => ['tenants', 'modules', id] as const,
```

Then append:

```ts
export function useTenantModulesQuery(id: MaybeRefOrGetter<string>) {
  return useQuery<TenantModule[], ApiHttpError>({
    queryKey: computed(() => tenantKeys.modules(toValue(id))),
    queryFn: async () => {
      const raw = await apiFetch<{ modules: TenantModule[] }>({
        service: 'platform',
        path: `/tenants/${toValue(id)}/modules`,
        authenticated: true,
      })
      return raw.modules
    },
    enabled: computed(() => Boolean(toValue(id))),
  })
}
```

Add `TenantModule` to the file's `import type` list.

- [ ] **Step 8: Add the mutation**

In `apps/web-admin/app/lib/mutations/tenants.ts`:

```ts
export function useToggleModuleMutation(tenantId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: { feature_code: string; enabled: boolean }) =>
      apiFetch<{ ok: boolean }>({
        service: 'platform',
        path: `/tenants/${tenantId}/modules`,
        method: 'PUT',
        body: input,
        authenticated: true,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.modules(tenantId) })
      queryClient.invalidateQueries({ queryKey: tenantKeys.subscription(tenantId) })
    },
  })
}
```

- [ ] **Step 9: Build the panel component**

Create `apps/web-admin/app/components/ModulePanel.vue`:

```vue
<script setup lang="ts">
import type { TenantModule } from '~/lib/api/types'
import { sortModules } from '~/components/module-ordering'
import { useToggleModuleMutation } from '~/lib/mutations/tenants'
import { getErrorMessage } from '~/lib/errors/messages'

const props = defineProps<{
  tenantId: string
  modules: TenantModule[] | undefined
  loading?: boolean
}>()

const toast = useToast()
const mutation = useToggleModuleMutation(props.tenantId)
const pendingCode = ref<string | null>(null)

const ordered = computed(() => sortModules(props.modules ?? []))

function onToggle(module: TenantModule, enabled: boolean) {
  pendingCode.value = module.code
  mutation.mutate(
    { feature_code: module.code, enabled },
    {
      onSuccess: () => {
        pendingCode.value = null
        toast.add({
          title: enabled ? `Enabled ${module.code}` : `Disabled ${module.code}`,
          color: 'success',
        })
      },
      onError: (e) => {
        pendingCode.value = null
        toast.add({
          title: 'Module change failed',
          description: getErrorMessage(e, { fallback: 'Could not change the module.' }),
          color: 'error',
        })
      },
    },
  )
}
</script>

<template>
  <UCard>
    <template #header>
      <h2 class="text-base font-semibold text-highlighted">Modules</h2>
      <p class="mt-0.5 text-sm text-muted">
        Features outside the tenant&rsquo;s plan cannot be switched on.
      </p>
    </template>

    <RegionSkeleton v-if="loading" :rows="4" />

    <EmptyState
      v-else-if="ordered.length === 0"
      title="No modules"
      message="This tenant has no plan features on record."
    />

    <ul v-else class="flex flex-col gap-3">
      <li
        v-for="module in ordered"
        :key="module.code"
        class="flex items-center justify-between gap-3"
      >
        <div class="min-w-0">
          <p class="truncate text-sm font-medium text-highlighted">{{ module.code }}</p>
          <p v-if="!module.entitled" class="text-xs text-muted">Not included in the current plan</p>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <AppLoadingSpinner v-if="pendingCode === module.code" size="xs" />
          <USwitch
            :model-value="module.enabled"
            :disabled="!module.entitled || pendingCode !== null"
            @update:model-value="(value: boolean) => onToggle(module, value)"
          />
        </div>
      </li>
    </ul>
  </UCard>
</template>
```

- [ ] **Step 10: Render it on the tenant detail page**

Add to the script in `apps/web-admin/app/pages/tenants/[id].vue`:

```ts
const { data: modules, isPending: modulesPending } = useTenantModulesQuery(tenantId)
```

extending the existing import from `~/lib/queries/tenants` with
`useTenantModulesQuery`. Then in the template, next to `SubscriptionCard`:

```vue
      <ModulePanel :tenant-id="tenantId" :modules="modules" :loading="modulesPending" />
```

- [ ] **Step 11: Verify lint, types, and tests**

Run: `cd apps/web-admin && pnpm lint && pnpm vitest run`
Expected: all pass. In particular, ESLint must not flag a native control —
the panel uses `USwitch`, not `<input type="checkbox">`.

- [ ] **Step 12: Commit (only if the user asked for commits)**

```bash
git add apps/web-admin/app apps/web-admin/tests/unit/module-panel.spec.ts
git commit -m "feat(web-admin): add tenant module entitlement panel"
```

---

### Task 9: Failed-registration board (UI)

**Files:**
- Modify: `apps/web-admin/app/lib/api/types.ts` (add `PendingRegistration`)
- Create: `apps/web-admin/app/lib/queries/registration-stall.ts`
- Create: `apps/web-admin/app/lib/queries/registrations.ts`
- Create: `apps/web-admin/app/pages/registrations/index.vue`
- Modify: `apps/web-admin/app/layouts/default.vue` (nav entry)
- Test: `apps/web-admin/tests/unit/registrations.spec.ts`, `apps/web-admin/tests/e2e/operator-flow.spec.ts`

**Interfaces:**
- Consumes: `GET /platform/registrations` from Task 5.
- Produces: `useRegistrationsQuery(page, pageSize, state)`, `registrationKeys`, route `/registrations`.

This board is read-only in Phase 1. Retry and clear actions arrive in Phase 2;
do not add mutate controls here.

- [ ] **Step 1: Add the type**

In `apps/web-admin/app/lib/api/types.ts`:

```ts
export type RegistrationState = 'user_created' | 'tenant_created' | 'completed' | 'failed'

export type PendingRegistration = {
  registration_id: string
  email: string
  iam_user_id: string | null
  tenant_id: string | null
  state: RegistrationState
  attempted_at: string
}
```

- [ ] **Step 2: Write the failing test**

Create `apps/web-admin/tests/unit/registrations.spec.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { isStalled, STALL_THRESHOLD_MINUTES } from '~/lib/queries/registration-stall'
import type { PendingRegistration } from '~/lib/api/types'

const reg = (state: PendingRegistration['state'], attemptedAt: string): PendingRegistration => ({
  registration_id: 'r1',
  email: 'a@example.com',
  iam_user_id: null,
  tenant_id: null,
  state,
  attempted_at: attemptedAt,
})

const now = new Date('2026-09-12T12:00:00Z')

describe('isStalled', () => {
  it('flags an in-progress registration older than the threshold', () => {
    expect(isStalled(reg('user_created', '2026-09-12T11:00:00Z'), now)).toBe(true)
  })

  it('does not flag a recent in-progress registration', () => {
    expect(isStalled(reg('user_created', '2026-09-12T11:55:00Z'), now)).toBe(false)
  })

  it('never flags a completed registration however old', () => {
    expect(isStalled(reg('completed', '2020-01-01T00:00:00Z'), now)).toBe(false)
  })

  it('never flags a failed registration as stalled', () => {
    expect(isStalled(reg('failed', '2020-01-01T00:00:00Z'), now)).toBe(false)
  })

  it('uses a 15 minute threshold', () => {
    expect(STALL_THRESHOLD_MINUTES).toBe(15)
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/registrations.spec.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement the pure helper**

Create `apps/web-admin/app/lib/queries/registration-stall.ts`:

```ts
import type { PendingRegistration } from '~/lib/api/types'

export const STALL_THRESHOLD_MINUTES = 15

const IN_PROGRESS: ReadonlyArray<PendingRegistration['state']> = ['user_created', 'tenant_created']

/**
 * A registration is stalled when it is still mid-saga and has not moved for
 * longer than the threshold. Terminal states (`completed`, `failed`) are never
 * stalled — a failure is a separate, already-visible condition.
 */
export function isStalled(registration: PendingRegistration, now: Date = new Date()): boolean {
  if (!IN_PROGRESS.includes(registration.state)) return false
  const ageMinutes = (now.getTime() - new Date(registration.attempted_at).getTime()) / 60_000
  return ageMinutes > STALL_THRESHOLD_MINUTES
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/registrations.spec.ts`
Expected: 5 passed.

- [ ] **Step 6: Add the query module**

Create `apps/web-admin/app/lib/queries/registrations.ts`:

```ts
import { useQuery } from '@tanstack/vue-query'
import type { MaybeRefOrGetter } from 'vue'
import { computed, toValue } from 'vue'
import { apiFetch } from '~/lib/api/client'
import type { ApiHttpError, PendingRegistration } from '~/lib/api/types'

export const registrationKeys = {
  all: ['registrations'] as const,
  list: (page: number, pageSize: number, state: string) =>
    ['registrations', 'list', { page, pageSize, state }] as const,
}

export function useRegistrationsQuery(
  page: MaybeRefOrGetter<number>,
  pageSize: MaybeRefOrGetter<number>,
  state: MaybeRefOrGetter<string>,
) {
  return useQuery<PendingRegistration[], ApiHttpError>({
    queryKey: computed(() =>
      registrationKeys.list(toValue(page), toValue(pageSize), toValue(state)),
    ),
    queryFn: () => {
      const p = toValue(page)
      const ps = toValue(pageSize)
      const s = toValue(state)
      const stateParam = s ? `&state=${encodeURIComponent(s)}` : ''
      return apiFetch<PendingRegistration[]>({
        service: 'platform',
        path: `/registrations?page=${p}&page_size=${ps}${stateParam}`,
        authenticated: true,
      })
    },
    // Operational freshness matters more here than request economy.
    refetchInterval: 60_000,
  })
}
```

- [ ] **Step 7: Build the page**

Create `apps/web-admin/app/pages/registrations/index.vue`:

```vue
<script setup lang="ts">
import { useRegistrationsQuery } from '~/lib/queries/registrations'
import { isStalled } from '~/lib/queries/registration-stall'

useHead({ title: 'Registrations — AkademiQ Admin' })

const page = ref(1)
const pageSize = ref(25)
const stateFilter = ref('')

const { data, isPending } = useRegistrationsQuery(page, pageSize, stateFilter)

const rows = computed(() => data.value ?? [])
const total = computed(() => rows.value.length)
const stalledCount = computed(() => rows.value.filter((r) => isStalled(r)).length)

const stateOptions = [
  { label: 'All states', value: '' },
  { label: 'User created', value: 'user_created' },
  { label: 'Tenant created', value: 'tenant_created' },
  { label: 'Completed', value: 'completed' },
  { label: 'Failed', value: 'failed' },
]
</script>

<template>
  <div class="flex flex-col gap-4">
    <div>
      <h1 class="text-lg font-semibold text-highlighted">Registrations</h1>
      <p class="text-sm text-muted">
        Tenant sign-up attempts and where they stopped. Read only.
      </p>
    </div>

    <UAlert
      v-if="stalledCount > 0"
      color="warning"
      :title="`${stalledCount} registration(s) stuck for over 15 minutes`"
    />

    <DataTableCard title="Pending registrations" :loading="isPending">
      <template #toolbar>
        <USelect v-model="stateFilter" :items="stateOptions" class="w-48" />
      </template>

      <UTable :data="rows" class="w-full">
        <template #state-cell="{ row }">
          <div class="flex items-center gap-2">
            <StatusBadge
              :status="row.original.state === 'completed'
                ? 'active'
                : row.original.state === 'failed'
                  ? 'cancelled'
                  : 'suspended'"
            />
            <UBadge v-if="isStalled(row.original)" color="warning" variant="subtle">stalled</UBadge>
          </div>
        </template>
        <template #attempted_at-cell="{ row }">
          <span class="font-mono text-xs text-muted">
            {{ new Date(row.original.attempted_at).toLocaleString() }}
          </span>
        </template>
      </UTable>

      <EmptyState
        v-if="!isPending && rows.length === 0"
        title="No registrations"
        message="No sign-up attempts match this filter."
      />

      <template #pagination>
        <UPagination v-model:page="page" :items-per-page="pageSize" :total="total" />
      </template>
    </DataTableCard>
  </div>
</template>
```

- [ ] **Step 8: Add the nav entry**

Open `apps/web-admin/app/layouts/default.vue`, find the array of navigation
links, and add an entry pointing at `/registrations` with the label
`Registrations` and icon `i-lucide-user-plus`, placed after the Tenants entry.
Match the exact shape of the neighbouring entries.

- [ ] **Step 9: Extend the e2e flow**

In `apps/web-admin/tests/e2e/operator-flow.spec.ts`, append a test that follows
the existing file's conventions (it skips automatically without
`E2E_OPERATOR_EMAIL` / `E2E_OPERATOR_PASSWORD`):

```ts
test('operator flow: registrations board renders and filters', async ({ page }) => {
  await login(page)

  await page.goto('/registrations')
  await expect(page.getByRole('heading', { name: 'Registrations', exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { level: 2, name: 'Pending registrations' })).toBeVisible()

  // The board is read-only in Phase 1: no destructive controls.
  await expect(page.getByRole('button', { name: /retry|delete|clear/i })).toHaveCount(0)
})
```

- [ ] **Step 10: Verify**

Run: `cd apps/web-admin && pnpm lint && pnpm vitest run`
Expected: all pass.

Then, with the backend stack running:
Run: `cd apps/web-admin && pnpm exec playwright test operator-flow`
Expected: pass, or skip if the operator credentials are not set.

- [ ] **Step 11: Commit (only if the user asked for commits)**

```bash
git add apps/web-admin/app apps/web-admin/tests
git commit -m "feat(web-admin): add failed registration board"
```

---

### Task 10: Service health board (UI)

**Files:**
- Modify: `apps/web-admin/app/lib/api/types.ts` (add `ServiceHealth`)
- Modify: `apps/web-admin/app/lib/queries/observability.ts` (add `useServiceHealthQuery`)
- Create: `apps/web-admin/app/lib/queries/health-summary.ts`
- Create: `apps/web-admin/app/pages/health/index.vue`
- Modify: `apps/web-admin/app/layouts/default.vue` (nav entry)
- Test: `apps/web-admin/tests/unit/health.spec.ts`

**Interfaces:**
- Consumes: `GET /platform/health` from Task 6.
- Produces: `useServiceHealthQuery()`, `healthKeys`, route `/health`.

- [ ] **Step 1: Add the type**

In `apps/web-admin/app/lib/api/types.ts`:

```ts
export type ServiceHealth = {
  name: string
  status: 'up' | 'down'
  latency_ms: number | null
}
```

- [ ] **Step 2: Write the failing test**

Create `apps/web-admin/tests/unit/health.spec.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { summariseHealth } from '~/lib/queries/health-summary'
import type { ServiceHealth } from '~/lib/api/types'

const svc = (name: string, status: 'up' | 'down'): ServiceHealth => ({
  name,
  status,
  latency_ms: status === 'up' ? 12 : null,
})

describe('summariseHealth', () => {
  it('reports all healthy when every service is up', () => {
    const result = summariseHealth([svc('iam', 'up'), svc('billing', 'up')])
    expect(result).toEqual({ total: 2, down: 0, allHealthy: true })
  })

  it('counts the services that are down', () => {
    const result = summariseHealth([svc('iam', 'up'), svc('billing', 'down')])
    expect(result).toEqual({ total: 2, down: 1, allHealthy: false })
  })

  it('treats an empty list as not healthy', () => {
    expect(summariseHealth([])).toEqual({ total: 0, down: 0, allHealthy: false })
  })

  it('handles an undefined payload', () => {
    expect(summariseHealth(undefined)).toEqual({ total: 0, down: 0, allHealthy: false })
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/health.spec.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement the pure helper**

Create `apps/web-admin/app/lib/queries/health-summary.ts`:

```ts
import type { ServiceHealth } from '~/lib/api/types'

export type HealthSummary = {
  total: number
  down: number
  allHealthy: boolean
}

/**
 * An empty list is deliberately *not* "all healthy" — it means the board has
 * nothing to report, which should never look like a green light.
 */
export function summariseHealth(services: ServiceHealth[] | undefined): HealthSummary {
  const list = services ?? []
  const down = list.filter((s) => s.status === 'down').length
  return { total: list.length, down, allHealthy: list.length > 0 && down === 0 }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/health.spec.ts`
Expected: 4 passed.

- [ ] **Step 6: Add the query hook**

In `apps/web-admin/app/lib/queries/observability.ts`, add:

```ts
export const healthKeys = {
  all: ['health'] as const,
}

export function useServiceHealthQuery() {
  return useQuery<ServiceHealth[], ApiHttpError>({
    queryKey: healthKeys.all,
    queryFn: async () => {
      const raw = await apiFetch<{ services: ServiceHealth[] }>({
        service: 'platform',
        path: '/health',
        authenticated: true,
      })
      return raw.services
    },
    refetchInterval: 30_000,
  })
}
```

Extend the file's existing `import type { ... }` line with `ServiceHealth`.

- [ ] **Step 7: Build the page**

Create `apps/web-admin/app/pages/health/index.vue`:

```vue
<script setup lang="ts">
import { useServiceHealthQuery } from '~/lib/queries/observability'
import { summariseHealth } from '~/lib/queries/health-summary'

useHead({ title: 'Service health — AkademiQ Admin' })

const { data, isPending, dataUpdatedAt } = useServiceHealthQuery()

const services = computed(() => data.value ?? [])
const summary = computed(() => summariseHealth(data.value))
const lastChecked = computed(() =>
  dataUpdatedAt.value ? new Date(dataUpdatedAt.value).toLocaleTimeString() : '—',
)
</script>

<template>
  <div class="flex flex-col gap-6">
    <div>
      <h1 class="text-lg font-semibold text-highlighted">Service health</h1>
      <p class="text-sm text-muted">
        Live probe of every backend service. Refreshes every 30 seconds · last checked {{ lastChecked }}
      </p>
    </div>

    <UAlert
      v-if="!isPending && summary.down > 0"
      color="error"
      :title="`${summary.down} of ${summary.total} services are down`"
    />

    <RegionSkeleton v-if="isPending" :rows="3" />

    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <UCard v-for="service in services" :key="service.name">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-highlighted">{{ service.name }}</p>
            <p class="mt-1 font-mono text-xs text-muted">
              {{ service.latency_ms !== null ? `${service.latency_ms} ms` : 'unreachable' }}
            </p>
          </div>
          <StatusBadge :status="service.status === 'up' ? 'active' : 'cancelled'" />
        </div>
      </UCard>
    </div>

    <EmptyState
      v-if="!isPending && services.length === 0"
      title="No services configured"
      message="No health targets are configured for this environment."
    />
  </div>
</template>
```

- [ ] **Step 8: Add the nav entry**

In `apps/web-admin/app/layouts/default.vue`, add a link to `/health` labelled
`Service health` with icon `i-lucide-activity`, placed last in the list.

- [ ] **Step 9: Verify**

Run: `cd apps/web-admin && pnpm lint && pnpm vitest run`
Expected: all pass.

Manual: with the stack running, open `/health` and stop one service
(`docker compose stop grading-service` or equivalent); within 30 seconds the
card must flip to `down` without the page erroring.

- [ ] **Step 10: Commit (only if the user asked for commits)**

```bash
git add apps/web-admin/app apps/web-admin/tests/unit/health.spec.ts
git commit -m "feat(web-admin): add service health board"
```

---

### Task 11: Documentation

**Files:**
- Modify: `docs/internal/11_integration_contracts/apis/platform-service-api.md`
- Modify: `docs/internal/11_integration_contracts/apis/billing-service-api.md`
- Modify: `docs/internal/10_data_design/` (the platform-service ERD file)

**Interfaces:**
- Consumes: every endpoint built in Tasks 1-6.
- Produces: no code.

The event doc (`tenant.module_toggled.md`) was written in Task 2 Step 7; do not
duplicate it here.

- [ ] **Step 1: Document the platform endpoints**

In `docs/internal/11_integration_contracts/apis/platform-service-api.md`, match
the existing prose style (section heading, one-line purpose, JSON example) and add:

- `GET /tenants/{tenant_id}/subscription` — under a new "Subscription detail"
  heading after "Tenant directory". State that `data` is `null` when no
  projection row exists, that `ends_at` is nullable, and that `payment_method`
  is intentionally not exposed because it is not projected.
- `GET /tenants/{tenant_id}/modules` and `PUT /tenants/{tenant_id}/modules` —
  under a new "Module entitlements" heading. Document the `entitled` flag and
  note that `FEATURE_NOT_AVAILABLE` and `SUBSCRIPTION_EXPIRED` propagate
  unchanged from billing.
- `GET /registrations` — under a new "Registration troubleshooting" heading.
  Note it proxies billing and keeps no local copy, and list the four valid
  `state` values.
- `GET /health` — under a new "Service health" heading. Note the 2-second
  per-service timeout, the parallel fan-out, and that a `down` service never
  fails the request.

- [ ] **Step 2: Document the billing endpoints**

In `docs/internal/11_integration_contracts/apis/billing-service-api.md`, add
`GET /internal/registrations` and `PATCH /internal/tenants/{id}/modules` to the
internal endpoints section, noting both require `X-Service-Token` and that the
module toggle enforces plan entitlement and emits `tenant.module_toggled`.

- [ ] **Step 3: Update the data design note**

Find the platform-service file under `docs/internal/10_data_design/` and record
that `platform_subscription.modules` is now also written by
`tenant.module_toggled` (single-key JSONB patch), in addition to the full
replacement performed by `subscription.activated` / `subscription.plan_changed`.

- [ ] **Step 4: Verify the docs match the code**

Re-read each endpoint's handler and confirm every documented field name exists
in the response. Specifically check `started_at`/`ends_at` (not
`start_date`/`end_date`) and `code`/`enabled`/`entitled` for modules.

- [ ] **Step 5: Commit (only if the user asked for commits)**

```bash
git add docs/internal
git commit -m "docs: document platform phase 1 endpoints and module projection"
```

---

## Final Verification

After all tasks, run the full suites:

```bash
cd apps/backend && cargo test -p platform-service -p billing-service
cd apps/backend && cargo clippy -p platform-service -p billing-service -- -D warnings
cd apps/web-admin && pnpm lint && pnpm vitest run
```

Then, with the stack up, walk the four surfaces by hand: tenant detail
(subscription card + module panel), `/registrations`, `/health`. Confirm the
module toggle round-trips — flip a switch, and after the projection consumer
processes the event the panel still shows the new value on reload.
