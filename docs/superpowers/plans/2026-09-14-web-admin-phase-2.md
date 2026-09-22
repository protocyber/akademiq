# Web Admin Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a platform operator create a tenant, invite its first admin, reset a tenant user's password, and see why a registration stalled — without touching SQL or the CLI.

**Architecture:** Platform-service gains four operator endpoints that forward to billing and IAM over `X-Service-Token`, reusing the existing registration saga unchanged. The one structural change is making the password optional end to end in IAM's internal user-creation path, so an operator-created admin is born passwordless and receives a set-password link instead of a password the operator knows.

**Tech Stack:** Rust + Axum, SQLx against PostgreSQL 18, refinery migrations, RabbitMQ outbox; Nuxt 4 + Nuxt UI 4 + TanStack Vue Query; `cargo test` with testcontainers + wiremock; Vitest.

**Spec:** `docs/superpowers/specs/2026-09-14-web-admin-phase-2-design.md`

## Global Constraints

- Backend rules are authoritative in `apps/backend/CONVENTIONS.md`; web-admin rules in `apps/web-admin/CONVENTIONS.md`. Read both before starting.
- API base path `/api/v1/platform`. Success envelope `{ "data": ..., "meta": ... }`. Error envelope `{ "error": { "code": "...", "message": "..." } }`.
- Every platform endpoint calls `require_platform_admin(&auth)?` as its **first** statement.
- Every mutating endpoint writes `operator_audit` **only after** a 2xx from the downstream service. `forward_to_billing` returns `Err` on any non-2xx, so placing `write_audit` after the `?` is what satisfies this — do not add extra branching.
- SQL lives in `repo.rs`. `queries.rs` is a read-shape layer that delegates.
- **Activation and reset links are secrets.** Never log them, never write them into `operator_audit` metadata, never persist them client-side.
- Never trust a client-supplied `tenant_id` for authorization; platform tokens carry no tenant scope, so ids arrive as path params and are lookup keys only.
- TDD: write the failing test, watch it fail, then implement.
- Do not run a blanket `cargo fmt` — it reformats unrelated files and destroys the ~19-hunk platform-service baseline. Format only what you add.
- Backend tests: `cargo test -p <crate> -- --test-threads=2`. Full parallelism exhausts testcontainers and produces spurious failures.
- Known pre-existing failures, do NOT fix: platform's `read_endpoints_reject_non_operators` (`INVALID_TOKEN` vs `UNAUTHENTICATED`); 3 clippy lints in `libs/common-auth`.
- Commits authorised on `feat/web-admin-phase-2` in each submodule. Message only — no trailers, no attribution.

## The hazard this plan is shaped around

`resend_set_password_token` (`iam/commands.rs:1001`) refuses to issue a token when **either** `password_hash.is_some()` **or** `status != Active`, and returns `Ok` with `set_password_token: None` — **not** an error.

Two earlier designs died on this. An operator-created admin is passwordless, therefore `pending`, therefore refused by the second condition. So: **anything needing a link at creation time issues it at the point of creation** (Task 2), never via `resend`. `resend` is used only in Task 6, where it genuinely fits.

## Task order and dependencies

```
Task 1 (optional password, IAM)
   └─> Task 2 (issue token at creation, IAM)
          └─> Task 3 (billing passes None)
                 └─> Task 4 (platform POST /tenants) ─> Task 8 (create-tenant UI)
Task 5 (platform invitations)  ─────────────────────> Task 9 (invite UI)
Task 6 (platform reset-password) ───────────────────> Task 10 (reset UI)
Task 7 (failure reason, billing) ───────────────────> Task 11 (reason on the board)
Task 12 (docs) depends on 1-7
```

Tasks 1→2→3→4 are a chain. Tasks 5, 6, 7 are independent of it and of each other.

---

### Task 1: Make the password optional in IAM's internal user creation

**Files:**
- Modify: `apps/backend/services/iam-service/src/commands.rs` (`RegisterUserInput`, `validate_register_user`, `register_user`)
- Modify: `apps/backend/services/iam-service/src/http.rs` (`InternalCreateUserBody`)
- Test: `apps/backend/services/iam-service/tests/integration.rs`

**Interfaces:**
- Produces: `RegisterUserInput.password: Option<String>`; `register_user` accepts a `None` password and inserts a user with a NULL `password_hash` and status `pending`.
- Consumed by: Task 2 (which adds token issuance), Task 3 (billing's caller).

Background, all verified in source:
- `password_hash` is already nullable (`iam/migrations/V9__google_oauth.sql:2`).
- `insert_user_with_roles` (`iam/repo.rs:586-602`) already takes `password_hash: Option<&str>` and already derives status: `Some` → `"active"`, `None` → `"pending"`. **No repo change is needed.**
- `register_user` currently calls `insert_with_role`, whose `password_hash` parameter is `&str` (`iam/repo.rs:332`). Switch it to `insert_user_with_roles`.
- `register_user` has exactly one production caller outside tests: `internal_create_user` (`iam/http.rs:1363`).

**THE SECURITY-CRITICAL PART.** `register_user` also backs public registration. `validate_register_user:2403` enforces `input.password.len() < 8`. That check must still run whenever a password IS supplied, and be skipped only when the caller explicitly sends `None`. Getting this wrong opens a hole rather than causing a bug.

- [ ] **Step 1: Write the failing tests**

Read the top of `services/iam-service/tests/integration.rs` first and reuse its existing `boot()` and helpers rather than inventing new ones. Append:

```rust
#[tokio::test]
async fn internal_create_user_without_a_password_yields_a_pending_user() {
    let (pool, state, _c) = boot().await;

    let user = iam_service::commands::register_user(
        &state,
        iam_service::commands::RegisterUserInput {
            email: Some("head@sekolah.test".into()),
            username: None,
            password: None,
            full_name: "Kepala Sekolah".into(),
            tenant_id: uuid::Uuid::new_v4(),
            role_code: "tenant_admin".into(),
        },
    )
    .await
    .expect("passwordless creation succeeds");

    let row: (Option<String>, String) =
        sqlx::query_as(r#"SELECT password_hash, status FROM "user" WHERE user_id = $1"#)
            .bind(user.user_id)
            .fetch_one(&pool)
            .await
            .unwrap();

    assert!(row.0.is_none(), "no password hash is stored");
    assert_eq!(row.1, "pending", "a user who cannot log in yet is pending");
}

#[tokio::test]
async fn a_supplied_password_is_still_hashed_and_activates_the_user() {
    let (pool, state, _c) = boot().await;

    let user = iam_service::commands::register_user(
        &state,
        iam_service::commands::RegisterUserInput {
            email: Some("with@password.test".into()),
            username: None,
            password: Some("correct-horse".into()),
            full_name: "Punya Password".into(),
            tenant_id: uuid::Uuid::new_v4(),
            role_code: "tenant_admin".into(),
        },
    )
    .await
    .expect("password creation succeeds");

    let row: (Option<String>, String) =
        sqlx::query_as(r#"SELECT password_hash, status FROM "user" WHERE user_id = $1"#)
            .bind(user.user_id)
            .fetch_one(&pool)
            .await
            .unwrap();

    let hash = row.0.expect("a hash is stored");
    assert_ne!(hash, "correct-horse", "the password is hashed, not stored raw");
    assert_eq!(row.1, "active");
}

#[tokio::test]
async fn a_short_password_is_still_rejected() {
    // The security-critical case: relaxing the type must NOT relax the rule.
    // A caller that sends a password is still held to the 8-character minimum;
    // only an explicit `None` skips it.
    let (_pool, state, _c) = boot().await;

    let err = iam_service::commands::register_user(
        &state,
        iam_service::commands::RegisterUserInput {
            email: Some("short@password.test".into()),
            username: None,
            password: Some("short".into()),
            full_name: "Terlalu Pendek".into(),
            tenant_id: uuid::Uuid::new_v4(),
            role_code: "tenant_admin".into(),
        },
    )
    .await
    .expect_err("a 5-character password is refused");

    assert_eq!(err.code(), "VALIDATION_ERROR");
}
```

If `AppError`'s code accessor is not `.code()`, check `libs/common-errors/src/lib.rs` and use the real one rather than adding an accessor for the test.

**Note for Task 2:** these three tests bind `register_user`'s result and read
`user.user_id`. Task 2 changes that return type to `RegisteredUser { user,
set_password_token }`, so Task 2 must update these call sites to
`registered.user.user_id`. That is expected churn, not a mistake — Task 1
cannot return a token it does not yet issue, and splitting the change keeps
each task's test cycle honest.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 password`
Expected: FAIL to compile — `password: None` does not typecheck against `String`.

- [ ] **Step 3: Relax the two structs**

`services/iam-service/src/commands.rs`, in `RegisterUserInput`:

```rust
    pub password: Option<String>,
```

`services/iam-service/src/http.rs`, in `InternalCreateUserBody`:

```rust
    password: Option<String>,
```

- [ ] **Step 4: Make validation conditional without weakening it**

In `validate_register_user`, replace the unconditional length check:

```rust
    // A supplied password is still held to the minimum. `None` is not a weak
    // password — it is the absence of one, and it produces a `pending` user who
    // cannot authenticate until they set one. Only an internal caller can send
    // it; the public registration handler always supplies a password.
    if let Some(password) = input.password.as_deref() {
        if password.len() < 8 {
            fields
                .entry("password".into())
                .or_default()
                .push("password must be at least 8 characters".into());
        }
    }
```

`ValidatedRegister.password` must become `Option<String>` to carry this through. Follow the existing struct's shape.

- [ ] **Step 5: Branch the hashing and switch the insert**

In `register_user`, replace the hash line and the `insert_with_role` call:

```rust
    let hash = match validated.password.as_deref() {
        Some(pw) => Some(hash_password(pw).map_err(map_password_error)?),
        None => None,
    };
    let user_id = Uuid::new_v4();
    let username = resolve_username(state, validated.username).await?;
    state
        .user_repo
        .insert_user_with_roles(
            user_id,
            &username,
            validated.email.as_deref(),
            hash.as_deref(),
            &validated.full_name,
            input.tenant_id,
            std::slice::from_ref(&input.role_code),
        )
        .await
        .map_err(map_sql_error)?;
```

Check `insert_user_with_roles`'s exact signature at `repo.rs:586-594` before writing this — it takes `role_codes: &[String]`, not a single code.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 password`
Expected: 3 passed.

- [ ] **Step 7: Verify nothing else broke**

Run: `cd apps/backend && cargo test -p iam-service -- --test-threads=2 && cargo clippy -p iam-service`
Expected: all pass except the two known `password_login_*` failures; clippy adds no new warnings.

Public registration goes through `public_register`, not `register_user` — confirm by reading `commands.rs:544` that it is a separate function with its own validation, so this change cannot reach it.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/services/iam-service/src/commands.rs \
        apps/backend/services/iam-service/src/http.rs \
        apps/backend/services/iam-service/tests/integration.rs
git commit -m "feat(iam): allow internal user creation without a password"
```

---

### Task 2: Issue a set-password token when the user is created passwordless

**Files:**
- Modify: `apps/backend/services/iam-service/src/commands.rs` (`register_user`, and a new output type)
- Modify: `apps/backend/services/iam-service/src/http.rs` (`internal_create_user` response)
- Test: `apps/backend/services/iam-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 1's optional password.
- Produces: `register_user` returns `RegisteredUser { user: User, set_password_token: Option<String> }`. `POST /api/v1/iam/internal/users` returns `set_password_token` and `activation_link` in its `data` when the user was created without a password.

Why here and not via `resend`: `resend_set_password_token` refuses a `pending` user (`commands.rs:1001`) and returns `Ok` with `None`, which would give the operator a success screen and no link. The raw token exists exactly once — `issue_set_password_token` (`commands.rs:2614-2626`) stores only its hash — so it must be returned at creation.

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn a_passwordless_user_gets_a_usable_set_password_token() {
    let (_pool, state, _c) = boot().await;

    let registered = iam_service::commands::register_user(
        &state,
        iam_service::commands::RegisterUserInput {
            email: Some("needs@token.test".into()),
            username: None,
            password: None,
            full_name: "Butuh Token".into(),
            tenant_id: uuid::Uuid::new_v4(),
            role_code: "tenant_admin".into(),
        },
    )
    .await
    .expect("creation succeeds");

    let token = registered
        .set_password_token
        .expect("a passwordless user must come with a token");

    // The token must actually work — not merely be present. This is the
    // assertion that fails if the token is issued for the wrong user, or
    // stored with a hash that cannot be matched back.
    iam_service::commands::set_password(
        &state,
        iam_service::commands::SetPasswordInput {
            token: Some(token),
            password: "brand-new-password".into(),
            ..Default::default()
        },
    )
    .await
    .expect("the issued token sets a password");
}

#[tokio::test]
async fn a_user_created_with_a_password_gets_no_token() {
    let (_pool, state, _c) = boot().await;

    let registered = iam_service::commands::register_user(
        &state,
        iam_service::commands::RegisterUserInput {
            email: Some("has@password.test".into()),
            username: None,
            password: Some("already-set-here".into()),
            full_name: "Sudah Punya".into(),
            tenant_id: uuid::Uuid::new_v4(),
            role_code: "tenant_admin".into(),
        },
    )
    .await
    .expect("creation succeeds");

    assert!(
        registered.set_password_token.is_none(),
        "issuing a token for a user who can already log in would be a second, \
         unnecessary credential",
    );
}
```

`SetPasswordInput`'s real field set is at `commands.rs:873`'s signature — read it and construct the value correctly rather than relying on `..Default::default()` if the type does not derive `Default`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 token`
Expected: FAIL to compile — `register_user` returns `User`, which has no `set_password_token`.

- [ ] **Step 3: Update Task 1's call sites**

The three tests Task 1 added bind `register_user`'s result and read
`user.user_id`. Changing the return type breaks them. Update each to
`registered.user.user_id` — do NOT weaken or delete them; they pin the
security-critical password rules.

- [ ] **Step 4: Add the output type and issue the token**

In `commands.rs`, next to the other output structs:

```rust
/// A freshly created user, plus the one-time set-password token when the user
/// was created without a password.
///
/// The token is returned here because this is the ONLY moment it can be: the
/// repository stores a hash of it (`issue_set_password_token`), and
/// `resend_set_password_token` refuses to mint another for a `pending` user.
pub struct RegisteredUser {
    pub user: User,
    pub set_password_token: Option<String>,
}
```

Change `register_user`'s return type to `Result<RegisteredUser, AppError>` and its tail:

```rust
    let set_password_token = if hash.is_none() {
        Some(issue_set_password_token(state, user_id).await?)
    } else {
        None
    };

    let user = state
        .user_repo
        .find_by_id(user_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::internal(anyhow::anyhow!("user vanished after insert")))?;
    Ok(RegisteredUser { user, set_password_token })
```

- [ ] **Step 5: Surface it on the internal endpoint**

`internal_create_user` (`http.rs:1354`) currently binds `let user = register_user(...)`. Update it to use `registered.user` wherever it used `user`, and add both fields to the response `data`:

```rust
            "set_password_token": registered.set_password_token,
            "activation_link": registered
                .set_password_token
                .as_deref()
                .map(|t| state.email_client.activation_link(t)),
```

`activation_link` is built by the existing `email.rs` helper (`:95`) — reuse it, do not format the URL by hand.

- [ ] **Step 6: Run the tests**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 token`
Expected: 2 passed.

- [ ] **Step 7: Verify the crate and prove the token test has teeth**

Run: `cd apps/backend && cargo test -p iam-service -- --test-threads=2`

Then temporarily change `issue_set_password_token(state, user_id)` to issue for `Uuid::new_v4()` instead, re-run, and confirm `a_passwordless_user_gets_a_usable_set_password_token` FAILS at the `set_password` call rather than at the `expect`. Restore. Report what you observed — a test that only asserts the token is `Some` would pass against a token issued for the wrong user.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/services/iam-service/src
git add apps/backend/services/iam-service/tests/integration.rs
git commit -m "feat(iam): return a set-password token for passwordless users"
```

---

### Task 3: Let billing register a tenant without a password

**Files:**
- Modify: `apps/backend/services/billing-service/src/iam_client.rs` (`create_user`)
- Modify: `apps/backend/services/billing-service/src/commands.rs` (`RegisterTenantInput`, `validate_register`, `register_tenant`)
- Test: `apps/backend/services/billing-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 2's `set_password_token` / `activation_link` on `POST /internal/users`.
- Produces: `RegisterTenantInput.admin_password: Option<String>`; `RegisterTenantOutput` gains `activation_link: Option<String>`.

`iam_client.create_user` has exactly one production caller (`commands.rs:164`), verified by grep; the rest are wiremock stubs in tests.

- [ ] **Step 1: Write the failing test**

Read the existing registration tests (`integration.rs:178`) and mirror their wiremock setup. Append:

```rust
#[tokio::test]
async fn registering_without_a_password_returns_an_activation_link() {
    let (pool, state, iam, _c) = boot().await;
    seed_plans(&pool).await;

    Mock::given(method("POST"))
        .and(path("/api/v1/iam/internal/users"))
        .respond_with(ResponseTemplate::new(201).set_body_json(json!({
            "data": {
                "user_id": "11111111-1111-1111-1111-111111111111",
                "set_password_token": "raw-token-abc",
                "activation_link": "https://app.test/invitations/accept?token=raw-token-abc"
            },
            "meta": {}
        })))
        .mount(&iam)
        .await;

    let out = billing_service::commands::register_tenant(
        &state,
        billing_service::commands::RegisterTenantInput {
            school_name: "SMA Harapan".into(),
            admin_email: "kepala@harapan.test".into(),
            admin_full_name: "Kepala Harapan".into(),
            admin_password: None,
            plan_id: premium_plan_id(&pool).await,
        },
    )
    .await
    .expect("registration succeeds without a password");

    assert_eq!(
        out.activation_link.as_deref(),
        Some("https://app.test/invitations/accept?token=raw-token-abc"),
        "the operator needs the link back; it cannot be re-derived later",
    );
}
```

Adapt the input struct's field names and the plan-id helper to whatever the file already uses — read `integration.rs:178-240` first.

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && cargo test -p billing-service --test integration -- --test-threads=2 without_a_password`
Expected: FAIL to compile — `admin_password: None` does not typecheck, and `activation_link` is not a field.

- [ ] **Step 3: Relax the client**

In `iam_client.rs`, change `create_user`'s `password: &str` to `password: Option<&str>` and serialise it as-is (serde omits `None` only with `skip_serializing_if`; here the IAM body's field is `Option`, so sending explicit `null` is fine). Return the `activation_link` alongside the user id — read the current return type and widen it rather than adding a second call.

- [ ] **Step 4: Thread it through the command**

`RegisterTenantInput.admin_password` becomes `Option<String>`. In `validate_register`, apply the existing password rules only when it is `Some` — same shape as Task 1 Step 4. `register_tenant` passes it through and carries the returned link into `RegisterTenantOutput`.

Leave the saga's ordering and its compensating `delete_user` on failure exactly as they are.

- [ ] **Step 5: Run the tests**

Run: `cd apps/backend && cargo test -p billing-service --test integration -- --test-threads=2`
Expected: all pass. The existing registration tests must stay green — they supply a password and must keep working unchanged.

- [ ] **Step 6: Commit**

```bash
git add apps/backend/services/billing-service/src \
        apps/backend/services/billing-service/tests/integration.rs
git commit -m "feat(billing): register a tenant without an admin password"
```

---

### Task 4: `POST /api/v1/platform/tenants`

**Files:**
- Modify: `apps/backend/services/platform-service/src/http.rs`
- Test: `apps/backend/services/platform-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 3's billing endpoint.
- Produces: `POST /api/v1/platform/tenants` with body `{ school_name, admin_email, admin_full_name, plan_id }`, returning `{ "data": { tenant_id, user_id, activation_link }, "meta": {} }`.

There is no operator-facing creation path today; only billing's public `POST /tenants/register` and `register-for-user`. Check whether billing exposes an **internal** registration route; if not, this task adds one alongside the existing `internal/*` endpoints, guarded by `ServiceToken`, mirroring `internal_suspend_handler`'s signature.

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn create_tenant_forwards_and_returns_the_activation_link() {
    let (pool, state, billing, _c) = boot().await;

    Mock::given(method("POST"))
        .and(path("/api/v1/billing/internal/tenants"))
        .and(header_exists("X-Service-Token"))
        .respond_with(ResponseTemplate::new(201).set_body_json(json!({
            "data": {
                "tenant_id": "22222222-2222-2222-2222-222222222222",
                "user_id": "33333333-3333-3333-3333-333333333333",
                "activation_link": "https://app.test/invitations/accept?token=xyz"
            },
            "meta": {}
        })))
        .mount(&billing)
        .await;

    let (status, json) = send(
        state.clone(),
        axum::http::Method::POST,
        "/api/v1/platform/tenants",
        &operator_token(),
        json!({
            "school_name": "SMA Harapan",
            "admin_email": "kepala@harapan.test",
            "admin_full_name": "Kepala Harapan",
            "plan_id": "44444444-4444-4444-4444-444444444444"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        json["data"]["activation_link"],
        "https://app.test/invitations/accept?token=xyz"
    );

    let count: (i64,) = sqlx::query_as(
        "SELECT count(*) FROM operator_audit WHERE action = 'tenant.create'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 1, "a successful create is audited");
}

#[tokio::test]
async fn a_failed_create_is_not_audited_and_does_not_leak_a_link() {
    let (pool, state, billing, _c) = boot().await;

    Mock::given(method("POST"))
        .and(path("/api/v1/billing/internal/tenants"))
        .respond_with(ResponseTemplate::new(409).set_body_json(json!({
            "error": { "code": "EMAIL_ALREADY_EXISTS", "message": "email is already registered" }
        })))
        .mount(&billing)
        .await;

    let (status, json) = send(
        state.clone(),
        axum::http::Method::POST,
        "/api/v1/platform/tenants",
        &operator_token(),
        json!({
            "school_name": "SMA Harapan",
            "admin_email": "kepala@harapan.test",
            "admin_full_name": "Kepala Harapan",
            "plan_id": "44444444-4444-4444-4444-444444444444"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(
        json["error"]["code"], "EMAIL_ALREADY_EXISTS",
        "billing's reason must reach the operator, not a generic downstream code",
    );

    let count: (i64,) = sqlx::query_as("SELECT count(*) FROM operator_audit")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count.0, 0);
}

#[tokio::test]
async fn create_tenant_requires_platform_admin() {
    let (_pool, state, billing, _c) = boot().await;

    let (status, _json) = send(
        state.clone(),
        axum::http::Method::POST,
        "/api/v1/platform/tenants",
        &platform_token(&["support"]),
        json!({ "school_name": "x", "admin_email": "a@b.test", "admin_full_name": "A", "plan_id": "44444444-4444-4444-4444-444444444444" }),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(
        billing.received_requests().await.unwrap().is_empty(),
        "authorization must short-circuit before any egress",
    );
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && cargo test -p platform-service --test integration -- --test-threads=2 create_tenant`
Expected: FAIL — route missing, 404 instead of 201.

- [ ] **Step 3: Add the route and handler**

Route, beside the other tenant routes:

```rust
        .route("/api/v1/platform/tenants", get(list_tenants).post(create_tenant))
```

`/api/v1/platform/tenants` already exists as a `get`. Merge the method into the existing registration — Axum panics at startup on a duplicate path.

Handler, beside `suspend_tenant`:

```rust
#[derive(Debug, Deserialize)]
struct CreateTenantBody {
    school_name: String,
    admin_email: String,
    admin_full_name: String,
    plan_id: Uuid,
}

async fn create_tenant(
    State(state): State<AppState>,
    auth: PlatformAuthContext,
    Json(body): Json<CreateTenantBody>,
) -> Result<(StatusCode, Json<Value>), AppError> {
    require_platform_admin(&auth)?;
    let value = forward_to_billing(
        &state,
        reqwest::Method::POST,
        "/api/v1/billing/internal/tenants",
        Some(json!({
            "school_name": body.school_name,
            "admin_email": body.admin_email,
            "admin_full_name": body.admin_full_name,
        })),
    )
    .await?;

    // The activation link is a credential: audit the fact, never the secret.
    write_audit(
        &state,
        auth.user_id,
        "tenant.create",
        "tenant",
        value
            .pointer("/data/tenant_id")
            .and_then(Value::as_str)
            .unwrap_or("unknown"),
        &json!({ "admin_email": body.admin_email, "school_name": body.school_name }),
    )
    .await?;
    Ok((StatusCode::CREATED, Json(value)))
}
```

Note `plan_id` is in the body above but omitted from the forwarded payload in this snippet — include it; the snippet shows the audit shape, and the forwarded body must carry every field billing validates.

- [ ] **Step 4: Preserve billing's error codes**

`map_downstream_error` flattens most codes. Add `EMAIL_ALREADY_EXISTS` to the pass-through allowlist beside `FEATURE_NOT_AVAILABLE` and `SUBSCRIPTION_EXPIRED`, following the same guard shape. Check `AppError::conflict`'s signature in `libs/common-errors/src/lib.rs` — if it takes `&'static str`, add a dedicated arm rather than passing a dynamic code.

- [ ] **Step 5: Run the tests**

Run: `cd apps/backend && cargo test -p platform-service --test integration -- --test-threads=2 create_tenant`
Expected: 3 passed.

- [ ] **Step 6: Verify the audit never carries the link**

Run: `cd apps/backend && cargo test -p platform-service -- --test-threads=2`

Then grep the audit metadata assertion: confirm no test and no handler writes `activation_link` into `operator_audit`. State in your report that you checked this.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/services/platform-service/src/http.rs \
        apps/backend/services/platform-service/tests/integration.rs
git commit -m "feat(platform): create a tenant from the operator console"
```

---

### Task 5: `POST /api/v1/platform/tenants/{tenant_id}/invitations`

**Files:**
- Modify: `apps/backend/services/iam-service/src/http.rs` (internal invitation route)
- Modify: `apps/backend/services/platform-service/src/http.rs` (proxy)
- Test: both services' `tests/integration.rs`

**Interfaces:**
- Produces: `POST /api/v1/platform/tenants/{tenant_id}/invitations` with body `{ email, roles }`, returning IAM's envelope including `activation_link`.

IAM's `invite_tenant_user` already mints the token and its handler already returns `activation_link` and `token` (`http.rs:585-586`). The tenant-scoped route reads `tenant_id` from the admin's JWT, which an operator does not hold — so IAM needs an internal route taking `tenant_id` as a path parameter, guarded by `ServiceToken`.

- [ ] **Step 1: Write the failing IAM test**

```rust
#[tokio::test]
async fn internal_invitation_returns_an_activation_link() {
    let (_pool, state, _c) = boot().await;
    let tenant_id = seed_tenant(&state).await;

    let app = iam_service::http::router(state.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/iam/internal/tenants/{tenant_id}/invitations"))
                .header("X-Service-Token", SERVICE_TOKEN)
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({
                        "email": "guru@sekolah.test",
                        "roles": ["tenant_admin"]
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let json = body_to_json(resp).await;
    assert!(
        json["data"]["activation_link"].as_str().is_some_and(|l| l.contains("token=")),
        "the operator must receive a link they can hand over",
    );
}

#[tokio::test]
async fn internal_invitation_rejects_a_caller_without_a_service_token() {
    let (_pool, state, _c) = boot().await;
    let tenant_id = seed_tenant(&state).await;

    let app = iam_service::http::router(state.clone());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/v1/iam/internal/tenants/{tenant_id}/invitations"))
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({ "email": "guru@sekolah.test", "roles": [] })).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}
```

Adapt `seed_tenant` and `SERVICE_TOKEN` to whatever the IAM test file already provides.

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 internal_invitation`
Expected: FAIL — 404, route missing.

- [ ] **Step 3: Add IAM's internal route**

Route, beside the other `internal/*` routes:

```rust
        .route(
            "/api/v1/iam/internal/tenants/:tenant_id/invitations",
            post(internal_invite_tenant_user),
        )
```

Handler mirroring `invite_tenant_user_handler` (`http.rs:555`) but taking `tenant_id` from the path and `invited_by` from the body (the operator's id), guarded by `ServiceToken` instead of `AuthContext`. Return the same `data` shape, including `activation_link`.

- [ ] **Step 4: Add the platform proxy**

Route:

```rust
        .route(
            "/api/v1/platform/tenants/:tenant_id/invitations",
            post(invite_tenant_admin),
        )
```

The handler calls `require_platform_admin`, forwards to IAM over `X-Service-Token`, then writes `operator_audit` with action `tenant.invite` — carrying the invited email, never the link.

**`forward_to_billing` only targets billing.** Read it (`http.rs:~806`) and either generalise it to take a base URL or add a sibling `forward_to_iam`. Whichever you choose, keep one error-mapping path — do not duplicate `map_downstream_error`.

A `409` from IAM ("user is already a member of this tenant", `commands.rs:682`) must reach the operator verbatim: add its code to the pass-through allowlist, and test it.

- [ ] **Step 5: Write the platform test**

Mirror the Task 4 tests: a success case asserting the link comes back and the audit row exists; a `409` case asserting the code survives and NO audit row is written.

- [ ] **Step 6: Run both suites**

Run: `cd apps/backend && cargo test -p iam-service -p platform-service -- --test-threads=2`
Expected: all pass except the known pre-existing failures.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/services/iam-service apps/backend/services/platform-service
git commit -m "feat(platform): invite a tenant admin from the operator console"
```

---

### Task 6: `POST /api/v1/platform/users/{user_id}/reset-password`

**Files:**
- Modify: `apps/backend/services/iam-service/src/http.rs` (internal reset route)
- Modify: `apps/backend/services/platform-service/src/http.rs` (proxy)
- Test: both services' `tests/integration.rs`

**Interfaces:**
- Produces: `POST /api/v1/platform/users/{user_id}/reset-password`, returning either `{ "data": { "activation_link": "…" } }` or a 409 explaining why no link could be issued.

**This is the one place `resend_set_password_token` fits** — it targets an `Active` user who already has a password, which is exactly a reset.

**The hazard.** It returns `Ok` with `set_password_token: None` when the user does not qualify (`commands.rs:1001-1005`). The endpoint MUST distinguish the two outcomes. A success envelope with a null link is the silent-failure shape this whole phase is built to avoid.

- [ ] **Step 1: Write the failing tests**

```rust
#[tokio::test]
async fn reset_password_returns_a_link_for_an_active_user() {
    let (_pool, state, _c) = boot().await;
    let user_id = seed_active_user_with_password(&state).await;

    let (status, json) = internal_post(
        &state,
        &format!("/api/v1/iam/internal/users/{user_id}/reset-password"),
        json!({}),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert!(json["data"]["activation_link"].as_str().is_some_and(|l| l.contains("token=")));
}

#[tokio::test]
async fn reset_password_explains_itself_when_no_token_can_be_issued() {
    // A `pending` user has never set a password, so there is nothing to reset
    // and `resend_set_password_token` returns Ok(None). Returning 200 with a
    // null link would tell the operator the reset worked.
    let (_pool, state, _c) = boot().await;
    let user_id = seed_pending_user(&state).await;

    let (status, json) = internal_post(
        &state,
        &format!("/api/v1/iam/internal/users/{user_id}/reset-password"),
        json!({}),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(json["error"]["code"], "NO_RESET_AVAILABLE");
    assert!(
        json["error"]["message"].as_str().is_some_and(|m| !m.is_empty()),
        "the operator needs to know WHY, not just that it failed",
    );
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/backend && cargo test -p iam-service --test integration -- --test-threads=2 reset_password`
Expected: FAIL — route missing.

- [ ] **Step 3: Add IAM's internal reset route**

Route + handler guarded by `ServiceToken`, calling `resend_set_password_token` and translating its result:

```rust
    let result = resend_set_password_token(&state, ResendSetPasswordInput { user_id }).await?;
    match result.set_password_token {
        Some(token) => Ok(Json(json!({
            "data": { "activation_link": state.email_client.activation_link(&token) },
            "meta": {}
        }))),
        // `resend` reports Ok(None) for a user who has no password to reset or
        // is not active. That is a real outcome with a real cause, not a
        // success — say so.
        None => Err(AppError::conflict(
            "NO_RESET_AVAILABLE",
            "the user has not set a password yet, or the account is not active",
        )),
    }
```

Read `ResendSetPasswordInput`'s real shape at `commands.rs:969` before writing this.

- [ ] **Step 4: Add the platform proxy**

Same pattern as Task 5: `require_platform_admin`, forward over `X-Service-Token`, audit `user.reset_password` **with the user id, never the link**, and pass `NO_RESET_AVAILABLE` through the error allowlist.

- [ ] **Step 5: Write the platform tests**

A success case, and a case asserting the `NO_RESET_AVAILABLE` code survives the proxy and writes no audit row.

- [ ] **Step 6: Run both suites and commit**

```bash
cd apps/backend && cargo test -p iam-service -p platform-service -- --test-threads=2
git add apps/backend/services/iam-service apps/backend/services/platform-service
git commit -m "feat(platform): reset a tenant user's password from the operator console"
```

---

### Task 7: Record why a registration failed

**Files:**
- Create: `apps/backend/services/billing-service/migrations/V4__pending_registration_failure_reason.sql`
- Modify: `apps/backend/services/billing-service/src/repo.rs` (`PendingRegistrationRepo`)
- Modify: `apps/backend/services/billing-service/src/commands.rs` (`register_tenant`'s error path)
- Modify: `apps/backend/services/billing-service/src/domain.rs` (`PendingRegistration`)
- Test: `apps/backend/services/billing-service/tests/integration.rs`

**Interfaces:**
- Produces: `pending_registration.failure_reason TEXT NULL`, surfaced on `GET /internal/registrations` and therefore on `GET /platform/registrations`.

Per the spec §6, there is no retry and no clear button. The operator's actual need is the cause, which today exists only in service logs (`commands.rs:174`).

- [ ] **Step 1: Write the migration**

```sql
-- Why a registration stopped, for the operator board.
--
-- The cause currently reaches only the service log, so an operator sees a
-- stalled row with no way to tell "this email is already taken" from "IAM was
-- unreachable" -- one needs a human decision, the other needs patience.
--
-- Nullable: a row in flight has not failed, and `completed` rows never do.
ALTER TABLE pending_registration
    ADD COLUMN IF NOT EXISTS failure_reason TEXT;
```

- [ ] **Step 2: Write the failing test**

```rust
#[tokio::test]
async fn a_failed_registration_records_why() {
    let (pool, state, iam, _c) = boot().await;
    seed_plans(&pool).await;

    Mock::given(method("POST"))
        .and(path("/api/v1/iam/internal/users"))
        .respond_with(ResponseTemplate::new(409).set_body_json(json!({
            "error": { "code": "EMAIL_ALREADY_EXISTS", "message": "email is already registered" }
        })))
        .mount(&iam)
        .await;

    let _ = billing_service::commands::register_tenant(
        &state,
        billing_service::commands::RegisterTenantInput {
            school_name: "SMA Gagal".into(),
            admin_email: "ada@sudah.test".into(),
            admin_full_name: "Sudah Ada".into(),
            admin_password: None,
            plan_id: premium_plan_id(&pool).await,
        },
    )
    .await
    .expect_err("registration fails");

    // Driven through the real saga, not written into the row directly -- a
    // test that UPDATEs the column itself would prove nothing about whether
    // the failure path records anything.
    let reason: (Option<String>,) =
        sqlx::query_as("SELECT failure_reason FROM pending_registration WHERE email = $1")
            .bind("ada@sudah.test")
            .fetch_one(&pool)
            .await
            .unwrap();

    let reason = reason.0.expect("the cause is recorded");
    assert!(
        reason.to_lowercase().contains("email"),
        "the stored reason must name the cause; got {reason:?}",
    );
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd apps/backend && cargo test -p billing-service --test integration -- --test-threads=2 records_why`
Expected: FAIL — the column does not exist.

- [ ] **Step 4: Add the repo method and record on failure**

Add `PendingRegistrationRepo::mark_failed(registration_id, reason: &str)` writing `state = 'failed'` and `failure_reason`. In `register_tenant`, call it on the IAM-creation failure branch (`commands.rs:172-177`) and on the `create_tenant_with_subscription` failure branch, before the compensating delete.

Note `failed` is currently a dead state with no producer — this task gives it one, which also makes the board's `Failed` filter meaningful for the first time.

- [ ] **Step 5: Surface it**

Add `failure_reason: Option<String>` to `domain::PendingRegistration` and to the `SELECT` in `list_pending_registrations`. No platform-service change is needed — it proxies billing's body verbatim.

- [ ] **Step 6: Run the tests and commit**

```bash
cd apps/backend && cargo test -p billing-service -- --test-threads=2
git add apps/backend/services/billing-service
git commit -m "feat(billing): record why a registration failed"
```

---

### Task 8: Create-tenant UI

**Files:**
- Create: `apps/web-admin/app/lib/schemas/create-tenant.ts`
- Create: `apps/web-admin/app/lib/mutations/create-tenant.ts`
- Create: `apps/web-admin/app/components/ActivationLinkPanel.vue`
- Modify: `apps/web-admin/app/pages/tenants/index.vue` (an action button + modal)
- Test: `apps/web-admin/tests/unit/create-tenant.spec.ts`

**Interfaces:**
- Consumes: `POST /platform/tenants` from Task 4.
- Produces: `<ActivationLinkPanel :link>` reused by Tasks 9 and 10.

Follow `apps/web-admin/CONVENTIONS.md` §4: the schema lives in `app/lib/schemas/`, field keys match the backend exactly (`school_name`, not `schoolName`), the form is `<UForm :schema :state>`, and server `VALIDATION_ERROR` payloads route through `apply-server-field-errors.ts`.

- [ ] **Step 1: Write the failing schema test**

```ts
import { describe, expect, it } from 'vitest'
import { createTenantSchema } from '~/lib/schemas/create-tenant'

describe('createTenantSchema', () => {
  it('accepts a complete form', () => {
    const result = createTenantSchema.safeParse({
      school_name: 'SMA Harapan Bangsa',
      admin_email: 'kepala@harapan.test',
      admin_full_name: 'Kepala Harapan',
      plan_id: '44444444-4444-4444-4444-444444444444',
    })
    expect(result.success).toBe(true)
  })

  it('rejects a malformed email', () => {
    const result = createTenantSchema.safeParse({
      school_name: 'SMA Harapan Bangsa',
      admin_email: 'not-an-email',
      admin_full_name: 'Kepala Harapan',
      plan_id: '44444444-4444-4444-4444-444444444444',
    })
    expect(result.success).toBe(false)
  })

  it('has no password field', () => {
    // The operator never sets or sees the school's password. If this field
    // ever appears, the passwordless flow has been undone.
    expect(Object.keys(createTenantSchema.shape)).not.toContain('admin_password')
  })
})
```

- [ ] **Step 2: Run to verify it fails, then write the schema**

Run: `cd apps/web-admin && pnpm vitest run tests/unit/create-tenant.spec.ts`
Expected: FAIL — module not found.

```ts
import * as z from 'zod'

export const createTenantSchema = z.object({
  school_name: z.string().min(1, 'School name is required'),
  admin_email: z.string().email('Enter a valid email address'),
  admin_full_name: z.string().min(1, "The admin's name is required"),
  plan_id: z.string().uuid('Select a plan'),
})

export type CreateTenantForm = z.output<typeof createTenantSchema>
```

- [ ] **Step 3: Add the mutation**

Mirror `app/lib/mutations/tenants.ts`. **Return the invalidation promise from `onSuccess`** — dropping it makes the pending state fall before the list has refetched, which is the defect fixed in commit `83bce50`.

- [ ] **Step 4: Build `ActivationLinkPanel`**

A `UAlert` holding the link in a read-only `UInput` plus a copy `UButton`, following the existing `useCopyId` pattern. Copy must state plainly that this link is shown **once** and must be delivered to the school by the operator.

- [ ] **Step 5: Wire the modal into `/tenants`**

A "New tenant" `UButton` in `DataTableCard`'s `#actions` slot, opening a `UModal` with the form. On success the modal stays open and swaps to the `ActivationLinkPanel` — closing it would discard a link that cannot be re-derived.

- [ ] **Step 6: Verify**

Run: `cd apps/web-admin && pnpm vitest run && pnpm lint && pnpm typecheck`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add apps/web-admin/app apps/web-admin/tests
git commit -m "feat(web-admin): create a tenant from the console"
```

---

### Task 9: Invite-admin UI

**Files:**
- Create: `apps/web-admin/app/lib/schemas/invite-admin.ts`
- Create: `apps/web-admin/app/lib/mutations/invitations.ts`
- Modify: `apps/web-admin/app/pages/tenants/[id].vue`
- Test: `apps/web-admin/tests/unit/invite-admin.spec.ts`

**Interfaces:**
- Consumes: Task 5's endpoint, and `<ActivationLinkPanel>` from Task 8.

- [ ] **Step 1: Schema + test**

Same shape as Task 8: `{ email: string (email), roles: string[] }`, with a test for a valid payload, a malformed email, and an empty roles array (decide whether empty means "tenant_admin by default" and encode that decision in the schema, not the template).

- [ ] **Step 2: Mutation, returning the invalidation promise**

- [ ] **Step 3: An "Invite admin" action on the tenant detail page**

Opens a modal; on success swaps to `ActivationLinkPanel`.

A `409` (already a member) must render through `getErrorMessage` with copy that says so — add `USER_ALREADY_MEMBER` (or whatever code IAM actually returns; read it) to `app/lib/errors/messages.ts`.

- [ ] **Step 4: Verify and commit**

```bash
cd apps/web-admin && pnpm vitest run && pnpm lint && pnpm typecheck
git add apps/web-admin/app apps/web-admin/tests
git commit -m "feat(web-admin): invite a tenant admin from the console"
```

---

### Task 10: Reset-password UI

**Files:**
- Create: `apps/web-admin/app/lib/mutations/reset-password.ts`
- Modify: `apps/web-admin/app/pages/users/[id].vue`
- Modify: `apps/web-admin/app/lib/errors/messages.ts`
- Test: `apps/web-admin/tests/unit/messages.spec.ts` (extend)

**Interfaces:**
- Consumes: Task 6's endpoint, and `<ActivationLinkPanel>`.

- [ ] **Step 1: Add the error copy and pin it**

`NO_RESET_AVAILABLE` must map to copy that names both causes — the user has never set a password, or the account is not active. Add a spec case asserting the mapping, following the `FEATURE_NOT_AVAILABLE` precedent: a typo in the key degrades silently to the generic fallback.

- [ ] **Step 2: Mutation + a "Reset password" action behind a `ConfirmDialog`**

This invalidates a credential; it deserves the same confirmation as suspend.

- [ ] **Step 3: Render the link on success, the reason on 409**

- [ ] **Step 4: Verify and commit**

```bash
cd apps/web-admin && pnpm vitest run && pnpm lint && pnpm typecheck
git add apps/web-admin/app apps/web-admin/tests
git commit -m "feat(web-admin): reset a tenant user's password from the console"
```

---

### Task 11: Show the failure reason on the registrations board

**Files:**
- Modify: `apps/web-admin/app/lib/api/types.ts` (`PendingRegistration`)
- Modify: `apps/web-admin/app/pages/registrations/index.vue`
- Test: `apps/web-admin/tests/unit/registrations.spec.ts` (extend)

**Interfaces:**
- Consumes: Task 7's `failure_reason`.

- [ ] **Step 1: Add the field to the type**

```ts
  failure_reason: string | null
```

- [ ] **Step 2: Add a column, and a pure formatter with tests**

A `failureReasonLabel(reason: string | null)` in `app/lib/format/display.ts` returning `NO_VALUE` for null. Test null, empty string, and a real message — the null case is the one that renders "null" on screen if it is missed.

- [ ] **Step 3: Update the page copy**

The board's description and empty state currently say `failed` never occurs. Task 7 gives that state a producer, so the copy must change. Re-read what is there before editing.

- [ ] **Step 4: Verify and commit**

```bash
cd apps/web-admin && pnpm vitest run && pnpm lint && pnpm typecheck
git add apps/web-admin/app apps/web-admin/tests
git commit -m "feat(web-admin): show why a registration failed"
```

---

### Task 12: Documentation

**Files:**
- Modify: `docs/internal/11_integration_contracts/apis/platform-service-api.md`
- Modify: `docs/internal/11_integration_contracts/apis/iam-service-api.md`
- Modify: `docs/internal/11_integration_contracts/apis/billing-service-api.md`

All in the PARENT repo.

- [ ] **Step 1: Document the four platform endpoints**

`POST /tenants`, `POST /tenants/{id}/invitations`, `POST /users/{id}/reset-password`, and the new `failure_reason` field on `GET /registrations`. Match the file's existing prose style.

State plainly for each link-returning endpoint: **the link is shown once and is not retrievable afterwards.**

- [ ] **Step 2: Document the IAM internal routes**

The two new `internal/*` routes, and the changed `POST /internal/users` response (`set_password_token`, `activation_link`), noting that the password is now optional and that omitting it yields a `pending` user.

- [ ] **Step 3: Document billing's changes**

The internal tenant-creation route, the optional `admin_password`, and `failure_reason` on `GET /internal/registrations`.

- [ ] **Step 4: Correct the Phase 1 roadmap's mailer claim**

`docs/superpowers/specs/2026-09-12-web-admin-roadmap-design.md` states there is no mail infrastructure. `iam-service/src/email.rs` exists with `Log` and `Resend` modes. Correct it to say delivery is unconfigured (`EMAIL_PROVIDER` defaults to `log`) and unverified, rather than absent.

- [ ] **Step 5: Verify every documented field exists**

Re-read each handler and confirm the documented names match the code. Phase 1 shipped docs that named fields the code did not have.

- [ ] **Step 6: Commit**

```bash
git add docs/internal docs/superpowers
git commit -m "docs: document phase 2 operator onboarding endpoints"
```

---

## Final verification

```bash
cd apps/backend && cargo test -p iam-service -p billing-service -p platform-service -- --test-threads=2
cd apps/backend && cargo clippy -p iam-service -p billing-service -p platform-service
cd apps/web-admin && pnpm vitest run && pnpm lint && pnpm typecheck
```

Then, with the stack running, walk the flow by hand — every Phase 1 defect that reached the operator was invisible to the test suite:

1. Create a tenant. Confirm a link comes back, and that it is shown once.
2. Open that link in a private window and set a password. Confirm login works.
3. Invite a second admin to the same tenant. Confirm the 409 path renders a real reason.
4. Reset a password for an active user; then attempt it for a `pending` user and confirm the console explains why rather than showing an empty success.
5. Force a registration failure (reuse an existing email) and confirm the reason appears on the board.
