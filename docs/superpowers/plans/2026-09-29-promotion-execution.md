# Promotion Execution (Plan 3c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an `approved` promotion run take effect — target year, per-student target homerooms, one-transaction execution that closes old enrollments, opens new ones, writes graduation/retention records and publishes three events — and turn graduates into alumni when their year closes.

**Architecture:** All new write logic lives in academic-ops' existing `promotion` module (CQRS split kept: `commands.rs` writes, `queries.rs` reads, `repo.rs` SQL, `http.rs` thin). Execution is one transaction that locks the run row, re-checks every precondition, then processes decisions row by row (spec §2.9). Events leave through the existing outbox; grading-service gains one consumer arm for the three new events. The `lulus → alumni` step rides the existing `academic_year.status_changed` consumer.

**Tech Stack:** Rust, Axum 0.7, SQLx 0.8, refinery, PostgreSQL 18, RabbitMQ (lapin), testcontainers.

**Spec:** `docs/superpowers/specs/2026-09-29-promotion-execution-design.md` — read it before any task. Parents: `2026-09-26-promotion-evaluation-design.md` (3b), `2026-09-23-promotion-design.md` (A1).

## Global Constraints

- Work in `apps/backend` on a new branch `feat/promotion-execution`, created from `feat/promotion-evaluation` (HEAD `a2d239a`, equal to `develop`).
- Follow `apps/backend/CONVENTIONS.md`. No HTTP between services; projections and events only.
- Migrations: refinery, re-runnable (`IF NOT EXISTS`, drop-then-add constraints). **Never edit an applied migration** (academic-ops V1–V18). Next free: academic-ops **V19**. grading-service gets **no** migration (its `enrolled_student_status_chk` already accepts `promoted`, grading V13).
- Envelope via the existing `envelope` helper; validation errors via `AppError::validation_error(BTreeMap<String, Vec<String>>)`; `AppError::validation_error_single(field, msg)` for one message.
- Feature guard: existing `AcademicOpsEntitlement`. Permission for all three new endpoints: `PERM_PROMOTION_MANAGE` via `auth.require_permission(...)`.
- `tenant_id` always from `AuthContext`. **Every new query and every write filters by `tenant_id`.** A run of another tenant is `404`, never `403`.
- No new error codes: `VALIDATION_ERROR`, `PROMOTION_RUN_INVALID_STATUS` (409), `FORBIDDEN`, 404, `FEATURE_NOT_AVAILABLE`.
- Only the constraint `enrollment_one_active_per_student_year_uidx` is mapped from `23505` to `400`; every other database error stays `500` (spec §4).
- Commit per task, message only, **no trailers**.
- Test cadence per `apps/backend/CONVENTIONS.md` §7.1: each task runs `cargo check --workspace` plus **only its own new tests** with `--exact`, RED shown as a real failing assertion (a 404/405 because the route does not exist yet counts; "0 tests matched" does not). **No full suite inside Tasks 1–7.** Integration tests use `-- --test-threads=2`; never run two cargo test processes at once (memory-constrained workstation). A `StartupTimeout` failure counts as clean only if the test passes when re-run alone.
- Known pre-existing failures that must not grow — academic-ops: `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url`; grading: `grade_read_permits_teacher_and_denies_super_admin`, `report_read_permits_teacher_and_denies_super_admin`.

## Review Focus

1. **Double click on execute.** Two concurrent executions: exactly one 200, one `409 PROMOTION_RUN_INVALID_STATUS`, and no duplicated enrollment. Pinned in Task 5 (`execute_concurrent_yields_one_execution`).
2. **The world moved between approval and execution.** A student transferred, or enrolled by hand into the target year, after approval: `400`, nothing written. Pinned in Task 5 (`execute_rejects_conflicts_together`, `execute_rejects_old_enrollment_no_longer_active`).
3. **Target year changed after targets were set.** Every target is cleared, and execute then reports the missing targets instead of using homerooms of the wrong year. Pinned in Task 2 (`set_target_year_clears_existing_targets`) and Task 5 (`execute_rejects_conflicts_together`).
4. **Grade ladder edited after assignment.** A target homeroom whose grade level was relinked or renumbered is reported stale, not silently used. Pinned in Task 5 (`execute_rejects_stale_target_homeroom`).
5. **Guessed run ids across tenants on the new endpoints.** Tenant B gets 404 on target, targets and execute for tenant A's run. Pinned in Task 5 (`execution_endpoints_hide_other_tenant_runs`).

---

### Task 1: Migration V19 and the `promoted` enrollment status

**Files:**
- Create: `services/academic-ops-service/migrations/V19__promotion_execution.sql`
- Modify: `services/academic-ops-service/src/domain.rs` (`EnrollmentStatus`, lines 5–33; its `#[cfg(test)]` block ~line 258)
- Modify: `services/academic-ops-service/tests/integration.rs` (`seed_promotion_run_with_status`, ~line 4650)
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: columns `promotion_run.target_academic_year_id UUID NULL`, `promotion_run.executed_by UUID NULL`, `promotion_decision.target_enrollment_id UUID NULL`; constraints `promotion_run_executed_chk`, `promotion_decision_graduate_no_target_chk`; `EnrollmentStatus::Promoted` (`as_str() == "promoted"`, `from_str("promoted")`).

Why the helper change: `promotion_run_executed_run_does_not_block_a_new_one` inserts an `executed` run without `executed_at`; V19's check would reject it. Production never wrote `executed` before this plan, so only that helper needs it.

- [ ] **Step 1: Write the failing tests** (append to `tests/integration.rs`, near the other `promotion_run_*` constraint tests):

```rust
// --- Plan 3c Task 1: V19 ----------------------------------------------------

#[tokio::test]
async fn promotion_run_executed_requires_audit_trail() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;

    let err = sqlx::query(
        "UPDATE promotion_run SET status = 'executed' WHERE tenant_id = $1 AND run_id = $2",
    )
    .bind(tenant_id)
    .bind(run_id)
    .execute(&pool)
    .await
    .expect_err("executed without executed_at/executed_by/target year must be rejected");
    let db_err = err.as_database_error().expect("database error");
    assert_eq!(db_err.constraint(), Some("promotion_run_executed_chk"));

    sqlx::query(
        "UPDATE promotion_run SET status = 'executed', executed_at = NOW(), executed_by = $3, \
                target_academic_year_id = $4 \
         WHERE tenant_id = $1 AND run_id = $2",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .execute(&pool)
    .await
    .expect("an executed run with its audit trail is accepted");
}

#[tokio::test]
async fn promotion_decision_graduate_cannot_have_target() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;

    let err = sqlx::query(
        "INSERT INTO promotion_decision \
         (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
          homeroom_id, recommended, result, computed_metrics, target_homeroom_id) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'graduate', 'graduate', '{}'::jsonb, $8)",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(run_id)
    .bind(tenant_id)
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .execute(&pool)
    .await
    .expect_err("a graduate with a target homeroom must be rejected");
    let db_err = err.as_database_error().expect("database error");
    assert_eq!(db_err.constraint(), Some("promotion_decision_graduate_no_target_chk"));
}
```

And in `src/domain.rs` `#[cfg(test)] mod tests`:

```rust
#[test]
fn enrollment_status_round_trips_promoted() {
    assert_eq!(EnrollmentStatus::Promoted.as_str(), "promoted");
    assert_eq!(
        EnrollmentStatus::from_str("promoted").unwrap(),
        EnrollmentStatus::Promoted
    );
}
```

- [ ] **Step 2: Run, expect failures.**
`cargo test -p academic-ops-service --lib enrollment_status_round_trips_promoted` → compile error (no `Promoted`).
`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact promotion_run_executed_requires_audit_trail promotion_decision_graduate_cannot_have_target` → first fails because the bare `executed` UPDATE succeeds (`expect_err` panics); second fails because the INSERT succeeds.

- [ ] **Step 3: Implement.** `migrations/V19__promotion_execution.sql`:

```sql
-- Plan 3c: promotion execution.
--
-- promotion_run.target_academic_year_id is chosen by the admin once the run is
-- approved (spec §2.1). Changing it clears every decision's
-- target_homeroom_id in the same transaction (spec §5.1), so a target
-- homeroom always belongs to the run's current target year.
--
-- promotion_decision.target_enrollment_id records the enrollment execution
-- created, so "where did this student go" is answerable without guessing.
--
-- Idempotent: the dev database receives promotion migrations by hand until
-- refinery's history catches up.

ALTER TABLE promotion_run
  ADD COLUMN IF NOT EXISTS target_academic_year_id UUID NULL,
  ADD COLUMN IF NOT EXISTS executed_by             UUID NULL;

ALTER TABLE promotion_decision
  ADD COLUMN IF NOT EXISTS target_enrollment_id UUID NULL;

ALTER TABLE promotion_run DROP CONSTRAINT IF EXISTS promotion_run_executed_chk;
ALTER TABLE promotion_run ADD CONSTRAINT promotion_run_executed_chk CHECK (
  status <> 'executed'
  OR (executed_at IS NOT NULL
      AND executed_by IS NOT NULL
      AND target_academic_year_id IS NOT NULL)
);

ALTER TABLE promotion_decision DROP CONSTRAINT IF EXISTS promotion_decision_graduate_no_target_chk;
ALTER TABLE promotion_decision ADD CONSTRAINT promotion_decision_graduate_no_target_chk CHECK (
  result <> 'graduate' OR target_homeroom_id IS NULL
);
```

`src/domain.rs`: add `Promoted` to `EnrollmentStatus`, `Self::Promoted => "promoted"` in `as_str`, `"promoted" => Ok(Self::Promoted)` in `from_str`. Fix any non-exhaustive `match` the compiler reports.

`tests/integration.rs`, `seed_promotion_run_with_status`: write the audit columns when seeding `executed`:

```rust
    let executed = status == "executed";
    let run_id = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO promotion_run \
         (run_id, tenant_id, academic_year_id, rule_id, status, created_by, report_type_id, \
          executed_at, executed_by, target_academic_year_id) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, \
                 CASE WHEN $8 THEN NOW() END, $9, $10)",
    )
    .bind(run_id)
    .bind(tenant_id)
    .bind(academic_year_id)
    .bind(rule_id)
    .bind(status)
    .bind(uuid::Uuid::new_v4())
    .bind(uuid::Uuid::new_v4())
    .bind(executed)
    .bind(executed.then(uuid::Uuid::new_v4))
    .bind(executed.then(uuid::Uuid::new_v4))
    .execute(pool)
    .await
    .expect("seed promotion run should insert");
    run_id
```

- [ ] **Step 4: Run, expect PASS** — the three new tests, plus `--exact promotion_run_executed_run_does_not_block_a_new_one` (proves the helper change), then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): add promotion execution columns and the promoted enrollment status`

---

### Task 2: Target academic year (`PUT /promotion-runs/:run_id/target`) and the extended run shape

**Files:**
- Modify: `services/academic-ops-service/src/promotion/repo.rs`
- Modify: `services/academic-ops-service/src/promotion/commands.rs`
- Modify: `services/academic-ops-service/src/promotion/queries.rs` (`PromotionRunView`, `From<RunViewRow>`)
- Modify: `services/academic-ops-service/src/promotion/http.rs`
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 1 columns.
- Produces (used by Tasks 3–5):
  - `repo::LockedRun { status: String, academic_year_id: Uuid, target_academic_year_id: Option<Uuid> }` and `repo::lock_run_row(conn: &mut PgConnection, tenant_id, run_id) -> sqlx::Result<Option<LockedRun>>` (`SELECT … FOR UPDATE`, tenant-scoped).
  - `repo::known_year_status_on(conn, tenant_id, academic_year_id) -> sqlx::Result<Option<String>>`.
  - `RunViewRow` / `PromotionRunView` gain `target_academic_year_id: Option<Uuid>`, `executed_by: Option<Uuid>`, `executed_at: Option<DateTime<Utc>>`.
  - `commands::SetTargetYear { tenant_id, run_id, target_academic_year_id }`, `commands::set_target_year(&AppState, SetTargetYear) -> Result<SetTargetOutcome, AppError>`, `SetTargetOutcome { #[serde(flatten)] run: PromotionRunView, cleared_targets: u64 }`.
  - Test helpers `ExecutionFixture`, `approved_execution_fixture`, `put_target_req`, `decision_id_of` (below), reused by Tasks 3–5.

**Run-shape refactor (needed, not optional):** `find_run_detail` already selects a 14-column tuple; three more columns exceed SQLx's 16-element tuple `FromRow`. Replace `RunViewTuple`/`run_view_row` with a derived row:

```rust
#[derive(sqlx::FromRow)]
pub struct RunViewRow {
    pub run_id: Uuid,
    pub tenant_id: Uuid,
    pub academic_year_id: Uuid,
    pub report_type_id: Uuid,
    pub rule_id: Uuid,
    pub status: String,
    pub created_by: Uuid,
    pub approved_by: Option<Uuid>,
    pub target_academic_year_id: Option<Uuid>,
    pub executed_by: Option<Uuid>,
    pub executed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Column list every run-shaped SELECT/RETURNING uses, so the shape cannot drift.
pub const RUN_VIEW_COLUMNS: &str = "run_id, tenant_id, academic_year_id, report_type_id, rule_id, \
     status, created_by, approved_by, target_academic_year_id, executed_by, executed_at, \
     created_at, updated_at";

#[derive(sqlx::FromRow)]
pub struct RunDetailRow {
    #[sqlx(flatten)]
    pub run: RunViewRow,
    pub min_average: Option<f64>,
    pub max_subjects_below_kkm: Option<i32>,
    pub min_attendance_percent: Option<f64>,
    pub kkm_snapshot: f64,
}
```

`list_runs`, `transition_run` and `find_run_detail` switch to `sqlx::query_as::<_, RunViewRow>` / `query_as::<_, RunDetailRow>` with `format!` over `RUN_VIEW_COLUMNS` (in `find_run_detail` prefix every run column with `r.` explicitly; keep the `JOIN promotion_rule_snapshot s ON s.rule_id = r.rule_id AND s.tenant_id = r.tenant_id`). Keep the `Deref` impl. `PromotionRunView` gets the three new fields and `From<RunViewRow>` copies them.

**Test helpers** (add once, in a `// --- Plan 3c: execution fixtures` section after the Task 8 transition helpers):

```rust
struct ExecutionFixture {
    fx: PromotionFixture,
    run_id: uuid::Uuid,
    admin_token: String,
    target_year_id: uuid::Uuid,
    /// Target-year homeroom at ordinal 1 (where `retain_student` goes).
    target_mid_homeroom: uuid::Uuid,
    /// Target-year homeroom at ordinal 2 (where `promote_student` goes).
    target_final_homeroom: uuid::Uuid,
    promote_student: uuid::Uuid,
    retain_student: uuid::Uuid,
    graduate_student: uuid::Uuid,
}

/// Source year from `seed_promotion_fixture` (Mid ordinal 1, Final ordinal 2)
/// with three students: one promotes, one retains (2 subjects below KKM 75
/// with max 1), one graduates. The run is created by a tenant_admin and
/// approved by a different principal. A Draft target year with the same
/// two-level ladder and one homeroom per level is seeded but NOT set on the run.
async fn approved_execution_fixture(pool: &PgPool, state: &AppState) -> ExecutionFixture {
    let fx = seed_promotion_fixture(pool, state).await;
    let promote_student = seed_promoted_student(pool, &fx, fx.mid_homeroom, &[90.0, 90.0]).await;
    let retain_student =
        seed_promoted_student(pool, &fx, fx.mid_homeroom, &[60.0, 60.0, 90.0]).await;
    let graduate_student = seed_promoted_student(pool, &fx, fx.final_homeroom, &[90.0]).await;

    let admin_token = jwt_for(fx.tenant_id);
    let app = academic_ops_service::http::router(state.clone());
    let (status, body) = create_run(
        app.clone(),
        &admin_token,
        json!({ "academic_year_id": fx.year_id, "max_subjects_below_kkm": 1 }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    let run_id: uuid::Uuid = body["data"]["run_id"].as_str().unwrap().parse().unwrap();
    let (status, _) = submit_run_req(app.clone(), &admin_token, run_id).await;
    assert_eq!(status, StatusCode::OK);
    let (principal_token, _) =
        common_testing::mint_jwt(uuid::Uuid::new_v4(), fx.tenant_id, "principal");
    let (status, _) = approve_run_req(app, &principal_token, run_id).await;
    assert_eq!(status, StatusCode::OK);

    let target_year_id = seed_year(pool, fx.tenant_id, "Draft").await;
    let target_mid_level = uuid::Uuid::new_v4();
    let target_final_level = uuid::Uuid::new_v4();
    for (level, code, ordinal, is_final) in [
        (target_mid_level, "M", 1, false),
        (target_final_level, "F", 2, true),
    ] {
        sqlx::query(
            "INSERT INTO known_grade_level \
             (tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final) \
             VALUES ($1, $2, $3, $4, $4, $5, $6)",
        )
        .bind(fx.tenant_id)
        .bind(level)
        .bind(target_year_id)
        .bind(code)
        .bind(ordinal)
        .bind(is_final)
        .execute(pool)
        .await
        .unwrap();
    }
    let target_mid_homeroom = seed_homeroom(pool, fx.tenant_id, target_year_id, "Mid-B", "M").await;
    let target_final_homeroom =
        seed_homeroom(pool, fx.tenant_id, target_year_id, "Final-B", "F").await;
    for (homeroom, level) in [
        (target_mid_homeroom, target_mid_level),
        (target_final_homeroom, target_final_level),
    ] {
        sqlx::query("UPDATE homeroom SET grade_level_id = $1 WHERE homeroom_id = $2")
            .bind(level)
            .bind(homeroom)
            .execute(pool)
            .await
            .unwrap();
    }

    ExecutionFixture {
        fx,
        run_id,
        admin_token,
        target_year_id,
        target_mid_homeroom,
        target_final_homeroom,
        promote_student,
        retain_student,
        graduate_student,
    }
}

async fn put_target_req(
    app: axum::Router,
    token: &str,
    run_id: uuid::Uuid,
    target_academic_year_id: uuid::Uuid,
) -> (StatusCode, Value) {
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/v1/academic-ops/promotion-runs/{run_id}/target"))
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({ "target_academic_year_id": target_academic_year_id }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    (status, body_to_json(resp).await)
}

async fn decision_id_of(pool: &PgPool, run_id: uuid::Uuid, student_id: uuid::Uuid) -> uuid::Uuid {
    sqlx::query_scalar("SELECT decision_id FROM promotion_decision WHERE run_id = $1 AND student_id = $2")
        .bind(run_id)
        .bind(student_id)
        .fetch_one(pool)
        .await
        .unwrap()
}
```

- [ ] **Step 1: Write the failing tests:**

```rust
#[tokio::test]
async fn set_target_year_sets_year_and_returns_run_shape() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);

    let (status, body) = put_target_req(app, &ex.admin_token, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["target_academic_year_id"], ex.target_year_id.to_string());
    assert_eq!(body["data"]["status"], "approved");
    assert_eq!(body["data"]["cleared_targets"], 0);
    assert!(body["data"]["executed_at"].is_null());
}

#[tokio::test]
async fn set_target_year_rejects_invalid_years_together() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);

    // The source year itself.
    let (status, body) = put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.fx.year_id).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    let msgs = body["error"]["fields"]["target_academic_year_id"].as_array().unwrap();
    assert!(msgs.iter().any(|m| m == "target academic year must differ from the run's academic year"));

    // Another tenant's year.
    let foreign_year = seed_year(&pool, uuid::Uuid::new_v4(), "Draft").await;
    let (status, body) = put_target_req(app.clone(), &ex.admin_token, ex.run_id, foreign_year).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let msgs = body["error"]["fields"]["target_academic_year_id"].as_array().unwrap();
    assert!(msgs.iter().any(|m| m == "academic year not found"));

    // A Closed year with no grade levels: two failures in one response.
    let closed_year = seed_year(&pool, ex.fx.tenant_id, "Closed").await;
    let (status, body) = put_target_req(app, &ex.admin_token, ex.run_id, closed_year).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let msgs = body["error"]["fields"]["target_academic_year_id"].as_array().unwrap();
    assert!(msgs.iter().any(|m| m == "target academic year must not be Closed or Archived"));
    assert!(msgs.iter().any(|m| m == "target academic year has no grade level with ordinal 1"));
    assert!(msgs.iter().any(|m| m == "target academic year has no grade level with ordinal 2"));

    let target: Option<uuid::Uuid> =
        sqlx::query_scalar("SELECT target_academic_year_id FROM promotion_run WHERE run_id = $1")
            .bind(ex.run_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(target, None, "a rejected request writes nothing");
}

#[tokio::test]
async fn set_target_year_clears_existing_targets() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    let (status, _) = put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::OK);

    // Targets are written by Task 3's endpoint; seed one directly here.
    let decision = decision_id_of(&pool, ex.run_id, ex.promote_student).await;
    sqlx::query("UPDATE promotion_decision SET target_homeroom_id = $1 WHERE decision_id = $2")
        .bind(ex.target_final_homeroom)
        .bind(decision)
        .execute(&pool)
        .await
        .unwrap();

    // Re-setting the same year keeps targets.
    let (status, body) = put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["data"]["cleared_targets"], 0);

    // A different valid year clears them.
    let other_year = seed_year(&pool, ex.fx.tenant_id, "Draft").await;
    for (code, ordinal) in [("M", 1), ("F", 2)] {
        sqlx::query(
            "INSERT INTO known_grade_level \
             (tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final) \
             VALUES ($1, $2, $3, $4, $4, $5, $5 = 2)",
        )
        .bind(ex.fx.tenant_id)
        .bind(uuid::Uuid::new_v4())
        .bind(other_year)
        .bind(code)
        .bind(ordinal)
        .execute(&pool)
        .await
        .unwrap();
    }
    let (status, body) = put_target_req(app, &ex.admin_token, ex.run_id, other_year).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["cleared_targets"], 1);
    let target: Option<uuid::Uuid> =
        sqlx::query_scalar("SELECT target_homeroom_id FROM promotion_decision WHERE decision_id = $1")
            .bind(decision)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(target, None);
}

#[tokio::test]
async fn set_target_year_requires_approved_run() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let fx = seed_promotion_fixture(&pool, &state).await;
    seed_promoted_student(&pool, &fx, fx.mid_homeroom, &[90.0]).await;
    let token = jwt_for(fx.tenant_id);
    let app = academic_ops_service::http::router(state);
    let (_, body) = create_run(app.clone(), &token, json!({ "academic_year_id": fx.year_id })).await;
    let run_id: uuid::Uuid = body["data"]["run_id"].as_str().unwrap().parse().unwrap();
    let target_year = seed_year(&pool, fx.tenant_id, "Draft").await;

    let (status, body) = put_target_req(app, &token, run_id, target_year).await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["error"]["code"], "PROMOTION_RUN_INVALID_STATUS");
}
```

- [ ] **Step 2: Run, expect FAIL** — `--exact` the four tests: the route does not exist, so the first assertion sees `405`/`404` instead of `200`/`400`/`409`.

- [ ] **Step 3: Implement.**

`repo.rs` — new functions (all tenant-scoped, all on `&mut sqlx::PgConnection`):

```rust
pub struct LockedRun {
    pub status: String,
    pub academic_year_id: Uuid,
    pub target_academic_year_id: Option<Uuid>,
}

/// Locks the run row for a Plan 3c write and returns what those writes need.
pub async fn lock_run_row(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
) -> sqlx::Result<Option<LockedRun>> {
    let row: Option<(String, Uuid, Option<Uuid>)> = sqlx::query_as(
        "SELECT status, academic_year_id, target_academic_year_id FROM promotion_run \
         WHERE tenant_id = $1 AND run_id = $2 FOR UPDATE",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_optional(&mut *conn)
    .await?;
    Ok(row.map(|(status, academic_year_id, target_academic_year_id)| LockedRun {
        status,
        academic_year_id,
        target_academic_year_id,
    }))
}

pub async fn known_year_status_on(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    academic_year_id: Uuid,
) -> sqlx::Result<Option<String>> {
    sqlx::query_scalar(
        "SELECT status FROM known_academic_year WHERE tenant_id = $1 AND academic_year_id = $2",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .fetch_optional(&mut *conn)
    .await
}

/// Ordinals the run's promote/retain decisions need in the target year:
/// source ordinal + 1 for promote, the same ordinal for retain (spec §2.8).
pub async fn needed_target_ordinals(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
) -> sqlx::Result<Vec<i32>> {
    sqlx::query_scalar(
        "SELECT DISTINCT CASE WHEN d.result = 'promote' THEN kgl.ordinal + 1 ELSE kgl.ordinal END \
         FROM promotion_decision d \
         JOIN homeroom h ON h.tenant_id = d.tenant_id AND h.homeroom_id = d.homeroom_id \
         JOIN known_grade_level kgl \
           ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.result IN ('promote', 'retain') \
         ORDER BY 1",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_all(&mut *conn)
    .await
}

pub async fn year_ordinals(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    academic_year_id: Uuid,
) -> sqlx::Result<Vec<i32>> {
    sqlx::query_scalar(
        "SELECT ordinal FROM known_grade_level WHERE tenant_id = $1 AND academic_year_id = $2",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .fetch_all(&mut *conn)
    .await
}

pub async fn clear_decision_targets(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
) -> sqlx::Result<u64> {
    let outcome = sqlx::query(
        "UPDATE promotion_decision SET target_homeroom_id = NULL \
         WHERE tenant_id = $1 AND run_id = $2 AND target_homeroom_id IS NOT NULL",
    )
    .bind(tenant_id)
    .bind(run_id)
    .execute(&mut *conn)
    .await?;
    Ok(outcome.rows_affected())
}

/// Conditional on `status = 'approved'`; `None` means the run left `approved`.
pub async fn set_run_target_year(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    target_academic_year_id: Uuid,
) -> sqlx::Result<Option<RunViewRow>> {
    sqlx::query_as::<_, RunViewRow>(&format!(
        "UPDATE promotion_run SET target_academic_year_id = $3, updated_at = NOW() \
         WHERE tenant_id = $1 AND run_id = $2 AND status = 'approved' \
         RETURNING {RUN_VIEW_COLUMNS}"
    ))
    .bind(tenant_id)
    .bind(run_id)
    .bind(target_academic_year_id)
    .fetch_optional(&mut *conn)
    .await
}
```

`commands.rs`:

```rust
pub struct SetTargetYear {
    pub tenant_id: Uuid,
    pub run_id: Uuid,
    pub target_academic_year_id: Uuid,
}

#[derive(Serialize)]
pub struct SetTargetOutcome {
    #[serde(flatten)]
    pub run: crate::promotion::queries::PromotionRunView,
    pub cleared_targets: u64,
}

/// Spec §5.1. Locks the run, validates the year (all failures together),
/// clears every target when the year changes, then sets the year.
pub async fn set_target_year(
    state: &AppState,
    input: SetTargetYear,
) -> Result<SetTargetOutcome, AppError> {
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let run = repo::lock_run_row(&mut tx, input.tenant_id, input.run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "approved" {
        return Err(transition_invalid_status_error("approved"));
    }

    let field = "target_academic_year_id";
    let mut messages: Vec<String> = Vec::new();
    let year_status = repo::known_year_status_on(&mut tx, input.tenant_id, input.target_academic_year_id)
        .await
        .map_err(AppError::internal)?;
    match year_status.as_deref() {
        None => messages.push("academic year not found".to_string()),
        Some("Closed") | Some("Archived") => {
            messages.push("target academic year must not be Closed or Archived".to_string())
        }
        Some(_) => {}
    }
    if input.target_academic_year_id == run.academic_year_id {
        messages.push("target academic year must differ from the run's academic year".to_string());
    }
    if year_status.is_some() {
        let needed = repo::needed_target_ordinals(&mut tx, input.tenant_id, input.run_id)
            .await
            .map_err(AppError::internal)?;
        let available = repo::year_ordinals(&mut tx, input.tenant_id, input.target_academic_year_id)
            .await
            .map_err(AppError::internal)?;
        for ordinal in needed.into_iter().filter(|o| !available.contains(o)) {
            messages.push(format!("target academic year has no grade level with ordinal {ordinal}"));
        }
    }
    if !messages.is_empty() {
        let mut errors = BTreeMap::new();
        errors.insert(field.to_string(), messages);
        return Err(AppError::validation_error(errors));
    }

    let cleared_targets = if run.target_academic_year_id != Some(input.target_academic_year_id) {
        repo::clear_decision_targets(&mut tx, input.tenant_id, input.run_id)
            .await
            .map_err(AppError::internal)?
    } else {
        0
    };

    let row = repo::set_run_target_year(&mut tx, input.tenant_id, input.run_id, input.target_academic_year_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| transition_invalid_status_error("approved"))?;

    tx.commit().await.map_err(AppError::internal)?;
    Ok(SetTargetOutcome {
        run: crate::promotion::queries::PromotionRunView::from(row),
        cleared_targets,
    })
}
```

`http.rs`: add `put` to the routing import, a route `"/api/v1/academic-ops/promotion-runs/:run_id/target"` → `put(set_promotion_run_target)`, and:

```rust
#[derive(Debug, Deserialize)]
struct SetTargetBody {
    target_academic_year_id: Uuid,
}

async fn set_promotion_run_target(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path(run_id): Path<Uuid>,
    Json(body): Json<SetTargetBody>,
) -> Result<Json<Value>, AppError> {
    auth.require_permission(PERM_PROMOTION_MANAGE)?;
    let outcome = commands::set_target_year(
        &state,
        commands::SetTargetYear {
            tenant_id: auth.tenant_id,
            run_id,
            target_academic_year_id: body.target_academic_year_id,
        },
    )
    .await?;
    Ok(envelope(outcome))
}
```

- [ ] **Step 4: Run, expect PASS** — the four new tests; then the 3b read/transition tests that touch the refactored row (`--exact list_promotion_runs_filters_by_year promotion_run_detail_includes_counts_criteria_and_cannot_evaluate promotion_transition_submit_then_approve`); then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): set the target academic year of an approved promotion run`

---

### Task 3: Bulk target homerooms (`PATCH /promotion-runs/:run_id/targets`) and the extended decision shape

**Files:**
- Modify: `services/academic-ops-service/src/promotion/{repo,commands,queries,http}.rs`
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: `repo::lock_run_row`, `ExecutionFixture`, `approved_execution_fixture`, `put_target_req`, `decision_id_of` (Task 2).
- Produces:
  - `DecisionView` / `DecisionListRow` gain `target_homeroom_id: Option<Uuid>`, `target_enrollment_id: Option<Uuid>` (the override command fills them from the decision row it read — extend `repo::DecisionRow` and `find_decision`'s SELECT accordingly).
  - `commands::TargetAssignment { decision_id: Uuid, homeroom_id: Option<Uuid> }`, `commands::AssignTargets { tenant_id, run_id, assignments: Vec<TargetAssignment> }`, `commands::assign_targets(&AppState, AssignTargets) -> Result<AssignTargetsOutcome, AppError>`, `AssignTargetsOutcome { updated: u64 }`.
  - `repo::update_decision_target(conn, tenant_id, run_id, decision_id, homeroom_id: Option<Uuid>) -> sqlx::Result<u64>`.
  - Test helper `patch_targets_req(app, token, run_id, assignments: Value) -> (StatusCode, Value)` (uses `patch_json`).

Validation rules (spec §5.2) — exact messages, all collected under field `assignments`:

| Condition | Message |
|---|---|
| more than 2,000 items | `at most 2000 assignments per request` (checked first, alone) |
| same `decision_id` twice | `decision {id}: assigned more than once` |
| decision not in this run (or another tenant) | `decision {id}: not in this run` |
| decision result `graduate` with a non-null homeroom | `decision {id}: graduating students have no target homeroom` |
| homeroom not found in this tenant | `decision {id}: homeroom {homeroom_id} not found` |
| homeroom not in the run's target year | `decision {id}: homeroom {name} is not in the target academic year` |
| homeroom has no (or a dangling) grade level | `decision {id}: homeroom {name} is not linked to a grade level` |
| ordinal mismatch | `decision {id}: homeroom {name} is ordinal {actual}, expected {expected}` |

Run not `approved` → 409 (`transition_invalid_status_error("approved")`). Run has no target year → `400` field `target_academic_year_id`, message `set the target academic year first`. A `null` homeroom always clears, for any result.

- [ ] **Step 1: Write the failing tests:**

```rust
async fn patch_targets_req(
    app: axum::Router,
    token: &str,
    run_id: uuid::Uuid,
    assignments: Value,
) -> (StatusCode, Value) {
    patch_json(
        app,
        token,
        &format!("/api/v1/academic-ops/promotion-runs/{run_id}/targets"),
        json!({ "assignments": assignments }),
    )
    .await
}

#[tokio::test]
async fn assign_targets_writes_promote_and_retain_targets() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    let promote = decision_id_of(&pool, ex.run_id, ex.promote_student).await;
    let retain = decision_id_of(&pool, ex.run_id, ex.retain_student).await;

    let (status, body) = patch_targets_req(
        app.clone(),
        &ex.admin_token,
        ex.run_id,
        json!([
            { "decision_id": promote, "homeroom_id": ex.target_final_homeroom },
            { "decision_id": retain, "homeroom_id": ex.target_mid_homeroom },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["updated"], 2);

    let (_, decisions) = get_json(
        app.clone(),
        &ex.admin_token,
        &format!("/api/v1/academic-ops/promotion-runs/{}/decisions", ex.run_id),
    )
    .await;
    let promote_view = decisions["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["decision_id"] == promote.to_string())
        .unwrap();
    assert_eq!(promote_view["target_homeroom_id"], ex.target_final_homeroom.to_string());
    assert!(promote_view["target_enrollment_id"].is_null());

    // null clears.
    let (status, _) = patch_targets_req(
        app,
        &ex.admin_token,
        ex.run_id,
        json!([{ "decision_id": promote, "homeroom_id": null }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let target: Option<uuid::Uuid> =
        sqlx::query_scalar("SELECT target_homeroom_id FROM promotion_decision WHERE decision_id = $1")
            .bind(promote)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(target, None);
}

#[tokio::test]
async fn assign_targets_rejects_the_whole_batch_and_reports_every_error() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    let promote = decision_id_of(&pool, ex.run_id, ex.promote_student).await;
    let retain = decision_id_of(&pool, ex.run_id, ex.retain_student).await;
    let graduate = decision_id_of(&pool, ex.run_id, ex.graduate_student).await;
    let foreign_homeroom = seed_homeroom(
        &pool,
        uuid::Uuid::new_v4(),
        seed_year(&pool, uuid::Uuid::new_v4(), "Draft").await,
        "Foreign",
        "M",
    )
    .await;

    let (status, body) = patch_targets_req(
        app,
        &ex.admin_token,
        ex.run_id,
        json!([
            // valid on its own — must NOT be written because the batch fails
            { "decision_id": retain, "homeroom_id": ex.target_mid_homeroom },
            // promote needs ordinal 2, Mid-B is ordinal 1
            { "decision_id": promote, "homeroom_id": ex.target_mid_homeroom },
            // graduates get no homeroom
            { "decision_id": graduate, "homeroom_id": ex.target_final_homeroom },
            // homeroom of the SOURCE year
            { "decision_id": retain, "homeroom_id": ex.fx.mid_homeroom },
            // another tenant's homeroom
            { "decision_id": uuid::Uuid::new_v4(), "homeroom_id": foreign_homeroom },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    let msgs: Vec<String> = body["error"]["fields"]["assignments"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m.as_str().unwrap().to_string())
        .collect();
    assert!(msgs.contains(&format!("decision {promote}: homeroom Mid-B is ordinal 1, expected 2")), "{msgs:?}");
    assert!(msgs.contains(&format!("decision {graduate}: graduating students have no target homeroom")));
    assert!(msgs.contains(&format!("decision {retain}: assigned more than once")));
    assert!(msgs.iter().any(|m| m.ends_with(": not in this run")));

    let written: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM promotion_decision WHERE run_id = $1 AND target_homeroom_id IS NOT NULL",
    )
    .bind(ex.run_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(written, 0, "one bad item rejects the whole batch");
}

#[tokio::test]
async fn assign_targets_rejects_homeroom_outside_target_year() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    let retain = decision_id_of(&pool, ex.run_id, ex.retain_student).await;

    let (status, body) = patch_targets_req(
        app,
        &ex.admin_token,
        ex.run_id,
        json!([{ "decision_id": retain, "homeroom_id": ex.fx.mid_homeroom }]),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(
        body["error"]["fields"]["assignments"][0],
        format!("decision {retain}: homeroom Mid-A is not in the target academic year")
    );
}

#[tokio::test]
async fn assign_targets_requires_target_year_first() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    let retain = decision_id_of(&pool, ex.run_id, ex.retain_student).await;

    let (status, body) = patch_targets_req(
        app,
        &ex.admin_token,
        ex.run_id,
        json!([{ "decision_id": retain, "homeroom_id": ex.target_mid_homeroom }]),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(
        body["error"]["fields"]["target_academic_year_id"][0],
        "set the target academic year first"
    );
}

#[tokio::test]
async fn update_decision_target_is_scoped_to_tenant_and_run() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let decision = decision_id_of(&pool, ex.run_id, ex.retain_student).await;
    let mut conn = pool.acquire().await.unwrap();
    use academic_ops_service::promotion::repo::update_decision_target;

    let rows = update_decision_target(&mut conn, uuid::Uuid::new_v4(), ex.run_id, decision, Some(ex.target_mid_homeroom))
        .await
        .unwrap();
    assert_eq!(rows, 0, "wrong tenant");
    let rows = update_decision_target(&mut conn, ex.fx.tenant_id, uuid::Uuid::new_v4(), decision, Some(ex.target_mid_homeroom))
        .await
        .unwrap();
    assert_eq!(rows, 0, "wrong run");
    let rows = update_decision_target(&mut conn, ex.fx.tenant_id, ex.run_id, decision, Some(ex.target_mid_homeroom))
        .await
        .unwrap();
    assert_eq!(rows, 1);
}
```

- [ ] **Step 2: Run, expect FAIL** — `--exact` the five tests (route missing → 405/404; the repo test fails to compile until `update_decision_target` exists — record the HTTP tests' failing assertions as RED).

- [ ] **Step 3: Implement.**

`repo.rs`:

```rust
/// Facts about the run's decisions that the target checks need.
pub struct DecisionTargetFacts {
    pub decision_id: Uuid,
    pub result: String,
    /// Ordinal of the decision's source homeroom; None if unlinked/dangling.
    pub source_ordinal: Option<i32>,
}

pub async fn decision_target_facts(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    decision_ids: &[Uuid],
) -> sqlx::Result<Vec<DecisionTargetFacts>> {
    let rows: Vec<(Uuid, String, Option<i32>)> = sqlx::query_as(
        "SELECT d.decision_id, d.result, kgl.ordinal \
         FROM promotion_decision d \
         LEFT JOIN homeroom h ON h.tenant_id = d.tenant_id AND h.homeroom_id = d.homeroom_id \
         LEFT JOIN known_grade_level kgl \
           ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.decision_id = ANY($3)",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(decision_ids)
    .fetch_all(&mut *conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(decision_id, result, source_ordinal)| DecisionTargetFacts { decision_id, result, source_ordinal })
        .collect())
}

pub struct HomeroomTargetFacts {
    pub homeroom_id: Uuid,
    pub name: String,
    pub academic_year_id: Uuid,
    /// None if the homeroom's grade level is unlinked or dangling.
    pub ordinal: Option<i32>,
}

pub async fn homeroom_target_facts(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    homeroom_ids: &[Uuid],
) -> sqlx::Result<Vec<HomeroomTargetFacts>> {
    let rows: Vec<(Uuid, String, Uuid, Option<i32>)> = sqlx::query_as(
        "SELECT h.homeroom_id, h.name, h.academic_year_id, kgl.ordinal \
         FROM homeroom h \
         LEFT JOIN known_grade_level kgl \
           ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id \
         WHERE h.tenant_id = $1 AND h.homeroom_id = ANY($2)",
    )
    .bind(tenant_id)
    .bind(homeroom_ids)
    .fetch_all(&mut *conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(homeroom_id, name, academic_year_id, ordinal)| HomeroomTargetFacts {
            homeroom_id,
            name,
            academic_year_id,
            ordinal,
        })
        .collect())
}

pub async fn update_decision_target(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    decision_id: Uuid,
    homeroom_id: Option<Uuid>,
) -> sqlx::Result<u64> {
    let outcome = sqlx::query(
        "UPDATE promotion_decision SET target_homeroom_id = $4 \
         WHERE tenant_id = $1 AND run_id = $2 AND decision_id = $3",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(decision_id)
    .bind(homeroom_id)
    .execute(&mut *conn)
    .await?;
    Ok(outcome.rows_affected())
}
```

Extend `DecisionListRow` (+ its tuple, + both SELECTs in `list_decisions_for_run`) and `DecisionRow` (+ `find_decision`) with `target_homeroom_id`, `target_enrollment_id`; extend `DecisionView` and both `From`/construction sites (`queries.rs` `From<DecisionListRow>`, `commands::override_decision`).

`commands.rs`:

```rust
pub const MAX_TARGET_ASSIGNMENTS: usize = 2000;

pub struct TargetAssignment {
    pub decision_id: Uuid,
    pub homeroom_id: Option<Uuid>,
}

pub struct AssignTargets {
    pub tenant_id: Uuid,
    pub run_id: Uuid,
    pub assignments: Vec<TargetAssignment>,
}

#[derive(Serialize)]
pub struct AssignTargetsOutcome {
    pub updated: u64,
}

/// Spec §5.2: all or nothing, every error reported under `assignments`.
pub async fn assign_targets(
    state: &AppState,
    input: AssignTargets,
) -> Result<AssignTargetsOutcome, AppError> {
    if input.assignments.len() > MAX_TARGET_ASSIGNMENTS {
        return Err(AppError::validation_error_single(
            "assignments",
            format!("at most {MAX_TARGET_ASSIGNMENTS} assignments per request"),
        ));
    }

    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let run = repo::lock_run_row(&mut tx, input.tenant_id, input.run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "approved" {
        return Err(transition_invalid_status_error("approved"));
    }
    let target_year = run.target_academic_year_id.ok_or_else(|| {
        AppError::validation_error_single("target_academic_year_id", "set the target academic year first")
    })?;

    let decision_ids: Vec<Uuid> = input.assignments.iter().map(|a| a.decision_id).collect();
    let homeroom_ids: Vec<Uuid> = input.assignments.iter().filter_map(|a| a.homeroom_id).collect();
    let decisions: std::collections::HashMap<Uuid, repo::DecisionTargetFacts> =
        repo::decision_target_facts(&mut tx, input.tenant_id, input.run_id, &decision_ids)
            .await
            .map_err(AppError::internal)?
            .into_iter()
            .map(|d| (d.decision_id, d))
            .collect();
    let homerooms: std::collections::HashMap<Uuid, repo::HomeroomTargetFacts> =
        repo::homeroom_target_facts(&mut tx, input.tenant_id, &homeroom_ids)
            .await
            .map_err(AppError::internal)?
            .into_iter()
            .map(|h| (h.homeroom_id, h))
            .collect();

    let mut messages = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for a in &input.assignments {
        let id = a.decision_id;
        if !seen.insert(id) {
            messages.push(format!("decision {id}: assigned more than once"));
            continue;
        }
        let Some(decision) = decisions.get(&id) else {
            messages.push(format!("decision {id}: not in this run"));
            continue;
        };
        let Some(homeroom_id) = a.homeroom_id else { continue };
        if decision.result == "graduate" {
            messages.push(format!("decision {id}: graduating students have no target homeroom"));
            continue;
        }
        let Some(homeroom) = homerooms.get(&homeroom_id) else {
            messages.push(format!("decision {id}: homeroom {homeroom_id} not found"));
            continue;
        };
        if homeroom.academic_year_id != target_year {
            messages.push(format!(
                "decision {id}: homeroom {} is not in the target academic year",
                homeroom.name
            ));
            continue;
        }
        let Some(actual) = homeroom.ordinal else {
            messages.push(format!(
                "decision {id}: homeroom {} is not linked to a grade level",
                homeroom.name
            ));
            continue;
        };
        let Some(source) = decision.source_ordinal else {
            // The source homeroom lost its grade level after evaluation; no
            // expected ordinal can be computed. Report it on the decision.
            messages.push(format!("decision {id}: its source homeroom is not linked to a grade level"));
            continue;
        };
        let expected = if decision.result == "promote" { source + 1 } else { source };
        if actual != expected {
            messages.push(format!(
                "decision {id}: homeroom {} is ordinal {actual}, expected {expected}",
                homeroom.name
            ));
        }
    }
    if !messages.is_empty() {
        let mut errors = BTreeMap::new();
        errors.insert("assignments".to_string(), messages);
        return Err(AppError::validation_error(errors));
    }

    let mut updated = 0;
    for a in &input.assignments {
        updated += repo::update_decision_target(&mut tx, input.tenant_id, input.run_id, a.decision_id, a.homeroom_id)
            .await
            .map_err(AppError::internal)?;
    }
    tx.commit().await.map_err(AppError::internal)?;
    Ok(AssignTargetsOutcome { updated })
}
```

`http.rs`: route `"/api/v1/academic-ops/promotion-runs/:run_id/targets"` → `patch(assign_promotion_targets)`; body `{ assignments: Vec<{ decision_id: Uuid, homeroom_id: Option<Uuid> }> }` (`#[derive(Deserialize)]` structs), `require_permission(PERM_PROMOTION_MANAGE)`, map into `commands::AssignTargets`, return `envelope(outcome)`.

- [ ] **Step 4: Run, expect PASS** — the five tests, plus `--exact override_changes_result_only promotion_run_decisions_filter_by_homeroom` (decision shape changed), then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): assign target homerooms to promotion decisions`

---

### Task 4: Placement report in the run detail

**Files:**
- Modify: `services/academic-ops-service/src/promotion/{repo,queries}.rs`
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 2/3 helpers.
- Produces: `PromotionRunDetail` gains `placement: Vec<PlacementView>` and `unassigned: i64`. `PlacementView { homeroom_id: Uuid, name: String, capacity: i32, existing_active: i64, assigned: i64, total: i64, over_capacity: bool }`, ordered by `name`. `repo::placement_rows(pool, tenant_id, run_id) -> sqlx::Result<Vec<(Uuid, String, i32, i64, i64)>>`, `repo::unassigned_count(pool, tenant_id, run_id) -> sqlx::Result<i64>`.

`existing_active` counts active enrollments in the homeroom **excluding enrollments created by this run** (`target_enrollment_id`), so the numbers mean the same thing before and after execution. Informational only (spec §2.4).

- [ ] **Step 1: Write the failing test:**

```rust
#[tokio::test]
async fn run_detail_reports_placement_against_capacity() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    let app = academic_ops_service::http::router(state);
    put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    sqlx::query("UPDATE homeroom SET capacity = 1 WHERE homeroom_id = $1")
        .bind(ex.target_mid_homeroom)
        .execute(&pool)
        .await
        .unwrap();
    // One student already active in Mid-B.
    let existing = seed_promoted_student(&pool, &ex.fx, ex.fx.mid_homeroom, &[]).await;
    sqlx::query(
        "INSERT INTO enrollment (enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id, status) \
         VALUES ($1, $2, $3, $4, $5, 'active')",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(ex.fx.tenant_id)
    .bind(existing)
    .bind(ex.target_mid_homeroom)
    .bind(ex.target_year_id)
    .execute(&pool)
    .await
    .unwrap();
    let retain = decision_id_of(&pool, ex.run_id, ex.retain_student).await;
    patch_targets_req(
        app.clone(),
        &ex.admin_token,
        ex.run_id,
        json!([{ "decision_id": retain, "homeroom_id": ex.target_mid_homeroom }]),
    )
    .await;

    let (status, body) = get_json(
        app,
        &ex.admin_token,
        &format!("/api/v1/academic-ops/promotion-runs/{}", ex.run_id),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let placement = body["data"]["placement"].as_array().unwrap();
    assert_eq!(placement.len(), 1);
    assert_eq!(placement[0]["homeroom_id"], ex.target_mid_homeroom.to_string());
    assert_eq!(placement[0]["name"], "Mid-B");
    assert_eq!(placement[0]["capacity"], 1);
    assert_eq!(placement[0]["existing_active"], 1);
    assert_eq!(placement[0]["assigned"], 1);
    assert_eq!(placement[0]["total"], 2);
    assert_eq!(placement[0]["over_capacity"], true);
    assert_eq!(body["data"]["unassigned"], 1, "the promoted student has no target yet");
}
```

- [ ] **Step 2: Run, expect FAIL** (`placement` is `null` → `as_array().unwrap()` panics).
- [ ] **Step 3: Implement.** `repo.rs`:

```rust
/// (homeroom_id, name, capacity, existing_active, assigned) per target homeroom of the run.
pub async fn placement_rows(
    pool: &PgPool,
    tenant_id: Uuid,
    run_id: Uuid,
) -> sqlx::Result<Vec<(Uuid, String, i32, i64, i64)>> {
    sqlx::query_as(
        "SELECT h.homeroom_id, h.name, h.capacity, \
                (SELECT count(*) FROM enrollment e \
                  WHERE e.tenant_id = h.tenant_id AND e.homeroom_id = h.homeroom_id \
                    AND e.status = 'active' \
                    AND e.enrollment_id NOT IN ( \
                        SELECT d2.target_enrollment_id FROM promotion_decision d2 \
                         WHERE d2.tenant_id = $1 AND d2.run_id = $2 \
                           AND d2.target_enrollment_id IS NOT NULL)) AS existing_active, \
                (SELECT count(*) FROM promotion_decision d \
                  WHERE d.tenant_id = $1 AND d.run_id = $2 \
                    AND d.target_homeroom_id = h.homeroom_id) AS assigned \
         FROM homeroom h \
         WHERE h.tenant_id = $1 \
           AND h.homeroom_id IN (SELECT target_homeroom_id FROM promotion_decision \
                                  WHERE tenant_id = $1 AND run_id = $2 \
                                    AND target_homeroom_id IS NOT NULL) \
         ORDER BY h.name, h.homeroom_id",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_all(pool)
    .await
}

pub async fn unassigned_count(pool: &PgPool, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<i64> {
    sqlx::query_scalar(
        "SELECT count(*) FROM promotion_decision \
         WHERE tenant_id = $1 AND run_id = $2 \
           AND result IN ('promote', 'retain') AND target_homeroom_id IS NULL",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_one(pool)
    .await
}
```

`queries.rs`: `#[derive(Serialize)] pub struct PlacementView { … }`; in `get_promotion_run` call both, map rows with `total = existing_active + assigned`, `over_capacity = total > capacity as i64`, add `placement` and `unassigned` to `PromotionRunDetail`.

- [ ] **Step 4: Run, expect PASS** (the new test + `--exact promotion_run_detail_includes_counts_criteria_and_cannot_evaluate`), then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): report target homeroom placement against capacity`

---

### Task 5: Execute (`POST /promotion-runs/:run_id/execute`)

**Files:**
- Modify: `services/academic-ops-service/src/promotion/{domain,repo,commands,http}.rs`
- Test: `services/academic-ops-service/src/promotion/domain.rs` (`mod tests`), `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `domain::retention_reason(overridden: bool, reason: Option<&str>, metrics: &serde_json::Value) -> Option<String>`.
  - `commands::execute_promotion_run(&AppState, tenant_id: Uuid, user_id: Uuid, run_id: Uuid) -> Result<ExecuteOutcome, AppError>`; `ExecuteOutcome { #[serde(flatten)] run: PromotionRunView, counts: ExecutionCounts }`; `ExecutionCounts { promoted: i64, retained: i64, graduated: i64 }`.
  - Outbox events `student.promoted`, `student.retained`, `student.graduated` with the payloads of spec §6.1 (Task 6 consumes them).
  - Test helpers `execute_req(app, token, run_id) -> (StatusCode, Value)` and `ready_to_execute(pool, state) -> (ExecutionFixture, axum::Router)` (target year set, both targets assigned).

**Algorithm** (spec §4) — `commands::execute_promotion_run`:

1. `tx = pool.begin()`; `repo::lock_run_row` → `None` = 404; status ≠ `approved` = `transition_invalid_status_error("approved")`.
2. Preconditions, all collected into one `BTreeMap` (400):
   - `target_academic_year`: `set the target academic year first` (none set) or `target academic year must not be Closed or Archived` (via `known_year_status_on`; a missing year also gets the first message).
   - `targets`: one `student {id} has no target homeroom` per promote/retain decision without a target.
   - `enrollments`: `student {id} is already enrolled in the target academic year` per promote/retain decision whose student is already active there; `student {id}'s enrollment is no longer active` per decision whose source enrollment is not `active`.
   - `target_homerooms`: `student {id}'s target homeroom is no longer valid` per decision whose target homeroom is gone, in another year, unlinked/dangling, or the wrong ordinal now.
   Each list comes from one repo query (below), sorted by `student_id`.
3. `repo::execution_rows` (ordered `homeroom_id, student_id`); for each row:
   - `close_source_enrollment` must return 1, else push `student {id}'s enrollment is no longer active` under `enrollments` and return 400 (dropping `tx` rolls back).
   - `promote`/`retain`: new `enrollment_id = Uuid::new_v4()`; `insert_target_enrollment` with the error mapped by `map_target_enrollment_error` (constraint `enrollment_one_active_per_student_year_uidx` → `AppError::validation_error_single("enrollments", format!("student {id} is already enrolled in the target academic year"))`, anything else `AppError::internal`); `set_target_enrollment` must return 1 (else internal).
   - `retain`: `insert_retention_record` with `retention_reason(...)`; `None` → `AppError::internal("retained decision {id} has neither an override reason nor a failed criterion")`.
   - `graduate`: `insert_graduation_record` (date = `chrono::Utc::now().date_naive()`), `set_student_lulus` must return 1.
   - enqueue the event (`state.outbox.enqueue(&mut *tx, Uuid::new_v4(), event_type, &payload)`).
4. `repo::mark_run_executed` (conditional on `approved`) → `None` = 409.
5. `tx.commit()`.

- [ ] **Step 1: Write the failing tests.**

`domain.rs` tests:

```rust
#[test]
fn retention_reason_prefers_the_override_reason() {
    let metrics = serde_json::json!({ "average": 90.0, "subjects_below_kkm": 0,
        "criteria": { "min_average": 70.0, "max_subjects_below_kkm": 2 } });
    assert_eq!(
        retention_reason(true, Some("Long absence, staff meeting agreed"), &metrics).as_deref(),
        Some("Long absence, staff meeting agreed")
    );
}

#[test]
fn retention_reason_summarises_failed_criteria() {
    let metrics = serde_json::json!({ "average": 65.23, "subjects_below_kkm": 3,
        "criteria": { "min_average": 70.0, "max_subjects_below_kkm": 2 } });
    assert_eq!(
        retention_reason(false, None, &metrics).as_deref(),
        Some("average 65.2 below 70; 3 subjects below KKM (max 2)")
    );
    let only_count = serde_json::json!({ "average": 80.0, "subjects_below_kkm": 2,
        "criteria": { "min_average": null, "max_subjects_below_kkm": 1 } });
    assert_eq!(
        retention_reason(false, None, &only_count).as_deref(),
        Some("2 subjects below KKM (max 1)")
    );
}

#[test]
fn retention_reason_is_none_without_a_cause() {
    let metrics = serde_json::json!({ "average": 90.0, "subjects_below_kkm": 0,
        "criteria": { "min_average": 70.0, "max_subjects_below_kkm": 2 } });
    assert_eq!(retention_reason(false, None, &metrics), None);
}
```

Integration tests (helpers first):

```rust
async fn execute_req(app: axum::Router, token: &str, run_id: uuid::Uuid) -> (StatusCode, Value) {
    let resp = post_json(
        app,
        token,
        &format!("/api/v1/academic-ops/promotion-runs/{run_id}/execute"),
        json!({}),
    )
    .await;
    let status = resp.status();
    (status, body_to_json(resp).await)
}

async fn ready_to_execute(pool: &PgPool, state: &AppState) -> (ExecutionFixture, axum::Router) {
    let ex = approved_execution_fixture(pool, state).await;
    let app = academic_ops_service::http::router(state.clone());
    let (status, _) = put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::OK);
    let promote = decision_id_of(pool, ex.run_id, ex.promote_student).await;
    let retain = decision_id_of(pool, ex.run_id, ex.retain_student).await;
    let (status, body) = patch_targets_req(
        app.clone(),
        &ex.admin_token,
        ex.run_id,
        json!([
            { "decision_id": promote, "homeroom_id": ex.target_final_homeroom },
            { "decision_id": retain, "homeroom_id": ex.target_mid_homeroom },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    (ex, app)
}

async fn enrollment_status_of(pool: &PgPool, student_id: uuid::Uuid, year_id: uuid::Uuid) -> Vec<(String, uuid::Uuid)> {
    sqlx::query_as(
        "SELECT status, homeroom_id FROM enrollment \
         WHERE student_id = $1 AND academic_year_id = $2 ORDER BY created_at",
    )
    .bind(student_id)
    .bind(year_id)
    .fetch_all(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn execute_moves_every_student_and_publishes_events() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let data = &body["data"];
    assert_eq!(data["status"], "executed");
    assert!(data["executed_at"].is_string());
    assert!(data["executed_by"].is_string());
    assert_eq!(data["counts"]["promoted"], 1);
    assert_eq!(data["counts"]["retained"], 1);
    assert_eq!(data["counts"]["graduated"], 1);

    // Old enrollments closed, new ones in the right homerooms.
    for student in [ex.promote_student, ex.retain_student, ex.graduate_student] {
        let old = enrollment_status_of(&pool, student, ex.fx.year_id).await;
        assert_eq!(old.len(), 1);
        assert_eq!(old[0].0, "promoted");
    }
    assert_eq!(
        enrollment_status_of(&pool, ex.promote_student, ex.target_year_id).await,
        vec![("active".to_string(), ex.target_final_homeroom)]
    );
    assert_eq!(
        enrollment_status_of(&pool, ex.retain_student, ex.target_year_id).await,
        vec![("active".to_string(), ex.target_mid_homeroom)]
    );
    assert!(enrollment_status_of(&pool, ex.graduate_student, ex.target_year_id).await.is_empty());

    // target_enrollment_id points at the new enrollment.
    let linked: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM promotion_decision d JOIN enrollment e \
           ON e.enrollment_id = d.target_enrollment_id AND e.academic_year_id = $2 \
         WHERE d.run_id = $1",
    )
    .bind(ex.run_id)
    .bind(ex.target_year_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(linked, 2);

    // Records and student status.
    let reason: String = sqlx::query_scalar(
        "SELECT reason FROM retention_record WHERE student_id = $1 AND academic_year_id = $2",
    )
    .bind(ex.retain_student)
    .bind(ex.fx.year_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(reason, "2 subjects below KKM (max 1)");
    let graduated: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM graduation_record WHERE student_id = $1 AND academic_year_id = $2",
    )
    .bind(ex.graduate_student)
    .bind(ex.fx.year_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(graduated, 1);
    let status: String = sqlx::query_scalar("SELECT status FROM student WHERE student_id = $1")
        .bind(ex.graduate_student)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(status, "lulus");

    // Outbox events.
    let events: Vec<(String, Value)> = sqlx::query_as(
        "SELECT event_type, payload FROM outbox \
         WHERE event_type IN ('student.promoted', 'student.retained', 'student.graduated') \
           AND payload->>'run_id' = $1",
    )
    .bind(ex.run_id.to_string())
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(events.len(), 3);
    let promoted = &events.iter().find(|e| e.0 == "student.promoted").unwrap().1;
    assert_eq!(promoted["student_id"], ex.promote_student.to_string());
    assert_eq!(promoted["from"]["academic_year_id"], ex.fx.year_id.to_string());
    assert_eq!(promoted["to"]["academic_year_id"], ex.target_year_id.to_string());
    assert_eq!(promoted["to"]["homeroom_id"], ex.target_final_homeroom.to_string());
    assert_eq!(promoted["full_name"], "Promo Student");
    let graduated_ev = &events.iter().find(|e| e.0 == "student.graduated").unwrap().1;
    assert_eq!(graduated_ev["student_status"], "lulus");
    assert!(graduated_ev.get("to").is_none());
}

#[tokio::test]
async fn execute_uses_override_reason_for_retention() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    // Overridden retain: rewrite the promoted student's decision to retain
    // with a reason directly (the run is already approved, so the override
    // endpoint would refuse — this pins the reason source only).
    sqlx::query(
        "UPDATE promotion_decision SET result = 'retain', overridden = TRUE, \
                reason = 'Long absence, staff meeting agreed' \
         WHERE run_id = $1 AND student_id = $2",
    )
    .bind(ex.run_id)
    .bind(ex.promote_student)
    .execute(&pool)
    .await
    .unwrap();
    let app = academic_ops_service::http::router(state.clone());
    put_target_req(app.clone(), &ex.admin_token, ex.run_id, ex.target_year_id).await;
    let a = decision_id_of(&pool, ex.run_id, ex.promote_student).await;
    let b = decision_id_of(&pool, ex.run_id, ex.retain_student).await;
    patch_targets_req(
        app.clone(),
        &ex.admin_token,
        ex.run_id,
        json!([
            { "decision_id": a, "homeroom_id": ex.target_mid_homeroom },
            { "decision_id": b, "homeroom_id": ex.target_mid_homeroom },
        ]),
    )
    .await;

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let reason: String = sqlx::query_scalar("SELECT reason FROM retention_record WHERE student_id = $1")
        .bind(ex.promote_student)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(reason, "Long absence, staff meeting agreed");
}

async fn moved_rows(pool: &PgPool, ex: &ExecutionFixture) -> (i64, i64, i64) {
    let enrollments: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM enrollment WHERE tenant_id = $1 AND academic_year_id = $2",
    )
    .bind(ex.fx.tenant_id)
    .bind(ex.target_year_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let promoted: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM enrollment WHERE tenant_id = $1 AND status = 'promoted'",
    )
    .bind(ex.fx.tenant_id)
    .fetch_one(pool)
    .await
    .unwrap();
    let records: i64 = sqlx::query_scalar(
        "SELECT (SELECT count(*) FROM graduation_record WHERE tenant_id = $1) \
              + (SELECT count(*) FROM retention_record WHERE tenant_id = $1)",
    )
    .bind(ex.fx.tenant_id)
    .fetch_one(pool)
    .await
    .unwrap();
    (enrollments, promoted, records)
}

#[tokio::test]
async fn execute_rejects_conflicts_together() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    // 1. The retained student was enrolled by hand into the target year.
    sqlx::query(
        "INSERT INTO enrollment (enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id, status) \
         VALUES ($1, $2, $3, $4, $5, 'active')",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(ex.fx.tenant_id)
    .bind(ex.retain_student)
    .bind(ex.target_mid_homeroom)
    .bind(ex.target_year_id)
    .execute(&pool)
    .await
    .unwrap();
    // 2. The promoted student's target was cleared.
    sqlx::query("UPDATE promotion_decision SET target_homeroom_id = NULL WHERE run_id = $1 AND student_id = $2")
        .bind(ex.run_id)
        .bind(ex.promote_student)
        .execute(&pool)
        .await
        .unwrap();
    let before = moved_rows(&pool, &ex).await;

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    let fields = &body["error"]["fields"];
    assert_eq!(
        fields["targets"][0],
        format!("student {} has no target homeroom", ex.promote_student)
    );
    assert_eq!(
        fields["enrollments"][0],
        format!("student {} is already enrolled in the target academic year", ex.retain_student)
    );
    assert_eq!(moved_rows(&pool, &ex).await, before, "nothing written");
    let (run_status, _) = run_status_and_approver(&pool, ex.run_id).await;
    assert_eq!(run_status, "approved");
}

#[tokio::test]
async fn execute_rejects_old_enrollment_no_longer_active() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    sqlx::query("UPDATE enrollment SET status = 'transferred' WHERE student_id = $1 AND academic_year_id = $2")
        .bind(ex.retain_student)
        .bind(ex.fx.year_id)
        .execute(&pool)
        .await
        .unwrap();

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(
        body["error"]["fields"]["enrollments"][0],
        format!("student {}'s enrollment is no longer active", ex.retain_student)
    );
}

#[tokio::test]
async fn execute_rejects_stale_target_homeroom() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    // Renumber the target year's Final level after assignment: the promoted
    // student's target (ordinal 2 expected) is now ordinal 3.
    sqlx::query(
        "UPDATE known_grade_level SET ordinal = 3 \
         WHERE tenant_id = $1 AND academic_year_id = $2 AND ordinal = 2",
    )
    .bind(ex.fx.tenant_id)
    .bind(ex.target_year_id)
    .execute(&pool)
    .await
    .unwrap();

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(
        body["error"]["fields"]["target_homerooms"][0],
        format!("student {}'s target homeroom is no longer valid", ex.promote_student)
    );
}

#[tokio::test]
async fn execute_twice_is_conflict() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    let (status, _) = execute_req(app.clone(), &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["error"]["code"], "PROMOTION_RUN_INVALID_STATUS");
}

#[tokio::test]
async fn execute_concurrent_yields_one_execution() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    let (a, b) = tokio::join!(
        execute_req(app.clone(), &ex.admin_token, ex.run_id),
        execute_req(app, &ex.admin_token, ex.run_id),
    );
    let mut statuses = vec![a.0, b.0];
    statuses.sort();
    assert_eq!(statuses, vec![StatusCode::OK, StatusCode::CONFLICT]);
    let (enrollments, _, _) = moved_rows(&pool, &ex).await;
    assert_eq!(enrollments, 2, "no duplicated enrollment");
}

#[tokio::test]
async fn execute_maps_interleaved_manual_enrollment_to_400() {
    // The precondition check and the INSERT run in one transaction, so the
    // race cannot be reproduced deterministically over HTTP. Pin the mapping
    // itself: the same unique violation, raised by the repo insert, must
    // become a 400 on `enrollments`.
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let ex = approved_execution_fixture(&pool, &state).await;
    sqlx::query(
        "INSERT INTO enrollment (enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id, status) \
         VALUES ($1, $2, $3, $4, $5, 'active')",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(ex.fx.tenant_id)
    .bind(ex.retain_student)
    .bind(ex.target_mid_homeroom)
    .bind(ex.target_year_id)
    .execute(&pool)
    .await
    .unwrap();
    let mut conn = pool.acquire().await.unwrap();
    let err = academic_ops_service::promotion::repo::insert_target_enrollment(
        &mut conn,
        uuid::Uuid::new_v4(),
        ex.fx.tenant_id,
        ex.retain_student,
        ex.target_mid_homeroom,
        ex.target_year_id,
    )
    .await
    .expect_err("second active enrollment in the year");
    let app_err = academic_ops_service::promotion::commands::map_target_enrollment_error(err, ex.retain_student);
    assert_eq!(app_err.code(), "VALIDATION_ERROR");
    let resp = axum::response::IntoResponse::into_response(app_err);
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn execute_failure_mid_transaction_rolls_back_everything() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    // Plant a retention record the preconditions do not look at. Whatever the
    // processing order (by homeroom_id, which is random), the retained
    // student's insert_retention_record hits retention_record_student_year_unique;
    // every write made before it, for any student, must roll back.
    sqlx::query(
        "INSERT INTO retention_record (retention_id, tenant_id, student_id, academic_year_id, reason) \
         VALUES ($1, $2, $3, $4, 'planted to force a mid-transaction failure')",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(ex.fx.tenant_id)
    .bind(ex.retain_student)
    .bind(ex.fx.year_id)
    .execute(&pool)
    .await
    .unwrap();
    let before = moved_rows(&pool, &ex).await;

    let (status, body) = execute_req(app, &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR, "body: {body}");
    assert_eq!(moved_rows(&pool, &ex).await, before, "every earlier write rolled back");
    let (run_status, _) = run_status_and_approver(&pool, ex.run_id).await;
    assert_eq!(run_status, "approved");
    let student_status: String = sqlx::query_scalar("SELECT status FROM student WHERE student_id = $1")
        .bind(ex.graduate_student)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_ne!(student_status, "lulus");
}

#[tokio::test]
async fn execution_endpoints_hide_other_tenant_runs_and_require_manage() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    let other = jwt_for(uuid::Uuid::new_v4());

    let (status, _) = put_target_req(app.clone(), &other, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = patch_targets_req(app.clone(), &other, ex.run_id, json!([])).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = execute_req(app.clone(), &other, ex.run_id).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (principal, _) = common_testing::mint_jwt(uuid::Uuid::new_v4(), ex.fx.tenant_id, "principal");
    let (status, _) = put_target_req(app.clone(), &principal, ex.run_id, ex.target_year_id).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = patch_targets_req(app.clone(), &principal, ex.run_id, json!([])).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = execute_req(app, &principal, ex.run_id).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
```


- [ ] **Step 2: Run, expect FAIL** — domain tests fail to compile (`retention_reason` missing); integration tests see 404/405 from the missing route (record the failing assertion of `execute_moves_every_student_and_publishes_events` as RED).

- [ ] **Step 3: Implement.**

`domain.rs`:

```rust
/// Reason stored on `retention_record` (spec §2.10): the override reason when
/// the decision was overridden, otherwise the failed criteria. `None` means a
/// retained decision has neither, which is a data error the caller surfaces.
pub fn retention_reason(
    overridden: bool,
    reason: Option<&str>,
    metrics: &serde_json::Value,
) -> Option<String> {
    if overridden {
        if let Some(r) = reason.map(str::trim).filter(|r| !r.is_empty()) {
            return Some(r.to_string());
        }
    }
    let mut parts = Vec::new();
    let criteria = &metrics["criteria"];
    if let (Some(min), Some(avg)) = (criteria["min_average"].as_f64(), metrics["average"].as_f64()) {
        if avg < min {
            parts.push(format!("average {avg:.1} below {min}"));
        }
    }
    if let (Some(max), Some(below)) = (
        criteria["max_subjects_below_kkm"].as_i64(),
        metrics["subjects_below_kkm"].as_i64(),
    ) {
        if below > max {
            parts.push(format!("{below} subjects below KKM (max {max})"));
        }
    }
    (!parts.is_empty()).then(|| parts.join("; "))
}
```

`repo.rs` (all tenant-scoped; `conn: &mut sqlx::PgConnection`):

```rust
pub struct ExecutionRow {
    pub decision_id: Uuid,
    pub student_id: Uuid,
    pub enrollment_id: Uuid,
    pub homeroom_id: Uuid,
    pub academic_year_id: Uuid,
    pub result: String,
    pub overridden: bool,
    pub reason: Option<String>,
    pub computed_metrics: serde_json::Value,
    pub target_homeroom_id: Option<Uuid>,
    pub full_name: String,
    pub nis: String,
}
// execution_rows: SELECT d.decision_id, d.student_id, d.enrollment_id, d.homeroom_id,
//   d.academic_year_id, d.result, d.overridden, d.reason, d.computed_metrics,
//   d.target_homeroom_id, s.full_name, s.nis
//   FROM promotion_decision d
//   JOIN student s ON s.tenant_id = d.tenant_id AND s.student_id = d.student_id
//   WHERE d.tenant_id = $1 AND d.run_id = $2 ORDER BY d.homeroom_id, d.student_id
// (use #[derive(sqlx::FromRow)] on ExecutionRow — 12 columns)

/// Precondition lists — each returns student_ids sorted ascending.
pub async fn students_without_target(conn, tenant_id, run_id) -> sqlx::Result<Vec<Uuid>>
// SELECT student_id FROM promotion_decision WHERE tenant_id=$1 AND run_id=$2
//   AND result IN ('promote','retain') AND target_homeroom_id IS NULL ORDER BY student_id

pub async fn students_already_in_year(conn, tenant_id, run_id, target_year: Uuid) -> sqlx::Result<Vec<Uuid>>
// SELECT DISTINCT d.student_id FROM promotion_decision d
//   JOIN enrollment e ON e.tenant_id = d.tenant_id AND e.student_id = d.student_id
//    AND e.academic_year_id = $3 AND e.status = 'active'
//   WHERE d.tenant_id=$1 AND d.run_id=$2 AND d.result IN ('promote','retain') ORDER BY 1

pub async fn students_with_inactive_source(conn, tenant_id, run_id) -> sqlx::Result<Vec<Uuid>>
// SELECT d.student_id FROM promotion_decision d
//   LEFT JOIN enrollment e ON e.tenant_id = d.tenant_id AND e.enrollment_id = d.enrollment_id
//    AND e.status = 'active'
//   WHERE d.tenant_id=$1 AND d.run_id=$2 AND e.enrollment_id IS NULL ORDER BY 1

pub async fn students_with_stale_target(conn, tenant_id, run_id, target_year: Uuid) -> sqlx::Result<Vec<Uuid>>
// SELECT d.student_id FROM promotion_decision d
//   LEFT JOIN homeroom sh ON sh.tenant_id = d.tenant_id AND sh.homeroom_id = d.homeroom_id
//   LEFT JOIN known_grade_level sk ON sk.tenant_id = sh.tenant_id AND sk.grade_level_id = sh.grade_level_id
//   LEFT JOIN homeroom th ON th.tenant_id = d.tenant_id AND th.homeroom_id = d.target_homeroom_id
//   LEFT JOIN known_grade_level tk ON tk.tenant_id = th.tenant_id AND tk.grade_level_id = th.grade_level_id
//   WHERE d.tenant_id=$1 AND d.run_id=$2 AND d.target_homeroom_id IS NOT NULL
//     AND (th.homeroom_id IS NULL OR th.academic_year_id <> $3
//          OR tk.grade_level_id IS NULL OR sk.grade_level_id IS NULL
//          OR tk.ordinal <> sk.ordinal + CASE WHEN d.result = 'promote' THEN 1 ELSE 0 END)
//   ORDER BY 1

pub async fn close_source_enrollment(conn, tenant_id, enrollment_id) -> sqlx::Result<u64>
// UPDATE enrollment SET status='promoted', updated_at=NOW()
//   WHERE tenant_id=$1 AND enrollment_id=$2 AND status='active'

pub async fn insert_target_enrollment(conn, enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id) -> sqlx::Result<()>
// INSERT INTO enrollment (enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id, status)
//   VALUES ($1,$2,$3,$4,$5,'active')

pub async fn set_target_enrollment(conn, tenant_id, run_id, decision_id, enrollment_id) -> sqlx::Result<u64>
// UPDATE promotion_decision SET target_enrollment_id=$4
//   WHERE tenant_id=$1 AND run_id=$2 AND decision_id=$3

pub async fn insert_retention_record(conn, tenant_id, student_id, academic_year_id, reason: &str) -> sqlx::Result<()>
// INSERT INTO retention_record (retention_id, tenant_id, student_id, academic_year_id, reason)
//   VALUES ($1,$2,$3,$4,$5) — bind Uuid::new_v4() as retention_id

pub async fn insert_graduation_record(conn, tenant_id, student_id, academic_year_id, graduation_date: chrono::NaiveDate) -> sqlx::Result<()>
// INSERT INTO graduation_record (graduation_id, tenant_id, student_id, academic_year_id, graduation_date) VALUES (…)

pub async fn set_student_lulus(conn, tenant_id, student_id) -> sqlx::Result<u64>
// UPDATE student SET status='lulus', updated_at=NOW() WHERE tenant_id=$1 AND student_id=$2

pub async fn mark_run_executed(conn, tenant_id, run_id, executed_by: Uuid) -> sqlx::Result<Option<RunViewRow>>
// UPDATE promotion_run SET status='executed', executed_at=NOW(), executed_by=$3, updated_at=NOW()
//   WHERE tenant_id=$1 AND run_id=$2 AND status='approved' RETURNING {RUN_VIEW_COLUMNS}
```

Every statement above is written out in full SQL in the implementation, bound in placeholder order, using `&mut *conn`.

`commands.rs`:

```rust
#[derive(Serialize, Default)]
pub struct ExecutionCounts {
    pub promoted: i64,
    pub retained: i64,
    pub graduated: i64,
}

#[derive(Serialize)]
pub struct ExecuteOutcome {
    #[serde(flatten)]
    pub run: crate::promotion::queries::PromotionRunView,
    pub counts: ExecutionCounts,
}

/// Only the one-active-enrollment index means "the student is already in
/// the target year"; every other database error is a 500 that rolls back.
pub fn map_target_enrollment_error(err: sqlx::Error, student_id: Uuid) -> AppError {
    if let sqlx::Error::Database(db) = &err {
        if db.constraint() == Some("enrollment_one_active_per_student_year_uidx") {
            return AppError::validation_error_single(
                "enrollments",
                format!("student {student_id} is already enrolled in the target academic year"),
            );
        }
    }
    AppError::internal(err)
}

fn push_all(errors: &mut BTreeMap<String, Vec<String>>, field: &str, messages: Vec<String>) {
    if !messages.is_empty() {
        errors.entry(field.to_string()).or_default().extend(messages);
    }
}
```

and `execute_promotion_run` following the Algorithm above. The event payloads:

```rust
let from = json!({ "enrollment_id": row.enrollment_id, "homeroom_id": row.homeroom_id,
                   "academic_year_id": row.academic_year_id });
// promote / retain:
json!({ "tenant_id": tenant_id, "student_id": row.student_id, "run_id": run_id,
        "from": from,
        "to": { "enrollment_id": new_id, "homeroom_id": target_homeroom, "academic_year_id": target_year },
        "full_name": row.full_name, "nis": row.nis })
// graduate:
json!({ "tenant_id": tenant_id, "student_id": row.student_id, "run_id": run_id,
        "from": from, "graduation_date": today, "student_status": "lulus" })
```

`map_target_enrollment_error` is `pub` so the integration test can call it; the test reads the HTTP status through `IntoResponse`, so `libs/common-errors` is untouched.

`http.rs`: route `"/api/v1/academic-ops/promotion-runs/:run_id/execute"` → `post(execute_promotion_run)`, `require_permission(PERM_PROMOTION_MANAGE)`, call the command with `auth.tenant_id`, `auth.user_id`, `run_id`, return `envelope(outcome)`.

- [ ] **Step 4: Run, expect PASS** — `cargo test -p academic-ops-service --lib retention_reason`, then the nine integration tests with `--exact`, then `cargo check --workspace`.
- [ ] **Step 5: Mutation proof** (record in the report, then restore): drop `AND status = 'active'` from `close_source_enrollment` → `execute_rejects_old_enrollment_no_longer_active` must fail; map every `23505` (drop the constraint-name check) → nothing in this task's tests changes, so instead drop the mapping entirely → `execute_maps_interleaved_manual_enrollment_to_400` must fail. Restore and show `git diff` is only the intended change.
- [ ] **Step 6: Commit** `feat(academic-ops): execute an approved promotion run`

---

### Task 6: grading-service consumes the three events

**Files:**
- Modify: `services/grading-service/src/events.rs` (`ROUTING_KEYS`, `handle_event`, payload structs)
- Modify: `services/grading-service/src/repo.rs` (`ProjectionRepo`, near `deactivate_enrolled_student` ~line 1970)
- Test: `services/grading-service/tests/integration.rs`

**Interfaces:**
- Consumes: payloads of spec §6.1 (Task 5).
- Produces: `ProjectionRepo::move_enrolled_student(&self, tenant_id, student_id, from_year: Uuid, to_homeroom: Uuid, to_year: Uuid, full_name: Option<&str>, nis: Option<&str>) -> Result<bool, sqlx::Error>` (true if the `from` row existed) and `ProjectionRepo::mark_enrolled_student_promoted(&self, tenant_id, student_id, academic_year_id) -> Result<bool, sqlx::Error>`.

- [ ] **Step 1: Write the failing tests:**

```rust
async fn enrolled_rows(pool: &PgPool, tenant_id: Uuid, student_id: Uuid) -> Vec<(Uuid, Uuid, String)> {
    sqlx::query_as(
        "SELECT academic_year_id, homeroom_id, status FROM enrolled_student \
         WHERE tenant_id = $1 AND student_id = $2 ORDER BY status",
    )
    .bind(tenant_id)
    .bind(student_id)
    .fetch_all(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn move_enrolled_student_closes_from_and_opens_to() {
    let (pool, state, _pg) = boot().await;
    let (tenant_id, student_id) = (Uuid::new_v4(), Uuid::new_v4());
    let (from_room, from_year, to_room, to_year) =
        (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    seed_enrollment(&pool, tenant_id, student_id, from_room, from_year).await;

    for _ in 0..2 {
        // second pass = redelivery, must be a no-op
        let found = state
            .projections
            .move_enrolled_student(tenant_id, student_id, from_year, to_room, to_year, Some("Student One"), Some("S-001"))
            .await
            .unwrap();
        assert!(found);
    }
    let rows = enrolled_rows(&pool, tenant_id, student_id).await;
    assert_eq!(
        rows,
        vec![
            (to_year, to_room, "active".to_string()),
            (from_year, from_room, "promoted".to_string()),
        ]
    );
}

#[tokio::test]
async fn move_enrolled_student_without_from_row_still_creates_to() {
    let (pool, state, _pg) = boot().await;
    let (tenant_id, student_id, to_room, to_year) =
        (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    let found = state
        .projections
        .move_enrolled_student(tenant_id, student_id, Uuid::new_v4(), to_room, to_year, Some("New"), Some("N-1"))
        .await
        .unwrap();
    assert!(!found);
    assert_eq!(
        enrolled_rows(&pool, tenant_id, student_id).await,
        vec![(to_year, to_room, "active".to_string())]
    );
}

#[tokio::test]
async fn mark_enrolled_student_promoted_for_graduate() {
    let (pool, state, _pg) = boot().await;
    let (tenant_id, student_id, room, year) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    seed_enrollment(&pool, tenant_id, student_id, room, year).await;
    assert!(state.projections.mark_enrolled_student_promoted(tenant_id, student_id, year).await.unwrap());
    assert_eq!(
        enrolled_rows(&pool, tenant_id, student_id).await,
        vec![(year, room, "promoted".to_string())]
    );
}

#[tokio::test]
async fn promotion_events_are_consumed_end_to_end() {
    // Proves ROUTING_KEYS and the match arms agree for all three events.
    use common_events::DEFAULT_EXCHANGE;
    use grading_service::events::ProjectionConsumer;
    use lapin::{options::{BasicPublishOptions, ExchangeDeclareOptions}, types::FieldTable,
                BasicProperties, Connection, ConnectionProperties, ExchangeKind};

    let (pool, state, _pg) = boot().await;
    let (_rabbit, rabbitmq_url) = common_testing::harness::start_rabbitmq().await;
    let consumer = ProjectionConsumer::new(
        rabbitmq_url.clone(),
        state.grades.clone(),
        state.projections.clone(),
        state.subscriptions.clone(),
    );
    let handle = tokio::spawn(async move { consumer.run().await });
    let conn = Connection::connect(&rabbitmq_url, ConnectionProperties::default()).await.unwrap();
    let channel = conn.create_channel().await.unwrap();
    channel
        .exchange_declare(DEFAULT_EXCHANGE, ExchangeKind::Topic,
            ExchangeDeclareOptions { durable: true, ..Default::default() }, FieldTable::default())
        .await
        .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(3000)).await;

    let tenant_id = Uuid::new_v4();
    let (from_year, to_year) = (Uuid::new_v4(), Uuid::new_v4());
    let mut expectations = Vec::new();
    for event_type in ["student.promoted", "student.retained", "student.graduated"] {
        let student_id = Uuid::new_v4();
        let from_room = Uuid::new_v4();
        let to_room = Uuid::new_v4();
        seed_enrollment(&pool, tenant_id, student_id, from_room, from_year).await;
        let from = json!({ "enrollment_id": Uuid::new_v4(), "homeroom_id": from_room, "academic_year_id": from_year });
        let payload = if event_type == "student.graduated" {
            json!({ "tenant_id": tenant_id, "student_id": student_id, "run_id": Uuid::new_v4(),
                    "from": from, "graduation_date": "2027-06-30", "student_status": "lulus" })
        } else {
            json!({ "tenant_id": tenant_id, "student_id": student_id, "run_id": Uuid::new_v4(),
                    "from": from,
                    "to": { "enrollment_id": Uuid::new_v4(), "homeroom_id": to_room, "academic_year_id": to_year },
                    "full_name": "Student One", "nis": "S-001" })
        };
        let envelope = json!({ "event_id": Uuid::new_v4(), "event_type": event_type,
                               "occurred_at": chrono::Utc::now(), "payload": payload });
        channel
            .basic_publish(DEFAULT_EXCHANGE, event_type, BasicPublishOptions::default(),
                &serde_json::to_vec(&envelope).unwrap(),
                BasicProperties::default().with_content_type("application/json".into()))
            .await
            .unwrap()
            .await
            .unwrap();
        expectations.push((event_type, student_id));
    }

    let mut ok = false;
    for _ in 0..100 {
        let mut all = true;
        for (event_type, student_id) in &expectations {
            let rows = enrolled_rows(&pool, tenant_id, *student_id).await;
            let from_promoted = rows.iter().any(|r| r.0 == from_year && r.2 == "promoted");
            let to_active = rows.iter().any(|r| r.0 == to_year && r.2 == "active");
            let expected_to = *event_type != "student.graduated";
            if !from_promoted || to_active != expected_to {
                all = false;
            }
        }
        if all {
            ok = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    handle.abort();
    assert!(ok, "all three promotion events must be consumed into enrolled_student");
}
```

If `AppState`'s `grades`/`projections`/`subscriptions` fields or the repos lack `Clone`, they already derive it (`#[derive(Clone)]` on all three repos, `pub` fields on `AppState`); no change needed.

- [ ] **Step 2: Run, expect FAIL** — repo tests fail to compile (methods missing; RED = compile error is acceptable here only for the repo methods — the e2e test is the behavioural RED: after adding the methods but before the arms, it times out with `ok == false`. Record that run.)

- [ ] **Step 3: Implement.** `repo.rs`:

```rust
    /// One transaction: the `from` year row becomes `promoted`, the `to` year
    /// row is upserted `active` (same statement as `upsert_enrolled_student`).
    /// Returns whether the `from` row existed.
    #[allow(clippy::too_many_arguments)]
    pub async fn move_enrolled_student(
        &self,
        tenant_id: Uuid,
        student_id: Uuid,
        from_year: Uuid,
        to_homeroom: Uuid,
        to_year: Uuid,
        full_name: Option<&str>,
        nis: Option<&str>,
    ) -> Result<bool, sqlx::Error> {
        let mut tx = self.pool.begin().await?;
        let closed = sqlx::query(
            "UPDATE enrolled_student SET status = 'promoted', updated_at = NOW() \
             WHERE tenant_id = $1 AND student_id = $2 AND academic_year_id = $3",
        )
        .bind(tenant_id)
        .bind(student_id)
        .bind(from_year)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        sqlx::query("INSERT INTO enrolled_student (tenant_id, student_id, homeroom_id, academic_year_id, status, full_name, nis) VALUES ($1,$2,$3,$4,'active',$5,$6) ON CONFLICT (tenant_id, student_id, academic_year_id) DO UPDATE SET homeroom_id = EXCLUDED.homeroom_id, status = EXCLUDED.status, full_name = COALESCE(EXCLUDED.full_name, enrolled_student.full_name), nis = COALESCE(EXCLUDED.nis, enrolled_student.nis), updated_at = NOW()")
            .bind(tenant_id).bind(student_id).bind(to_homeroom).bind(to_year).bind(full_name).bind(nis)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(closed > 0)
    }

    pub async fn mark_enrolled_student_promoted(
        &self,
        tenant_id: Uuid,
        student_id: Uuid,
        academic_year_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let res = sqlx::query(
            "UPDATE enrolled_student SET status = 'promoted', updated_at = NOW() \
             WHERE tenant_id = $1 AND student_id = $2 AND academic_year_id = $3",
        )
        .bind(tenant_id)
        .bind(student_id)
        .bind(academic_year_id)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() > 0)
    }
```

`events.rs`: add the three keys to `ROUTING_KEYS`; payload structs:

```rust
#[derive(Debug, Deserialize)]
struct EnrollmentRef {
    homeroom_id: Uuid,
    academic_year_id: Uuid,
}

#[derive(Debug, Deserialize)]
struct StudentMovedPayload {
    tenant_id: Uuid,
    student_id: Uuid,
    from: EnrollmentRef,
    to: EnrollmentRef,
    #[serde(default)]
    full_name: Option<String>,
    #[serde(default)]
    nis: Option<String>,
}

#[derive(Debug, Deserialize)]
struct StudentGraduatedPayload {
    tenant_id: Uuid,
    student_id: Uuid,
    from: EnrollmentRef,
}
```

arms:

```rust
            "student.promoted" | "student.retained" => {
                let payload: StudentMovedPayload = serde_json::from_value(envelope.payload)?;
                let found = self
                    .projections
                    .move_enrolled_student(
                        payload.tenant_id,
                        payload.student_id,
                        payload.from.academic_year_id,
                        payload.to.homeroom_id,
                        payload.to.academic_year_id,
                        payload.full_name.as_deref(),
                        payload.nis.as_deref(),
                    )
                    .await?;
                if !found {
                    tracing::warn!(
                        tenant_id = %payload.tenant_id,
                        student_id = %payload.student_id,
                        academic_year_id = %payload.from.academic_year_id,
                        "promotion event for non-projected source enrollment"
                    );
                }
            }
            "student.graduated" => {
                let payload: StudentGraduatedPayload = serde_json::from_value(envelope.payload)?;
                let found = self
                    .projections
                    .mark_enrolled_student_promoted(
                        payload.tenant_id,
                        payload.student_id,
                        payload.from.academic_year_id,
                    )
                    .await?;
                if !found {
                    tracing::warn!(
                        tenant_id = %payload.tenant_id,
                        student_id = %payload.student_id,
                        academic_year_id = %payload.from.academic_year_id,
                        "student.graduated event for non-projected source enrollment"
                    );
                }
            }
```

`from.homeroom_id` is deserialized but unused by grading; if the compiler warns, rename it `#[serde(rename = "homeroom_id")] _homeroom_id` on a separate `FromRef` struct exactly as `StudentUnenrolledPayload` does.

- [ ] **Step 4: Run, expect PASS** — the four tests with `cargo test -p grading-service --test integration -- --test-threads=2 --exact …`, then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(grading): project promotion, retention and graduation moves`

---

### Task 7: `lulus → alumni` when the graduating year closes

**Files:**
- Modify: `services/academic-ops-service/src/repo.rs` (`KnownAcademicYearRepo`, ~line 770)
- Modify: `services/academic-ops-service/src/events.rs` (`academic_year.status_changed` arm, ~line 96)
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: `KnownAcademicYearRepo::apply_status_change(&self, tenant_id: Uuid, year_id: Uuid, status: &str) -> sqlx::Result<u64>` — upserts the status and, only when `status == "Closed"`, moves that year's graduates to `alumni` in the same transaction; returns the number of students moved.

- [ ] **Step 1: Write the failing tests:**

```rust
async fn seed_graduate(pool: &PgPool, tenant_id: uuid::Uuid, year_id: uuid::Uuid) -> uuid::Uuid {
    let student_id = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO student (student_id, tenant_id, nis, full_name, gender, birth_date, status) \
         VALUES ($1, $2, $3, 'Grad', 'male', '2008-01-01', 'lulus')",
    )
    .bind(student_id)
    .bind(tenant_id)
    .bind(format!("G-{student_id}"))
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO graduation_record (graduation_id, tenant_id, student_id, academic_year_id, graduation_date) \
         VALUES ($1, $2, $3, $4, CURRENT_DATE)",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(tenant_id)
    .bind(student_id)
    .bind(year_id)
    .execute(pool)
    .await
    .unwrap();
    student_id
}

async fn student_status(pool: &PgPool, student_id: uuid::Uuid) -> String {
    sqlx::query_scalar("SELECT status FROM student WHERE student_id = $1")
        .bind(student_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn closing_a_year_turns_its_graduates_into_alumni_only() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year = seed_year(&pool, tenant_id, "Active").await;
    let other_year = seed_year(&pool, tenant_id, "Active").await;
    let mine = seed_graduate(&pool, tenant_id, year).await;
    let other_years_graduate = seed_graduate(&pool, tenant_id, other_year).await;
    let other_tenant = uuid::Uuid::new_v4();
    let other_tenant_year = seed_year(&pool, other_tenant, "Active").await;
    let other_tenants_graduate = seed_graduate(&pool, other_tenant, other_tenant_year).await;

    let moved = state.known_years.apply_status_change(tenant_id, year, "Draft").await.unwrap();
    assert_eq!(moved, 0, "only Closed moves graduates");
    assert_eq!(student_status(&pool, mine).await, "lulus");

    let moved = state.known_years.apply_status_change(tenant_id, year, "Closed").await.unwrap();
    assert_eq!(moved, 1);
    assert_eq!(student_status(&pool, mine).await, "alumni");
    assert_eq!(student_status(&pool, other_years_graduate).await, "lulus");
    assert_eq!(student_status(&pool, other_tenants_graduate).await, "lulus");

    // Redelivery is a no-op.
    let moved = state.known_years.apply_status_change(tenant_id, year, "Closed").await.unwrap();
    assert_eq!(moved, 0);
}

#[tokio::test]
async fn year_closed_event_makes_alumni_end_to_end() {
    let (pool, state, rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year = seed_year(&pool, tenant_id, "Active").await;
    let graduate = seed_graduate(&pool, tenant_id, year).await;

    let consumer = ProjectionConsumer::new(
        rabbitmq_url.clone(),
        state.known_years.clone(),
        state.known_terms.clone(),
        state.known_tenant_users.clone(),
        state.subscriptions.clone(),
        state.known_report_scores.clone(),
        state.known_grading_policies.clone(),
        state.known_grade_levels.clone(),
        state.known_report_types.clone(),
    );
    let handle = tokio::spawn(async move { consumer.run().await });
    let conn = Connection::connect(&rabbitmq_url, ConnectionProperties::default()).await.unwrap();
    let channel = conn.create_channel().await.unwrap();
    channel
        .exchange_declare(EXCHANGE, ExchangeKind::Topic,
            ExchangeDeclareOptions { durable: true, ..Default::default() }, FieldTable::default())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(3000)).await;

    let envelope = json!({
        "event_id": uuid::Uuid::new_v4(),
        "event_type": "academic_year.status_changed",
        "occurred_at": chrono::Utc::now(),
        "payload": { "tenant_id": tenant_id, "academic_year_id": year, "status": "Closed" },
    });
    channel
        .basic_publish(EXCHANGE, "academic_year.status_changed",
            lapin::options::BasicPublishOptions::default(),
            &serde_json::to_vec(&envelope).unwrap(),
            lapin::BasicProperties::default().with_content_type("application/json".into()))
        .await
        .unwrap()
        .await
        .unwrap();

    let mut alumni = false;
    for _ in 0..100 {
        if student_status(&pool, graduate).await == "alumni" {
            alumni = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    handle.abort();
    assert!(alumni, "a Closed year event must turn its graduates into alumni");
}
```

- [ ] **Step 2: Run, expect FAIL** — first test fails to compile until `apply_status_change` exists; the e2e test is the behavioural RED (after adding the method, before switching the arm, it times out with `alumni == false`; record that run).

- [ ] **Step 3: Implement.** `repo.rs`, in `impl KnownAcademicYearRepo`:

```rust
    /// Stores the year's status and, when it becomes `Closed`, moves that
    /// year's graduates from `lulus` to `alumni` in the same transaction
    /// (Plan 3c spec §6.3). Returns the number of students moved.
    pub async fn apply_status_change(
        &self,
        tenant_id: Uuid,
        year_id: Uuid,
        status: &str,
    ) -> sqlx::Result<u64> {
        let mut tx = self.0.begin().await?;
        sqlx::query("INSERT INTO known_academic_year (academic_year_id, tenant_id, status) VALUES ($1,$2,$3) ON CONFLICT (academic_year_id) DO UPDATE SET status=EXCLUDED.status, updated_at=NOW()")
            .bind(year_id).bind(tenant_id).bind(status).execute(&mut *tx).await?;
        let moved = if status == "Closed" {
            sqlx::query(
                "UPDATE student SET status = 'alumni', updated_at = NOW() \
                 WHERE tenant_id = $1 AND status = 'lulus' \
                   AND student_id IN (SELECT student_id FROM graduation_record \
                                       WHERE tenant_id = $1 AND academic_year_id = $2)",
            )
            .bind(tenant_id)
            .bind(year_id)
            .execute(&mut *tx)
            .await?
            .rows_affected()
        } else {
            0
        };
        tx.commit().await?;
        Ok(moved)
    }
```

`events.rs`, `academic_year.status_changed` arm: replace `self.years.upsert(...)` with `self.years.apply_status_change(payload.tenant_id, payload.academic_year_id, &payload.status).await?;`. Leave `academic_year.created` on `upsert`.

- [ ] **Step 4: Run, expect PASS** — the two tests plus `--exact projection_consumer_updates_year_status`, then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): turn graduates into alumni when their year closes`

---

### Task 8: Final gate and contract documentation

**Files:**
- Create: `docs/internal/11_integration_contracts/events/student-promotion-events.md` (parent repo)
- Modify: `docs/internal/11_integration_contracts/apis/promotion-service-api.md` (parent repo)
- Modify: parent submodule pointer `apps/backend`

- [ ] **Step 1: Whole-branch review first** (controller): dispatch the final code review over `a2d239a..HEAD` per `superpowers:requesting-code-review`, fix wave if needed, scoped re-review. Full suites run once, after that.
- [ ] **Step 2: Full suites, one at a time** (academic-ops integration `--test-threads=2`, academic-ops `--lib`, grading integration, `common-testing`), then `cargo check --workspace` and `cargo clippy --workspace --all-targets`. Judge every failure by name against Global Constraints; a `StartupTimeout` failure is clean only if it passes when re-run alone. New clippy warnings introduced by this branch are fixed.
- [ ] **Step 3: Dev database:** apply V19 twice by hand (`docker compose exec -T postgres psql -U akademiq -d akademiq`, `SET search_path TO academic_ops;` first); the second run must only print `NOTICE … skipping`/re-create the constraints. Verify the three columns and two constraints exist.
- [ ] **Step 4: Contract docs** (parent repo):
  - `events/student-promotion-events.md` — the three events, one file, in the style of `grade-level-events.md`: producer academic-ops, consumer grading-service (platform deliberately does not subscribe — spec §2.6), when emitted (only from execute, after commit, one per student), the payloads of spec §6.1, redelivery semantics of the grading consumer.
  - `apis/promotion-service-api.md` — add the three endpoints (§5.1–5.3 with exact messages and field keys), the added run/decision fields, `placement`/`unassigned` on the detail, the `approved` row in the status table now reading "set target year and homerooms, execute", and the Events section listing the three events instead of "publish no events yet".
- [ ] **Step 5: Commit** backend (if gate fixes) and parent: `docs(contracts): document promotion execution endpoints and student promotion events`, then `chore: bump backend to promotion execution`. No push.

---

## Spec coverage

| Spec | Task |
|---|---|
| §2.1 explicit target year, §5.1 | 2 |
| §2.2 per-student targets, §5.2 | 3 |
| §2.3 targets only when `approved`, no return from `approved` | 2, 3 (status checks); `transition_run` unchanged |
| §2.4 capacity reported, §5.4 placement | 4 |
| §2.5 / §5.3 conflicts rejected together | 5 |
| §2.6 three events, §6.1 payloads | 5 |
| §2.7 / §6.3 alumni | 7 |
| §2.8 ordinal matching | 2, 3, 5 |
| §2.9 one transaction | 5 |
| §2.10 graduation date, retention reason | 5 |
| §3 V19 | 1 |
| §4 algorithm, 23505 mapping | 5 |
| §5.4 extended run/decision shapes | 2, 3 |
| §6.2 grading consumer | 6 |
| §6.4 contract docs | 8 |
| §7 testing | 1–7, gate in 8 |
