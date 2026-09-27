# Promotion Evaluation Engine (Plan 3b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a year's published promotion-source report cards plus a set of criteria into one reviewable, overridable, approvable `promotion_decision` per student — without moving any student.

**Architecture:** grading-service starts publishing `report_type.promotion_source_changed` through its outbox; academic-ops projects it into `known_report_type`. A new `promotion` module in academic-ops holds a pure evaluation function, a repo, command handlers and query handlers (CQRS split), and HTTP routes merged into the existing router. Run lifecycle `draft → submitted → approved` is enforced with conditional `UPDATE … WHERE status = …` statements.

**Tech Stack:** Rust, Axum, SQLx, refinery, PostgreSQL 18, RabbitMQ (lapin), testcontainers.

**Spec:** `docs/superpowers/specs/2026-09-26-promotion-evaluation-design.md` — read it before any task. Parent: `docs/superpowers/specs/2026-09-23-promotion-design.md`.

## Global Constraints

- Work in `apps/backend` on branch `feat/promotion-evaluation`, created from `feat/promotion-foundation` (HEAD `3c07572`).
- Follow `apps/backend/CONVENTIONS.md`. No HTTP between services; projections only.
- Migrations: refinery, re-runnable (`IF NOT EXISTS`, `ON CONFLICT`). **Never edit an applied migration** (V1–V16 in academic-ops) — refinery checksums them.
- Next free migration: academic-ops **V17**. grading-service gets **no** migration.
- Envelope: success `{ "data": …, "meta": … }` via the existing `envelope` helper; validation errors via `AppError::validation_error(BTreeMap<String, Vec<String>>)`.
- Feature guard: existing `AcademicOpsEntitlement` (`academic_ops`). Do NOT add a `promotion` feature code (spec §2.3).
- Permissions: `promotion.manage` (tenant_admin), `promotion.approve` (principal). Checked with `auth.require_permission(code)`.
- `tenant_id` always from `AuthContext`, never from the request body.
- Every new query filters by `tenant_id`.
- `min_attendance_percent` non-NULL → `VALIDATION_ERROR` (spec §2.1).
- Commit per task, message only, **no trailers** (no `Co-authored-by`, no tool names).
- Test baseline that must not grow: academic-config 56/1, academic-ops 65/2, iam 105/0. Known failures: `status_transition_legal_and_illegal_paths`, `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url`.
- Test cadence per `apps/backend/CONVENTIONS.md` §7.1: each task runs `cargo check --workspace` plus **only its own tests** by name filter (RED then GREEN). **No full service suite inside Tasks 1–8** — full suites run once, in Task 9. Integration tests always use `-- --test-threads=4`; never run suites in parallel (memory-constrained workstation).

## Review Focus

1. **Out-of-order flag events.** `false` for report type A delivered after `true` for B must not clear B. Pinned in Task 3 (`promotion_source_false_for_other_type_does_not_clear_current`).
2. **A score of `0.0` is a score, not a missing score.** It counts toward the average and toward below-KKM. Pinned in Task 4 (`zero_score_counts_as_score`).
3. **Double-click on approve/return.** Two concurrent transitions: exactly one wins, the other gets `409 PROMOTION_RUN_INVALID_STATUS`. Pinned in Task 8 (`second_approve_is_conflict`).
4. **Guessed IDs across tenants.** Tenant B reading or overriding tenant A's run/decision gets 404, not 403 and not data. Pinned in Task 7 (`other_tenant_cannot_see_or_override_run`).
5. **Override back to the recommendation.** Setting `result` equal to `recommended` clears `overridden` and `reason` instead of recording a no-op override. Pinned in Task 6 (`override_back_to_recommendation_clears_flag`).

---

### Task 1: Promotion permission constants in the JWT test minting

**Files:**
- Modify: `libs/common-auth/src/jwt.rs` (after `PERM_REPORT_READ`, ~line 62)
- Modify: `libs/common-testing/src/jwt.rs` (imports + `ROLE_TENANT_ADMIN` and `ROLE_PRINCIPAL` arms)
- Test: `libs/common-testing/src/jwt.rs` (`mod tests`)

**Interfaces:**
- Produces: `common_auth::jwt::PERM_PROMOTION_MANAGE = "promotion.manage"`, `PERM_PROMOTION_APPROVE = "promotion.approve"`. `mint_jwt(_, _, "tenant_admin")` carries `promotion.manage`; `mint_jwt(_, _, "principal")` carries `promotion.approve`; neither carries both.

Why: IAM seeded these (V26) but test tokens are built from a hardcoded role→perms map. Without this, every promotion handler test gets 403.

- [ ] **Step 1: Write the failing test** in `libs/common-testing/src/jwt.rs` `mod tests`:

```rust
#[test]
fn minted_tokens_split_promotion_permissions() {
    use common_auth::jwt::{PERM_PROMOTION_APPROVE, PERM_PROMOTION_MANAGE, ROLE_PRINCIPAL};
    let (_, admin) = mint_jwt(Uuid::new_v4(), Uuid::new_v4(), ROLE_TENANT_ADMIN);
    let (_, principal) = mint_jwt(Uuid::new_v4(), Uuid::new_v4(), ROLE_PRINCIPAL);
    assert!(admin.perms.iter().any(|p| p == PERM_PROMOTION_MANAGE));
    assert!(!admin.perms.iter().any(|p| p == PERM_PROMOTION_APPROVE));
    assert!(principal.perms.iter().any(|p| p == PERM_PROMOTION_APPROVE));
    assert!(!principal.perms.iter().any(|p| p == PERM_PROMOTION_MANAGE));
}
```

- [ ] **Step 2: Run, expect compile failure** (constants undefined): `cargo test -p common-testing minted_tokens_split_promotion_permissions`

- [ ] **Step 3: Implement.** In `libs/common-auth/src/jwt.rs`:

```rust
pub const PERM_PROMOTION_MANAGE: &str = "promotion.manage";
pub const PERM_PROMOTION_APPROVE: &str = "promotion.approve";
```

In `libs/common-testing/src/jwt.rs` add both to the `use common_auth::jwt::{…}` list, append `PERM_PROMOTION_MANAGE` to the `ROLE_TENANT_ADMIN` slice, and change the principal arm to `ROLE_PRINCIPAL => &[PERM_REPORT_TRANSITION, PERM_REPORT_READ, PERM_PROMOTION_APPROVE],`.

`libs/common-auth/src/lib.rs` re-exports permission constants (`pub use jwt::{… PERM_… }`); add both new constants to that list too.

- [ ] **Step 4: Run, expect PASS**, then `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(auth): add promotion permission constants`

---

### Task 2: grading-service publishes `report_type.promotion_source_changed`

**Files:**
- Modify: `services/grading-service/src/repo.rs` (`impl GradeRepo`: add connection-taking write methods; trait impls delegate)
- Modify: `services/grading-service/src/commands.rs` (`create_report_type`, `update_report_type`, `delete_report_type`)
- Test: `services/grading-service/tests/integration.rs` (near the promotion-source tests, ~line 4542)

**Interfaces:**
- Produces event `report_type.promotion_source_changed`, payload `{ tenant_id, academic_year_id, report_type_id, is_promotion_source }` (spec §4.3).

Publish rules (spec §4.3):
- create with `is_promotion_source = true` → publish `true`. Create with `false` → nothing.
- update where `Some(v)` and `v != current.is_promotion_source` → publish `v`. Otherwise nothing.
- delete where `current.is_promotion_source` → publish `false`. Otherwise nothing.
- `copy_report_types` publishes nothing (it never sets the flag — keep its WARNING comment intact).

The flag write and the `outbox.enqueue` MUST share one transaction.

- [ ] **Step 1: Write failing tests.** Reuse the setup of `second_promotion_source_report_type_is_rejected` (line 4560) for how it creates report types via HTTP (copy its boot/seed calls exactly). Add:

```rust
async fn promotion_source_events(pool: &PgPool) -> Vec<Value> {
    sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'report_type.promotion_source_changed' ORDER BY seq",
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn creating_promotion_source_publishes_event() { /* create with is_promotion_source=true; assert 1 event, payload.is_promotion_source == true, report_type_id/academic_year_id/tenant_id match */ }

#[tokio::test]
async fn creating_non_source_publishes_nothing() { /* create with false; assert 0 events */ }

#[tokio::test]
async fn flipping_flag_publishes_each_change_once() {
    /* create false (0 events); PATCH true (1 event, true); PATCH true again (still 1);
       PATCH false (2 events, last false) */
}

#[tokio::test]
async fn deleting_promotion_source_publishes_false() { /* create true, delete; last event false */ }

#[tokio::test]
async fn deleting_non_source_publishes_nothing() {}

#[tokio::test]
async fn rejected_second_source_publishes_nothing() {
    /* A true (1 event); create B true -> 409 REPORT_TYPE_PROMOTION_SOURCE_TAKEN; still 1 event */
}
```

Write each body fully in the test file using the same request helpers the neighbouring tests use; the comments above state the exact assertions.

- [ ] **Step 2: Run, expect FAIL** (0 events where ≥1 expected): `cargo test -p grading-service --test integration promotion_source -- --test-threads=4`

- [ ] **Step 3: Implement repo methods** in `impl GradeRepo` (inherent, not the trait), moving the existing SQL verbatim so it stays single-sourced:

```rust
impl GradeRepo {
    #[allow(clippy::too_many_arguments)]
    pub async fn insert_report_type_on(
        &self,
        conn: &mut sqlx::PgConnection,
        tenant_id: Uuid, academic_year_id: Uuid, term_id: Uuid,
        code: &str, name: &str, position: i32, is_promotion_source: bool,
    ) -> Result<ReportType, sqlx::Error> { /* existing INSERT … RETURNING *, .fetch_one(&mut *conn) */ }

    pub async fn update_report_type_on(
        &self,
        conn: &mut sqlx::PgConnection,
        tenant_id: Uuid, report_type_id: Uuid,
        code: Option<&str>, name: Option<&str>, position: Option<i32>,
        is_promotion_source: Option<bool>,
    ) -> Result<ReportType, sqlx::Error> { /* existing UPDATE (repo.rs:918) on conn */ }

    pub async fn delete_report_type_on(
        &self, conn: &mut sqlx::PgConnection, tenant_id: Uuid, report_type_id: Uuid,
    ) -> Result<(), sqlx::Error> { /* existing DELETE on conn */ }
}
```

Change the three trait impls to `let mut conn = self.pool.acquire().await?; self.<name>_on(&mut conn, …).await`. Behaviour for other callers is unchanged.

- [ ] **Step 4: Implement commands.** Add near `ensure_no_other_promotion_source`:

```rust
async fn enqueue_promotion_source_changed(
    state: &AppState,
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    report_type_id: Uuid,
    is_promotion_source: bool,
) -> Result<(), AppError> {
    state
        .outbox
        .enqueue(
            &mut *conn,
            Uuid::new_v4(),
            "report_type.promotion_source_changed",
            &json!({
                "tenant_id": tenant_id,
                "academic_year_id": academic_year_id,
                "report_type_id": report_type_id,
                "is_promotion_source": is_promotion_source,
            }),
            Utc::now(),
        )
        .await
        .map_err(AppError::internal)
}
```

In `create_report_type`: after validation and the `term_id`/`position` resolution, `let mut tx = state.pool.begin().await.map_err(AppError::internal)?;`, call `insert_report_type_on(&mut tx, …)` keeping the existing `23505 → DUPLICATE_REPORT_TYPE_CODE` mapping, then `if created.is_promotion_source { enqueue_promotion_source_changed(state, &mut tx, …, true).await?; }`, then `tx.commit()`.

In `update_report_type`: `let changed = input.is_promotion_source.filter(|v| *v != current.is_promotion_source);` — open tx, `update_report_type_on`, `if let Some(v) = changed { enqueue…(…, current.academic_year_id, input.report_type_id, v) }`, commit.

In `delete_report_type`: keep the `get_report_type` lookup as `current`; open tx, `delete_report_type_on`, `if current.is_promotion_source { enqueue…(…, false) }`, commit.

- [ ] **Step 5: Run the new tests + the five existing `promotion_source` tests, expect PASS:** `cargo test -p grading-service --test integration promotion_source -- --test-threads=4`. Also run `report_card` (the publish path shares `GradeRepo`): `cargo test -p grading-service --test integration report_card -- --test-threads=4`. Do NOT run the full grading suite here — that is Task 9.
- [ ] **Step 6: Commit** `feat(grading): publish report type promotion source changes`

---

### Task 3: academic-ops projects `known_report_type` (migration V17)

**Files:**
- Create: `services/academic-ops-service/migrations/V17__known_report_type.sql`
- Modify: `services/academic-ops-service/src/repo.rs` (add `KnownReportTypeRepo` after `KnownGradeLevelRepo`)
- Modify: `services/academic-ops-service/src/state.rs` (field `known_report_types`)
- Modify: `services/academic-ops-service/src/events.rs` (`ROUTING_KEYS`, payload struct, match arm, `ProjectionConsumer` field + `new` param)
- Modify: `services/academic-ops-service/src/main.rs:68` and test call sites `tests/integration.rs:788, 2851, 3494` (new `new` argument)
- Test: `services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: `KnownReportTypeRepo::apply(&self, tenant_id, academic_year_id, report_type_id, is_promotion_source: bool) -> sqlx::Result<()>`; `KnownReportTypeRepo::find_promotion_source(&self, tenant_id, academic_year_id) -> sqlx::Result<Option<Uuid>>`; `AppState.known_report_types`; column `promotion_run.report_type_id UUID NOT NULL`.

- [ ] **Step 1: Write the migration** (it is a prerequisite of the tests, not behaviour):

```sql
-- known_report_type: projection of grading-service's report_type.is_promotion_source,
-- fed by `report_type.promotion_source_changed`.
--
-- CORRECTION OF RECORD: the comment on known_report_score.is_promotion_source in
-- V13 says the promotion engine "asks academic-config for the CURRENT flag".
-- That is wrong: the flag lives in grading-service (its V12), and there was no
-- legal path to ask (CONVENTIONS.md forbids cross-service HTTP). This projection
-- is that path. V13 is not edited because refinery checksums applied migrations.
--
-- The flag is YEAR-scoped while report_type is TERM-scoped. At most one row per
-- (tenant_id, academic_year_id) is TRUE; the consumer clears the previous one.
CREATE TABLE IF NOT EXISTS known_report_type (
  tenant_id           UUID NOT NULL,
  report_type_id      UUID NOT NULL,
  academic_year_id    UUID NOT NULL,
  is_promotion_source BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, report_type_id)
);

CREATE INDEX IF NOT EXISTS known_report_type_promotion_idx
  ON known_report_type (tenant_id, academic_year_id)
  WHERE is_promotion_source;

-- Which report type produced a run's scores. NOT NULL without backfill is safe:
-- no code path could create a promotion_run before this plan.
ALTER TABLE promotion_run
  ADD COLUMN IF NOT EXISTS report_type_id UUID NOT NULL;
```

- [ ] **Step 2: Write failing tests:**

```rust
#[tokio::test]
async fn known_report_type_true_clears_previous_source() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (tenant, year, a, b) = (uuid::Uuid::new_v4(), uuid::Uuid::new_v4(), uuid::Uuid::new_v4(), uuid::Uuid::new_v4());
    state.known_report_types.apply(tenant, year, a, true).await.unwrap();
    state.known_report_types.apply(tenant, year, b, true).await.unwrap();
    assert_eq!(state.known_report_types.find_promotion_source(tenant, year).await.unwrap(), Some(b));
    let a_flag: bool = sqlx::query_scalar("SELECT is_promotion_source FROM known_report_type WHERE report_type_id = $1")
        .bind(a).fetch_one(&pool).await.unwrap();
    assert!(!a_flag);
}

#[tokio::test]
async fn promotion_source_false_for_other_type_does_not_clear_current() {
    // Review Focus #1: A=false arriving after B=true must leave B as source.
    let (_pool, state, _url, _pg, _rabbit) = boot().await;
    let (tenant, year, a, b) = (uuid::Uuid::new_v4(), uuid::Uuid::new_v4(), uuid::Uuid::new_v4(), uuid::Uuid::new_v4());
    state.known_report_types.apply(tenant, year, b, true).await.unwrap();
    state.known_report_types.apply(tenant, year, a, false).await.unwrap();
    assert_eq!(state.known_report_types.find_promotion_source(tenant, year).await.unwrap(), Some(b));
}

#[tokio::test]
async fn promotion_source_is_scoped_by_tenant_and_year() {
    // same report ids, other tenant/year: find_promotion_source returns None for them
}

#[tokio::test]
async fn report_type_promotion_source_event_is_consumed_end_to_end() {
    // Copy grade_level_created_event_is_consumed_end_to_end (line 3485) exactly,
    // adding state.known_report_types.clone() to ProjectionConsumer::new, publishing
    // routing key "report_type.promotion_source_changed" with payload
    // { tenant_id, academic_year_id, report_type_id, is_promotion_source: true },
    // and polling known_report_type for the row. This proves ROUTING_KEYS and the
    // match arm agree.
}
```

Write the scoping and end-to-end bodies fully.

- [ ] **Step 3: Run, expect compile failure / FAIL:** `cargo test -p academic-ops-service --test integration known_report_type -- --test-threads=4`

- [ ] **Step 4: Implement `KnownReportTypeRepo`:**

```rust
/// Projection of grading-service's `report_type.is_promotion_source`. The
/// promotion engine reads the CURRENT source here — not the publish-time
/// snapshot on `known_report_score`, and not academic-config (which never
/// held this flag; see V17's header).
#[derive(Clone)]
pub struct KnownReportTypeRepo(PgPool);

impl KnownReportTypeRepo {
    pub fn new(pool: PgPool) -> Self { Self(pool) }

    pub async fn apply(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
        report_type_id: Uuid,
        is_promotion_source: bool,
    ) -> Result<(), sqlx::Error> {
        let mut tx = self.0.begin().await?;
        if is_promotion_source {
            sqlx::query(
                "UPDATE known_report_type SET is_promotion_source = FALSE, updated_at = NOW() \
                 WHERE tenant_id = $1 AND academic_year_id = $2 AND report_type_id <> $3 \
                   AND is_promotion_source",
            )
            .bind(tenant_id).bind(academic_year_id).bind(report_type_id)
            .execute(&mut *tx).await?;
        }
        sqlx::query(
            "INSERT INTO known_report_type (tenant_id, report_type_id, academic_year_id, is_promotion_source) \
             VALUES ($1,$2,$3,$4) \
             ON CONFLICT (tenant_id, report_type_id) DO UPDATE SET \
               academic_year_id = EXCLUDED.academic_year_id, \
               is_promotion_source = EXCLUDED.is_promotion_source, updated_at = NOW()",
        )
        .bind(tenant_id).bind(report_type_id).bind(academic_year_id).bind(is_promotion_source)
        .execute(&mut *tx).await?;
        tx.commit().await
    }

    pub async fn find_promotion_source(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        sqlx::query_scalar(
            "SELECT report_type_id FROM known_report_type \
             WHERE tenant_id = $1 AND academic_year_id = $2 AND is_promotion_source LIMIT 1",
        )
        .bind(tenant_id).bind(academic_year_id)
        .fetch_optional(&self.0).await
    }
}
```

Wire it: `AppState.known_report_types: KnownReportTypeRepo` constructed like `known_grade_levels`; in `events.rs` add `"report_type.promotion_source_changed"` to `ROUTING_KEYS`, a `#[derive(Deserialize)] struct ReportTypePromotionSourceChangedPayload { tenant_id: Uuid, academic_year_id: Uuid, report_type_id: Uuid, is_promotion_source: bool }`, a `known_report_types` field, a new last parameter on `ProjectionConsumer::new`, and the arm:

```rust
"report_type.promotion_source_changed" => {
    let p: ReportTypePromotionSourceChangedPayload = serde_json::from_value(envelope.payload)?;
    self.known_report_types
        .apply(p.tenant_id, p.academic_year_id, p.report_type_id, p.is_promotion_source)
        .await?;
}
```

Update all **four** `ProjectionConsumer::new` call sites.

- [ ] **Step 5: Run, expect PASS.** Then `cargo check --workspace`.
- [ ] **Step 6: Commit** `feat(academic-ops): project report type promotion source`

---

### Task 4: Bootstrap backfill + pure evaluation function

Two small, independent deliverables grouped because each is under one test cycle and neither is worth a reviewer gate alone.

**Files:**
- Modify: `scripts/bootstrap-projections.sh` (after the `known_grade_level` block)
- Create: `services/academic-ops-service/src/promotion/mod.rs`, `services/academic-ops-service/src/promotion/domain.rs`
- Modify: `services/academic-ops-service/src/lib.rs` (`pub mod promotion;`)

**Interfaces:**
- Produces (in `academic_ops_service::promotion::domain`):

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PromotionResult { Promote, Retain, Graduate }
impl PromotionResult {
    pub fn as_str(self) -> &'static str;
    pub fn parse(s: &str) -> Option<Self>;
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq)]
pub struct PromotionCriteria {
    pub min_average: Option<f64>,
    pub max_subjects_below_kkm: Option<i32>,
    pub min_attendance_percent: Option<f64>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct EvaluationMetrics {
    pub subjects_counted: usize,
    pub subjects_below_kkm: usize,
    pub average: Option<f64>,
    pub kkm_used: f64,
    pub criteria: PromotionCriteria,
}

pub fn evaluate(scores: &[f64], kkm: f64, criteria: &PromotionCriteria, is_final_grade: bool)
    -> (PromotionResult, EvaluationMetrics);

pub fn validate_criteria(criteria: &PromotionCriteria)
    -> Result<(), std::collections::BTreeMap<String, Vec<String>>>;
```

- [ ] **Step 1: Write failing unit tests** in `promotion/domain.rs` `#[cfg(test)] mod tests`:

```rust
use super::*;
fn c(min_avg: Option<f64>, max_below: Option<i32>) -> PromotionCriteria {
    PromotionCriteria { min_average: min_avg, max_subjects_below_kkm: max_below, min_attendance_percent: None }
}

#[test] fn all_null_criteria_promote() {
    assert_eq!(evaluate(&[10.0, 20.0], 75.0, &c(None, None), false).0, PromotionResult::Promote);
}
#[test] fn all_null_criteria_on_final_grade_graduate() {
    assert_eq!(evaluate(&[10.0], 75.0, &c(None, None), true).0, PromotionResult::Graduate);
}
#[test] fn too_many_below_kkm_retain() {
    assert_eq!(evaluate(&[70.0, 70.0, 90.0], 75.0, &c(None, Some(1)), false).0, PromotionResult::Retain);
}
#[test] fn below_kkm_at_limit_promotes() {
    assert_eq!(evaluate(&[70.0, 90.0], 75.0, &c(None, Some(1)), false).0, PromotionResult::Promote);
}
#[test] fn score_equal_to_kkm_is_not_below() {
    let (_, m) = evaluate(&[75.0], 75.0, &c(None, Some(0)), false);
    assert_eq!(m.subjects_below_kkm, 0);
}
#[test] fn low_average_retain() {
    assert_eq!(evaluate(&[70.0, 72.0], 60.0, &c(Some(75.0), None), false).0, PromotionResult::Retain);
}
#[test] fn retain_wins_over_graduate() {
    assert_eq!(evaluate(&[10.0], 75.0, &c(Some(75.0), None), true).0, PromotionResult::Retain);
}
#[test] fn zero_score_counts_as_score() {
    // Review Focus #2
    let (r, m) = evaluate(&[0.0, 100.0], 75.0, &c(Some(60.0), None), false);
    assert_eq!(m.subjects_counted, 2);
    assert_eq!(m.subjects_below_kkm, 1);
    assert_eq!(m.average, Some(50.0));
    assert_eq!(r, PromotionResult::Retain);
}
#[test] fn metrics_record_criteria_and_kkm() {
    let crit = c(Some(70.0), Some(2));
    let (_, m) = evaluate(&[80.0], 75.0, &crit, false);
    assert_eq!(m.kkm_used, 75.0);
    assert_eq!(m.criteria, crit);
}
#[test] fn attendance_criterion_is_rejected() {
    let crit = PromotionCriteria { min_attendance_percent: Some(80.0), ..Default::default() };
    let err = validate_criteria(&crit).unwrap_err();
    assert!(err.contains_key("min_attendance_percent"));
}
#[test] fn out_of_range_criteria_rejected() {
    let err = validate_criteria(&c(Some(101.0), Some(-1))).unwrap_err();
    assert!(err.contains_key("min_average"));
    assert!(err.contains_key("max_subjects_below_kkm"));
}
#[test] fn result_round_trips() {
    for r in [PromotionResult::Promote, PromotionResult::Retain, PromotionResult::Graduate] {
        assert_eq!(PromotionResult::parse(r.as_str()), Some(r));
    }
    assert_eq!(PromotionResult::parse("skip"), None);
}
```

`evaluate` is only ever called with a non-empty `scores` slice (students without scores go to "cannot evaluate", spec §2.7); document that with a `debug_assert!(!scores.is_empty())`.

- [ ] **Step 2: Run, expect FAIL:** `cargo test -p academic-ops-service --lib promotion::domain`

- [ ] **Step 3: Implement** `evaluate`: `below = scores.iter().filter(|s| **s < kkm).count()`, `average = Some(sum / len)`; retain if `max_subjects_below_kkm` is `Some(m)` and `below > m as usize`, or `min_average` is `Some(a)` and `average < a`; else `Graduate` if `is_final_grade`; else `Promote`. `validate_criteria`: `min_attendance_percent.is_some()` → `"attendance criterion is not available yet"`; `min_average` outside `0.0..=100.0` → `"must be between 0 and 100"`; `max_subjects_below_kkm < 0` → `"must be zero or greater"`. `mod.rs`: `pub mod domain;`.

- [ ] **Step 4: Bootstrap backfill.** Append after the `known_grade_level` re-link block, same `run_upsert` shape:

```bash
# academic_ops.known_report_type: mirrors grading.report_type.is_promotion_source.
# RabbitMQ does not replay report_type.promotion_source_changed events published
# before academic-ops' queue bound that key, so without this the promotion engine
# sees no source for any existing year and refuses to run.
run_upsert "academic_ops.known_report_type" "academic_ops.known_report_type grading.report_type" "
WITH upserted AS (
  INSERT INTO academic_ops.known_report_type
    (tenant_id, report_type_id, academic_year_id, is_promotion_source, updated_at)
  SELECT tenant_id, report_type_id, academic_year_id, is_promotion_source, NOW()
  FROM grading.report_type
  ON CONFLICT (tenant_id, report_type_id) DO UPDATE
  SET academic_year_id    = EXCLUDED.academic_year_id,
      is_promotion_source = EXCLUDED.is_promotion_source,
      updated_at          = NOW()
  RETURNING 1
)
SELECT COUNT(*) FROM upserted;
"
```

Verify: `bash -n scripts/bootstrap-projections.sh`. Then run it twice against the dev stack (`make up` must be running); both runs must exit 0 and report the same row count.

- [ ] **Step 5: Run unit tests, expect PASS;** `cargo check --workspace`.
- [ ] **Step 6: Commit** `feat(academic-ops): add promotion evaluation rules and report type backfill`

---

### Task 5: Create a promotion run (`POST /promotion-runs`)

**Files:**
- Create: `services/academic-ops-service/src/promotion/repo.rs`, `src/promotion/commands.rs`, `src/promotion/http.rs`
- Modify: `src/promotion/mod.rs` (`pub mod repo; pub mod commands; pub mod http;` — `queries` comes in Task 7)
- Modify: `src/http.rs` — make `AcademicOpsEntitlement` and `envelope` `pub(crate)`; merge `crate::promotion::http::routes()` into the router before state is applied
- Test: `tests/integration.rs`

**Interfaces:**
- Consumes: Task 3 `known_report_types`, Task 4 `domain::{evaluate, validate_criteria, PromotionCriteria, PromotionResult, EvaluationMetrics}`, existing `crate::repo::promotion_score_readiness`.
- Produces:

```rust
// promotion/commands.rs
pub struct CreatePromotionRun { pub tenant_id: Uuid, pub user_id: Uuid, pub academic_year_id: Uuid, pub criteria: PromotionCriteria }
#[derive(Serialize)]
pub struct PromotionRunOutcome {
    pub run_id: Uuid, pub status: String, pub report_type_id: Uuid, pub rule_id: Uuid,
    pub counts: ResultCounts, pub cannot_evaluate: Vec<Uuid>, pub discarded_overrides: i64,
}
#[derive(Serialize, Default)]
pub struct ResultCounts { pub promote: i64, pub retain: i64, pub graduate: i64 }
pub async fn create_promotion_run(state: &AppState, input: CreatePromotionRun) -> Result<PromotionRunOutcome, AppError>;
// shared with Task 6:
pub(crate) async fn check_preconditions(state: &AppState, tenant_id: Uuid, academic_year_id: Uuid) -> Result<Preconditions, AppError>;
pub(crate) struct Preconditions { pub report_type_id: Uuid, pub kkm: f64 }
pub(crate) async fn evaluate_into(tx: &mut sqlx::PgConnection, state: &AppState, tenant_id: Uuid, run_id: Uuid,
    academic_year_id: Uuid, report_type_id: Uuid, kkm: f64, criteria: &PromotionCriteria)
    -> Result<(ResultCounts, Vec<Uuid>), AppError>;
```

Routes (all `_feature: AcademicOpsEntitlement`, `auth: AuthContext`):
`POST /api/v1/academic-ops/promotion-runs` → `auth.require_permission(PERM_PROMOTION_MANAGE)?` → 201 with `envelope(outcome)`. Body: `{ academic_year_id, min_average?, max_subjects_below_kkm?, min_attendance_percent? }`.

**Command order (all validation before any write):**
1. `validate_criteria` → `VALIDATION_ERROR` with its fields.
2. `check_preconditions` — collect ALL failures into one `BTreeMap`, return `AppError::validation_error(fields)` if non-empty:
   - `academic_year`: `known_academic_year` row for (tenant, year) with status `Active` or `Closed`; else `"academic year must be Active or Closed"`.
   - `grade_levels`: `SELECT count(*) FROM known_grade_level WHERE tenant_id=$1 AND academic_year_id=$2 AND is_final` must be exactly 1; else `"exactly one final grade level is required (found N)"`.
   - `report_type`: `known_report_types.find_promotion_source` is `Some`; else `"no promotion-source report type for this year"`.
   - `homerooms`: dangling OR NULL links (spec §2.6), one message per homeroom name:
     ```sql
     SELECT h.name FROM homeroom h
     LEFT JOIN known_grade_level kgl
       ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id
     WHERE h.tenant_id = $1 AND h.academic_year_id = $2 AND kgl.grade_level_id IS NULL
     ORDER BY h.name
     ```
     message: `format!("homeroom {name} is not linked to a grade level")`.
   - `grading_policy`: `known_grading_policy` row exists; else `"no grading policy (KKM) configured for this year"`. Its `minimum_passing_score` is `kkm`.
3. Reject if a run already exists for (tenant, year) with status other than `executed`: `AppError::conflict("PROMOTION_RUN_EXISTS", "a promotion run already exists for this academic year; re-evaluate it instead")`.
4. One transaction: insert `promotion_rule_snapshot` (`kkm_snapshot = kkm`), insert `promotion_run` (`status='draft'`, `created_by = user_id`, `report_type_id`), then `evaluate_into`, commit.

**`evaluate_into`:**
- Enrollments: `SELECT e.enrollment_id, e.student_id, e.homeroom_id, kgl.is_final FROM enrollment e JOIN homeroom h ON h.homeroom_id = e.homeroom_id AND h.tenant_id = e.tenant_id JOIN known_grade_level kgl ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id WHERE e.tenant_id=$1 AND e.academic_year_id=$2 AND e.status='active'`.
- Scores: `SELECT student_id, final_score FROM known_report_score WHERE tenant_id=$1 AND academic_year_id=$2 AND report_type_id=$3`, grouped into `HashMap<Uuid, Vec<f64>>`.
- Student with no scores → push to `cannot_evaluate` (sorted), **no decision row**.
- Otherwise `evaluate(...)`; insert `promotion_decision` with `recommended = result = r.as_str()`, `overridden = false`, `reason = NULL`, `computed_metrics = serde_json::to_value(metrics)`, `target_homeroom_id = NULL`.

- [ ] **Step 1: Write the fixture helper and failing tests.** Add to `tests/integration.rs`:

```rust
struct PromotionFixture {
    tenant_id: uuid::Uuid, year_id: uuid::Uuid, report_type_id: uuid::Uuid,
    final_level: uuid::Uuid, mid_level: uuid::Uuid,
    mid_homeroom: uuid::Uuid, final_homeroom: uuid::Uuid,
}

/// Year Active, two grade levels (one final), one homeroom per level linked via
/// grade_level_id, grading policy KKM 75, and a promotion-source report type.
/// No students: tests add them with `seed_promoted_student`.
async fn seed_promotion_fixture(pool: &PgPool, state: &AppState) -> PromotionFixture { /* direct SQL inserts + state.known_report_types.apply(..., true) + seed_active_subscription */ }

/// Inserts student + active enrollment in `homeroom_id`, and one
/// known_report_score row per score (fresh subject_id each). Empty `scores`
/// means "no published card".
async fn seed_promoted_student(pool: &PgPool, fx: &PromotionFixture, homeroom_id: uuid::Uuid, scores: &[f64]) -> uuid::Uuid {
    let student_id = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO student (student_id, tenant_id, nis, full_name, gender, birth_date) \
         VALUES ($1, $2, $3, 'Promo Student', 'female', '2012-01-01')",
    )
    .bind(student_id).bind(fx.tenant_id).bind(format!("P-{student_id}"))
    .execute(pool).await.unwrap();
    sqlx::query(
        "INSERT INTO enrollment (enrollment_id, tenant_id, student_id, homeroom_id, academic_year_id, status) \
         VALUES ($1, $2, $3, $4, $5, 'active')",
    )
    .bind(uuid::Uuid::new_v4()).bind(fx.tenant_id).bind(student_id).bind(homeroom_id).bind(fx.year_id)
    .execute(pool).await.unwrap();
    for score in scores {
        sqlx::query(
            "INSERT INTO known_report_score \
               (tenant_id, academic_year_id, student_id, subject_id, report_type_id, final_score, is_promotion_source) \
             VALUES ($1, $2, $3, $4, $5, $6, TRUE)",
        )
        .bind(fx.tenant_id).bind(fx.year_id).bind(student_id).bind(uuid::Uuid::new_v4())
        .bind(fx.report_type_id).bind(score)
        .execute(pool).await.unwrap();
    }
    student_id
}

async fn create_run(app: axum::Router, token: &str, body: Value) -> (StatusCode, Value) {
    let resp = post_json(app, token, "/api/v1/academic-ops/promotion-runs", body).await;
    let status = resp.status();
    (status, body_to_json(resp).await)
}
```

Write the helper bodies fully (student insert needs `student_id, tenant_id, nis, full_name, gender, birth_date`; use unique `nis` per call). Tests:

- `promotion_run_evaluates_each_branch` — four students: mid homeroom `[90,90]` → promote; mid `[60,60,90]` with `max_subjects_below_kkm: 1` → retain; final `[90]` → graduate; mid `[]` → in `cannot_evaluate`. Assert 201, `counts`, `cannot_evaluate == [id]`, and that `promotion_decision` has exactly 3 rows with `recommended == result`, `overridden = false`, and `computed_metrics->>'kkm_used' = '75'`.
- `promotion_run_all_null_criteria_promotes_everyone_not_final`.
- `promotion_run_rejects_attendance_criterion` — **400** `VALIDATION_ERROR` (`AppError::Validation` maps to `StatusCode::BAD_REQUEST`, `libs/common-errors/src/lib.rs:147`), `error.fields.min_attendance_percent` present, **zero** rows in `promotion_run`.
- `promotion_run_reports_all_failed_preconditions_together` — year `Planning`, no final level, no report type, no grading policy: one response whose `fields` has `academic_year`, `grade_levels`, `report_type`, `grading_policy`.
- `promotion_run_blocks_dangling_grade_level_link` — set a homeroom's `grade_level_id` to a random UUID (non-NULL, no projection row): `fields.homerooms` names it. Repeat with NULL: same.
- `promotion_run_second_create_is_conflict` — 409 `PROMOTION_RUN_EXISTS`.
- `promotion_run_requires_manage_permission` — principal token → 403 `FORBIDDEN`.
- `promotion_run_uses_current_source_not_snapshot` — seed scores for report type A (projection says B is source): students have no B scores → all in `cannot_evaluate`, `report_type_id == B`.

- [ ] **Step 2: Run, expect FAIL** (404 route): `cargo test -p academic-ops-service --test integration promotion_run -- --test-threads=4`
- [ ] **Step 3: Implement** `repo.rs` (plain `sqlx` functions taking `&PgPool` or `&mut PgConnection`, tenant-filtered), `commands.rs`, `http.rs` (`pub fn routes() -> Router<AppState>`), and the `http.rs` merge.
- [ ] **Step 4: Run, expect PASS;** `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): create and evaluate promotion runs`

---

### Task 6: Re-evaluate and override

**Files:**
- Modify: `src/promotion/{repo,commands,http}.rs`
- Test: `tests/integration.rs`

**Interfaces:**
- Consumes: Task 5 `check_preconditions`, `evaluate_into`, `PromotionRunOutcome`.
- Produces:

```rust
pub struct ReevaluatePromotionRun { pub tenant_id: Uuid, pub run_id: Uuid, pub criteria: PromotionCriteria }
pub async fn reevaluate_promotion_run(state: &AppState, input: ReevaluatePromotionRun) -> Result<PromotionRunOutcome, AppError>;
pub struct OverrideDecision { pub tenant_id: Uuid, pub run_id: Uuid, pub decision_id: Uuid, pub result: String, pub reason: Option<String> }
pub async fn override_decision(state: &AppState, input: OverrideDecision) -> Result<DecisionView, AppError>;
#[derive(Serialize)]
pub struct DecisionView { pub decision_id: Uuid, pub student_id: Uuid, pub homeroom_id: Uuid,
    pub recommended: String, pub result: String, pub overridden: bool, pub reason: Option<String>,
    pub computed_metrics: serde_json::Value }
```

Routes (both `promotion.manage`):
- `POST /api/v1/academic-ops/promotion-runs/:run_id/evaluate` → 200. Body = criteria only.
- `PATCH /api/v1/academic-ops/promotion-runs/:run_id/decisions/:decision_id` → 200. Body `{ result, reason? }`.

**Re-evaluate** (spec §2.9): run not found for tenant → 404; status ≠ `draft` → 409 `PROMOTION_RUN_INVALID_STATUS`; `validate_criteria`; `check_preconditions`; then one tx: `SELECT … FOR UPDATE` the run and re-check `draft`; `discarded = SELECT count(*) … WHERE run_id=$1 AND overridden`; `DELETE FROM promotion_decision WHERE run_id=$1`; insert new snapshot; `UPDATE promotion_run SET rule_id=$new, report_type_id=$rt, updated_at=NOW()`; `evaluate_into`; commit. Return `discarded_overrides = discarded`. The old snapshot row stays (it is referenced by nothing, but is audit history).

**Override:** run (tenant-scoped) must be `draft` else 409 `PROMOTION_RUN_INVALID_STATUS`; decision must belong to the run and tenant else 404; `PromotionResult::parse(result)` else `VALIDATION_ERROR fields.result`. If `result == recommended` → set `result`, `overridden=false`, `reason=NULL` (Review Focus #5). Else trim reason; `None` or `trim().chars().count() < 10` → `VALIDATION_ERROR fields.reason = ["reason must be at least 10 characters"]` (checked here so the DB constraint is a backstop, not the user-facing error); set `result`, `overridden=true`, `reason=trimmed`. `recommended` is never written.

- [ ] **Step 1: Write failing tests:**
  - `override_changes_result_only` — `recommended` unchanged, `overridden=true`, reason stored trimmed.
  - `override_requires_real_reason` — `"ok"` and `"          "` (10 spaces) → `fields.reason`; row unchanged.
  - `override_back_to_recommendation_clears_flag`.
  - `override_rejects_unknown_result` — `"skip"` → `fields.result`.
  - `override_on_submitted_run_is_conflict` — set status to `submitted` via SQL, then PATCH → 409.
  - `reevaluate_replaces_decisions_and_reports_discarded_overrides` — override one, re-evaluate with stricter criteria: `discarded_overrides == 1`, no decision has `overridden`, `rule_id` changed, old snapshot row still exists.
  - `reevaluate_outside_draft_is_conflict`.
  - `reevaluate_picks_up_moved_source` — move projection source to B (with B scores seeded), re-evaluate: `report_type_id == B`.
- [ ] **Step 2: Run, expect FAIL:** `cargo test -p academic-ops-service --test integration -- --test-threads=4 override reevaluate`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS;** `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): re-evaluate promotion runs and override decisions`

---

### Task 7: Read side — list, detail, decisions

**Files:**
- Create: `src/promotion/queries.rs` (query handlers live apart from commands — CQRS rule)
- Modify: `src/promotion/{mod,repo,http}.rs`
- Test: `tests/integration.rs`

**Interfaces:**
- Produces:

```rust
#[derive(Serialize)]
pub struct PromotionRunView { pub run_id: Uuid, pub academic_year_id: Uuid, pub report_type_id: Uuid,
    pub rule_id: Uuid, pub status: String, pub created_by: Uuid, pub approved_by: Option<Uuid>,
    pub created_at: DateTime<Utc>, pub updated_at: DateTime<Utc> }
#[derive(Serialize)]
pub struct PromotionRunDetail { pub run: PromotionRunView, pub criteria: PromotionCriteria, pub kkm: f64,
    pub counts: ResultCounts, pub overridden: i64, pub cannot_evaluate: Vec<Uuid> }
pub async fn list_promotion_runs(state: &AppState, tenant_id: Uuid, academic_year_id: Uuid) -> Result<Vec<PromotionRunView>, AppError>;
pub async fn get_promotion_run(state: &AppState, tenant_id: Uuid, run_id: Uuid) -> Result<PromotionRunDetail, AppError>;
pub async fn list_decisions(state: &AppState, tenant_id: Uuid, run_id: Uuid, homeroom_id: Option<Uuid>) -> Result<Vec<DecisionView>, AppError>;
```

Routes (all `promotion.manage` OR `promotion.approve` — a principal must read what they approve; check with `if !auth.has_permission(MANAGE) && !auth.has_permission(APPROVE) { return Err(AppError::forbidden("FORBIDDEN", "missing required permission: promotion.manage or promotion.approve")) }`):
- `GET /promotion-runs?academic_year_id=` (missing param → `VALIDATION_ERROR fields.academic_year_id`), newest first.
- `GET /promotion-runs/:run_id` → 404 if not the tenant's. `cannot_evaluate` is computed live via `crate::repo::promotion_score_readiness(pool, tenant, year, run.report_type_id)` (spec §2.7) — not stored.
- `GET /promotion-runs/:run_id/decisions?homeroom_id=` → ordered by `homeroom_id, student_id`.

Every query joins/filters `tenant_id`; a run id from another tenant is simply not found.

- [ ] **Step 1: Write failing tests:** `list_runs_filters_by_year`, `run_detail_includes_counts_criteria_and_cannot_evaluate`, `decisions_filter_by_homeroom`, `principal_can_read_runs`, `teacher_cannot_read_runs` (403), and `other_tenant_cannot_see_or_override_run` (Review Focus #4): tenant B token → 404 on GET detail, GET decisions, PATCH decision, POST evaluate for tenant A's ids; tenant A's rows unchanged afterwards.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS;** `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): read promotion runs and decisions`

---

### Task 8: Submit, approve, return

**Files:**
- Modify: `src/promotion/{repo,commands,http}.rs`
- Test: `tests/integration.rs`

**Interfaces:**
- Produces:

```rust
pub enum RunTransition { Submit, Approve, Return }
pub async fn transition_promotion_run(state: &AppState, tenant_id: Uuid, user_id: Uuid, run_id: Uuid, t: RunTransition)
    -> Result<PromotionRunView, AppError>;
```

| Route | Permission | From → To | Extra |
|---|---|---|---|
| `POST /promotion-runs/:run_id/submit` | `promotion.manage` | draft → submitted | — |
| `POST /promotion-runs/:run_id/approve` | `promotion.approve` | submitted → approved | `approved_by = user_id`; reject `user_id == created_by` |
| `POST /promotion-runs/:run_id/return` | `promotion.approve` | submitted → draft | `approved_by` stays NULL |

Implementation: first load the run (tenant-scoped) → 404 if absent. For approve, if `run.created_by == user_id` → `AppError::forbidden("PROMOTION_SELF_APPROVAL", "the user who created a promotion run cannot approve it")` (spec §2.10). Then a single conditional statement so concurrent requests cannot both win:

```sql
UPDATE promotion_run
SET status = $4, approved_by = COALESCE($5, approved_by), updated_at = NOW()
WHERE tenant_id = $1 AND run_id = $2 AND status = $3
RETURNING *
```

Zero rows → `AppError::conflict("PROMOTION_RUN_INVALID_STATUS", format!("run is not {expected}"))`.

- [ ] **Step 1: Write failing tests:**
  - `run_lifecycle_submit_approve` — admin submits, principal approves: status `approved`, `approved_by` = principal's user id.
  - `return_sends_run_back_to_draft` — then override works again.
  - `submit_requires_manage_and_approve_requires_approve` — principal submit → 403; admin approve → 403.
  - `approve_draft_is_conflict`.
  - `second_approve_is_conflict` (Review Focus #3) — fire two approve requests with `tokio::join!` on cloned routers: exactly one 200, one 409.
  - `creator_cannot_approve_own_run` — mint a token for the creator's `user_id` that carries both `promotion.manage` and `promotion.approve` (use `common_auth::jwt::JwtEncoder::from_pem(dev_keys::PRIVATE_PEM)` and `.issue(user_id, tenant_id, roles, perms, ttl)` as `libs/common-testing/src/jwt.rs` does); create with it, submit, approve with it → 403 `PROMOTION_SELF_APPROVAL`; status still `submitted`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS;** `cargo check --workspace`.
- [ ] **Step 5: Commit** `feat(academic-ops): submit, approve, and return promotion runs`

---

### Task 9: Final gate

**Files:** none changed unless a check fails.

- [ ] **Step 1:** `cargo check --workspace` and `cargo clippy --workspace --all-targets -- -D warnings` (if clippy already fails on `feat/promotion-foundation`, record the pre-existing count and require it not to grow).
- [ ] **Step 2:** Suites, one at a time: `cargo test -p grading-service --test integration -- --test-threads=4`, `cargo test -p academic-ops-service --test integration -- --test-threads=4`, `cargo test -p academic-ops-service --lib`, `cargo test -p common-testing`, `cargo test -p iam-service --test integration -- --test-threads=4`, `cargo test -p academic-config-service --test integration -- --test-threads=4`. Only the three known failures may fail — confirm by **name**, not count.
- [ ] **Step 3:** Apply V17 twice to the dev DB (`docker compose exec -T postgres psql … -f`); second run must not error. Run `scripts/bootstrap-projections.sh` twice; same counts both times.
- [ ] **Step 4:** Trailer audit: `git log feat/promotion-foundation..HEAD --format='%B' | grep -ciE "co-authored|signed-off|generated with|claude|hermes"` → 0.
- [ ] **Step 5:** In the parent repo, bump the `apps/backend` pointer: `git add apps/backend && git commit -m "chore: bump backend to promotion evaluation"`. Do not push.
