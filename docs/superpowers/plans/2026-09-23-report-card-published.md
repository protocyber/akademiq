# Report Card Published Event + Promotion Projections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the report-card scores and grading policy that the promotion engine needs into `academic-ops-service` as local projections, fed by events, with no cross-service HTTP.

**Architecture:** `grading-service` gains an `is_promotion_source` flag on `report_type` (command-layer enforced, at most one per academic year), renames its existing `report_card.approved` event to `report_card.published`, and enriches the payload with the frozen per-subject scores. `academic-ops-service` gains two `known_*` projections fed by that event and by the existing `grading_policy.configured` event. Status CHECK constraints in both services gain the new enrollment/student states in one change.

**Tech Stack:** Rust, Axum, SQLx 0.8, refinery migrations, PostgreSQL 18, RabbitMQ, testcontainers

**Spec:** `docs/superpowers/specs/2026-09-23-report-card-published-design.md`
**Parent spec:** `docs/superpowers/specs/2026-09-23-promotion-design.md` (§3.2, §5)

## Global Constraints

- Migrations are immutable once applied. Next free version is **V12** in BOTH `grading-service` and `academic-ops-service`.
- `refinery::embed_migrations!` inlines SQL at COMPILE time and cargo does NOT watch `migrations/`. After adding or editing any `V*.sql`, run `touch services/<service>/src/lib.rs` or tests falsely fail with "relation does not exist".
- Backend integration suites MUST run with `--test-threads=4`. Default parallelism causes spurious testcontainer resource-contention failures.
- Validation errors are HTTP **400** with `{"error":{"code":"VALIDATION_ERROR","fields":{...}}}`. Never 422. (`libs/common-errors/src/lib.rs:147`)
- Conflict errors are HTTP 409 via `AppError::conflict(CODE, msg)`.
- Never trust a client-supplied `tenant_id`; resolve it from the JWT.
- CQRS: commands and queries live in separate modules. Validation belongs in the command layer, never the repo.
- Every projection query and every repo method MUST be scoped by `tenant_id`.
- `minimum_passing_score` is `DOUBLE PRECISION` everywhere. Do NOT use `NUMERIC` (the parent spec §5 is wrong on this; producer `academic-config` V1:64 and existing consumer `grading` V3:6 are both `DOUBLE PRECISION`).
- Score source is `report_subject_score.final_score` (frozen at generation). NEVER `subject_report_score` (mutable, changes whenever a teacher saves). The two names are nearly identical — check twice.
- Commit messages contain ONLY the message. No `Co-authored-by:`, no `Signed-off-by:`, no "Generated with", no tool or model identifiers.
- Commit in the submodule you are working in. Do not commit in the parent repo.

## Review Focus

1. **A student with no score rows at all** (report never published, or published before this feature shipped) must make the future evaluation REFUSE to run for that student — never be treated as score `0`, which silently means "held back". Pinned in Task 6.
2. **Two report types flagged `is_promotion_source` in one year** must be rejected at the producer AND detectable by the consumer. The producer rule is command-layer only, so the consumer must not trust it. Pinned in Tasks 1 and 6.
3. **A report card regenerated with FEWER subjects** must not leave orphan score rows behind — a stale subject would silently drag the average. Pinned in Task 5.
4. **The same event delivered twice** (RabbitMQ redelivery) must leave identical state. Pinned in Task 5.
5. **Scores edited after a report card is published** must NOT change what was already projected — the payload must come from the frozen table. Pinned in Task 2.

---

## File Structure

| File | Responsibility |
|---|---|
| `grading-service/migrations/V12__report_type_promotion_source.sql` | Add `is_promotion_source` to `report_type` |
| `grading-service/src/domain.rs` | `ReportType` gains the field |
| `grading-service/src/repo.rs` | Read/write the flag; fetch frozen scores for an event payload |
| `grading-service/src/commands.rs` | Enforce at-most-one flag; enrich + rename the outbox event |
| `grading-service/src/http.rs` | Accept the flag on report-type create/update |
| `grading-service/tests/integration.rs` | Producer-side tests |
| `grading-service/migrations/V13__enrolled_student_promoted.sql` | Add `'promoted'` to `enrolled_student` CHECK |
| `academic-ops-service/migrations/V12__promotion_status_values.sql` | Add `'promoted'` to `enrollment`, `'lulus'`/`'alumni'` to `student` |
| `academic-ops-service/migrations/V13__known_report_score.sql` | The two `known_*` projection tables |
| `academic-ops-service/src/repo.rs` | `KnownReportScoreRepo`, `KnownGradingPolicyRepo` |
| `academic-ops-service/src/events.rs` | `ProjectionConsumer` gains both repos; consumes `report_card.published` + `grading_policy.configured` |
| `academic-ops-service/tests/integration.rs` | Consumer-side tests |
| `docs/internal/11_integration_contracts/events/report-card-published.md` | Replaces `report-card-approved.md` |
| `docs/internal/10_data_design/*.md` | ERD updates |

---

### Task 1: `is_promotion_source` flag on `report_type`

**Files:**
- Create: `apps/backend/services/grading-service/migrations/V12__report_type_promotion_source.sql`
- Modify: `apps/backend/services/grading-service/src/domain.rs`, `src/repo.rs`, `src/commands.rs`, `src/http.rs`
- Test: `apps/backend/services/grading-service/tests/integration.rs`

**Interfaces:**
- Produces: `ReportType.is_promotion_source: bool`; `ReportTypeRepo::find_promotion_source(tenant_id, academic_year_id) -> Result<Option<ReportType>, sqlx::Error>`; command error code `REPORT_TYPE_PROMOTION_SOURCE_TAKEN`.

- [ ] **Step 1: Write the failing migration test**

**Testing note — the harness, verified.** `boot()` in `grading-service/tests/integration.rs:14` returns a 3-tuple `(pool, state, _pg_container)` — there is NO `app.pool` field. Existing helpers you MUST reuse rather than reinvent: `jwt_for(user_id, tenant_id)`, `jwt_for_role(user_id, tenant_id, role)`, `body_to_json(resp)`, `seed_active_subscription(pool, tenant_id)`, `seed_report_type(pool, tenant_id, year_id, code, name)`, `post_report_type(...)`. Note `seed_report_type` already fills `term_id` as `md5(year::text)::uuid`. Build the router with `grading_service::http::router(state)` as the sibling tests do. Helpers named in this plan that do NOT exist (`principal_token`, `create_report_type`, `update_report_type`, `to_json`, `id_from`, `seed_year`, `seed_extra_year`) are illustrative — use the real ones above, or add a small helper next to them in the same style.

```rust
#[tokio::test]
async fn report_type_has_promotion_source_column_defaulting_false() {
    let (pool, _state, _pg) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let type_id = seed_report_type(&pool, tenant_id, year_id, "UTS", "Ujian Tengah Semester").await;

    let flag: bool = sqlx::query_scalar(
        "SELECT is_promotion_source FROM report_type WHERE report_type_id = $1",
    )
    .bind(type_id)
    .fetch_one(&pool)
    .await
    .expect("column must exist");

    assert!(!flag, "new report types must not be the promotion source by default");
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p grading-service --test integration report_type_has_promotion_source_column -- --test-threads=4`
Expected: FAIL — `column "is_promotion_source" does not exist`.

- [ ] **Step 3: Write the migration**

Create `migrations/V12__report_type_promotion_source.sql`:

```sql
-- Marks which report type decides grade promotion for its academic year.
-- At most one per (tenant, academic_year) — enforced in the command layer,
-- mirroring grade_level.is_final in academic-config-service. No DB constraint,
-- deliberately: see docs/superpowers/specs/2026-09-23-report-card-published-design.md §3.3.
--
-- NOTE the scope difference: report_type itself is TERM-scoped
-- (report_type_term_code_unique on (academic_year_id, term_id, code), V7), but
-- the promotion-source flag is YEAR-scoped. A year has several terms, each with
-- its own report types; exactly one of them across the whole year decides
-- promotion. The partial index below is deliberately NOT unique — uniqueness is
-- the command layer's job.
ALTER TABLE report_type
  ADD COLUMN IF NOT EXISTS is_promotion_source BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS report_type_promotion_source_idx
  ON report_type (tenant_id, academic_year_id)
  WHERE is_promotion_source;
```

Then run `touch services/grading-service/src/lib.rs` (refinery inlines SQL at compile time).

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cargo test -p grading-service --test integration report_type_has_promotion_source_column -- --test-threads=4`
Expected: PASS.

- [ ] **Step 5: Write the failing test for the at-most-one rule**

```rust
#[tokio::test]
async fn second_promotion_source_report_type_is_rejected() {
    let app = boot().await;
    let (tenant_id, year_id) = seed_year(&app).await;
    let token = principal_token(&app, tenant_id);

    let first = create_report_type(&app, &token, year_id, "UAS", true).await;
    assert_eq!(first.status(), 200);

    let second = create_report_type(&app, &token, year_id, "UTS", true).await;
    assert_eq!(second.status(), 409, "a year may have only one promotion source");
    let body: serde_json::Value = to_json(second).await;
    assert_eq!(body["error"]["code"], "REPORT_TYPE_PROMOTION_SOURCE_TAKEN");
}

#[tokio::test]
async fn resaving_the_same_promotion_source_is_allowed() {
    let app = boot().await;
    let (tenant_id, year_id) = seed_year(&app).await;
    let token = principal_token(&app, tenant_id);

    let created = create_report_type(&app, &token, year_id, "UAS", true).await;
    let type_id = id_from(created).await;

    let resaved = update_report_type(&app, &token, type_id, "UAS Revisi", true).await;
    assert_eq!(resaved.status(), 200, "a type may keep its own flag");
}

#[tokio::test]
async fn promotion_source_is_scoped_per_academic_year() {
    let app = boot().await;
    let (tenant_id, year_a) = seed_year(&app).await;
    let year_b = seed_extra_year(&app, tenant_id).await;
    let token = principal_token(&app, tenant_id);

    assert_eq!(create_report_type(&app, &token, year_a, "UAS", true).await.status(), 200);
    assert_eq!(
        create_report_type(&app, &token, year_b, "UAS", true).await.status(),
        200,
        "a different year may have its own promotion source"
    );
}
```

- [ ] **Step 6: Run them and confirm they fail**

Run: `cargo test -p grading-service --test integration promotion_source -- --test-threads=4`
Expected: FAIL — the flag is accepted unconditionally, no 409.

- [ ] **Step 7: Add the field to the domain type**

In `src/domain.rs`, add to the `ReportType` struct:

```rust
pub is_promotion_source: bool,
```

Update every construction site the compiler flags.

- [ ] **Step 8: Add the repo lookup**

In `src/repo.rs`, on `GradeRepo` (report types live there — there is no separate `report_types` repo):

```rust
pub async fn find_promotion_source(
    &self,
    tenant_id: Uuid,
    academic_year_id: Uuid,
) -> Result<Option<ReportType>, sqlx::Error> {
    sqlx::query_as::<_, ReportType>(
        "SELECT report_type_id, tenant_id, academic_year_id, term_id, code, name, position, \
         is_promotion_source, created_at, updated_at \
         FROM report_type \
         WHERE tenant_id = $1 AND academic_year_id = $2 AND is_promotion_source",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .fetch_optional(&self.0)
    .await
}
```

Note `term_id` in the column list: `report_type` has a NOT NULL `term_id` (added in V7), and omitting it makes the row decode fail at runtime.

Include `is_promotion_source` in the column list of every existing `report_type` SELECT, INSERT and UPDATE the compiler points at.

- [ ] **Step 9: Enforce the rule in the command layer**

In `src/commands.rs`:

```rust
/// At most one report type per academic year may be the promotion source.
/// Enforced here rather than by a DB constraint, mirroring
/// `grade_level.is_final` in academic-config-service.
async fn ensure_no_other_promotion_source(
    state: &AppState,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    self_id: Option<Uuid>,
) -> Result<(), AppError> {
    let existing = state
        .grades
        .find_promotion_source(tenant_id, academic_year_id)
        .await
        .map_err(AppError::internal)?;

    match existing {
        Some(found) if Some(found.report_type_id) != self_id => Err(AppError::conflict(
            "REPORT_TYPE_PROMOTION_SOURCE_TAKEN",
            "another report type is already the promotion source for this academic year",
        )),
        _ => Ok(()),
    }
}
```

Call it from BOTH the create and update commands, before writing, and only when the incoming `is_promotion_source` is `true`. On create pass `None` as `self_id`; on update pass `Some(report_type_id)` so a type can keep its own flag.

- [ ] **Step 10: Accept the flag over HTTP**

In `src/http.rs`, add `#[serde(default)] is_promotion_source: bool` to the report-type create and update body structs, and thread it into the command inputs.

- [ ] **Step 11: Run the tests and confirm they pass**

Run: `cargo test -p grading-service --test integration promotion_source -- --test-threads=4`
Expected: PASS (3 tests).

- [ ] **Step 12: Commit**

```bash
cd apps/backend
git add services/grading-service/migrations/V12__report_type_promotion_source.sql \
        services/grading-service/src/domain.rs services/grading-service/src/repo.rs \
        services/grading-service/src/commands.rs services/grading-service/src/http.rs \
        services/grading-service/tests/integration.rs
git commit -m "feat(grading): mark which report type decides promotion"
```

---

### Task 2: Rename the event and carry the frozen scores

**Files:**
- Modify: `apps/backend/services/grading-service/src/repo.rs`, `src/commands.rs:1574-1590`
- Test: `apps/backend/services/grading-service/tests/integration.rs`

**Interfaces:**
- Consumes: `ReportTypeRepo::find_promotion_source` (Task 1).
- Produces: outbox event `report_card.published` with payload `{tenant_id, student_id, academic_year_id, report_card_id, report_type_id, is_promotion_source, scores: [{subject_id, final_score}]}`; `ReportCardRepo::frozen_scores(report_card_id) -> Result<Vec<(Uuid, f64)>, sqlx::Error>`.

**Context:** `commands.rs:1574` ALREADY emits an event at exactly the right moment — the transition to `Published`. It is only misnamed (`report_card.approved`, a leftover from before the `Published` status existed) and carries no scores. The old name has ZERO consumers anywhere in the monorepo; the only other mention is the assertion in `tests/integration.rs:1257,1262`. No `event_type_v2` is needed.

- [ ] **Step 1: Write the failing test for the renamed, enriched event**

```rust
#[tokio::test]
async fn publishing_a_report_card_emits_scores_on_the_outbox() {
    let app = boot().await;
    let ctx = seed_published_ready_card(&app).await;

    publish_report_card(&app, &ctx).await;

    let (event_type, payload): (String, serde_json::Value) = sqlx::query_as(
        "SELECT event_type, payload FROM outbox WHERE event_type = 'report_card.published' LIMIT 1",
    )
    .fetch_one(&app.pool)
    .await
    .expect("a report_card.published event must exist");

    assert_eq!(event_type, "report_card.published");
    assert_eq!(payload["report_card_id"], json!(ctx.report_card_id));
    assert_eq!(payload["report_type_id"], json!(ctx.report_type_id));
    assert_eq!(payload["is_promotion_source"], json!(true));

    let scores = payload["scores"].as_array().expect("scores must be an array");
    assert_eq!(scores.len(), 2, "every frozen subject score must be carried");
    let by_subject: std::collections::BTreeMap<String, f64> = scores
        .iter()
        .map(|s| (s["subject_id"].as_str().unwrap().to_string(), s["final_score"].as_f64().unwrap()))
        .collect();
    assert_eq!(by_subject[&ctx.subject_a.to_string()], 82.5);
    assert_eq!(by_subject[&ctx.subject_b.to_string()], 65.0);
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p grading-service --test integration publishing_a_report_card_emits_scores -- --test-threads=4`
Expected: FAIL — no row, because the event is still named `report_card.approved`.

- [ ] **Step 3: Write the failing test proving the scores are FROZEN**

This is the test that matters most: it proves the payload reads the frozen table, not the mutable one.

```rust
#[tokio::test]
async fn published_scores_do_not_follow_later_grade_edits() {
    let app = boot().await;
    let ctx = seed_published_ready_card(&app).await;

    // Teacher edits the still-mutable working score AFTER the card was generated.
    sqlx::query("UPDATE subject_report_score SET score = 10.0 WHERE student_id = $1")
        .bind(ctx.student_id)
        .execute(&app.pool)
        .await
        .unwrap();

    publish_report_card(&app, &ctx).await;

    let payload: serde_json::Value = sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'report_card.published' LIMIT 1",
    )
    .fetch_one(&app.pool)
    .await
    .unwrap();

    let scores = payload["scores"].as_array().unwrap();
    let first = scores.iter().find(|s| s["subject_id"] == json!(ctx.subject_a)).unwrap();
    assert_eq!(
        first["final_score"].as_f64().unwrap(),
        82.5,
        "payload must come from the frozen report_subject_score, not subject_report_score"
    );
}
```

- [ ] **Step 4: Run it and confirm it fails**

Run: `cargo test -p grading-service --test integration published_scores_do_not_follow -- --test-threads=4`
Expected: FAIL — no event row yet.

- [ ] **Step 5: Add the frozen-score repo read**

In `src/repo.rs`:

```rust
/// Frozen per-subject scores for one card. Reads `report_subject_score`
/// (computed once at generation), NOT `subject_report_score` (mutable).
pub async fn frozen_scores(
    &self,
    report_card_id: Uuid,
) -> Result<Vec<(Uuid, f64)>, sqlx::Error> {
    sqlx::query_as::<_, (Uuid, f64)>(
        "SELECT subject_id, final_score FROM report_subject_score \
         WHERE report_card_id = $1 ORDER BY subject_id",
    )
    .bind(report_card_id)
    .fetch_all(&self.0)
    .await
}
```

- [ ] **Step 6: Rename and enrich the emitted event**

Replace the block at `src/commands.rs:1574-1590`:

```rust
if next == ReportCardStatus::Published {
    let scores = state
        .grades
        .frozen_scores(card.report_card_id)
        .await
        .map_err(AppError::internal)?;
    let scores: Vec<serde_json::Value> = scores
        .into_iter()
        .map(|(subject_id, final_score)| json!({
            "subject_id": subject_id,
            "final_score": final_score,
        }))
        .collect();

    let promotion_source = state
        .grades
        .find_promotion_source(input.tenant_id, card.academic_year_id)
        .await
        .map_err(AppError::internal)?;
    let is_promotion_source = promotion_source
        .map(|t| t.report_type_id == card.report_type_id)
        .unwrap_or(false);

    state
        .outbox
        .insert_event(
            Uuid::new_v4(),
            "report_card.published",
            &json!({
                "tenant_id": input.tenant_id,
                "student_id": card.student_id,
                "academic_year_id": card.academic_year_id,
                "report_card_id": card.report_card_id,
                "report_type_id": card.report_type_id,
                "is_promotion_source": is_promotion_source,
                "scores": scores,
            }),
            Utc::now(),
        )
        .await
        .map_err(AppError::internal)?;
}
```

Scores are carried for EVERY published card, not only the promotion source — the flag can be moved after a card is published, and a card that never sent its scores would leave an unfillable hole. See spec §4.2.

- [ ] **Step 7: Update the stale assertion on the old name**

In `tests/integration.rs:1257,1262`, change `'report_card.approved'` to `'report_card.published'` in both the SQL and the assertion.

- [ ] **Step 8: Run both new tests and confirm they pass**

Run: `cargo test -p grading-service --test integration -- --test-threads=4 publishing_a_report_card_emits_scores published_scores_do_not_follow`
Expected: PASS (2 tests).

- [ ] **Step 9: Run the whole grading suite**

Run: `cargo test -p grading-service --test integration -- --test-threads=4`
Expected: all pass. If anything else asserted on the old event name, fix it now.

- [ ] **Step 10: Commit**

```bash
cd apps/backend
git add services/grading-service/src/repo.rs services/grading-service/src/commands.rs \
        services/grading-service/tests/integration.rs
git commit -m "feat(grading): publish report card scores on the outbox"
```

---

### Task 3: Status CHECK constraints in both services

**Files:**
- Create: `apps/backend/services/grading-service/migrations/V13__enrolled_student_promoted.sql`
- Create: `apps/backend/services/academic-ops-service/migrations/V12__promotion_status_values.sql`
- Test: both `tests/integration.rs`

**Context — read this before writing either file.** `enrolled_student` in grading-service is a PROJECTION of `enrollment` in academic-ops. If `'promoted'` is added to the producer but not to the projection, the grading consumer rejects the event and the projection drifts with NO visible error. This exact failure already happened once (`.ai/plans/20`: the grading consumer was dead for 8 days before anyone noticed). Both migrations ship in ONE task for that reason.

- [ ] **Step 1: Write the failing test in academic-ops**

```rust
#[tokio::test]
async fn enrollment_accepts_promoted_and_student_accepts_graduation_states() {
    let app = boot().await;
    let (tenant_id, year_id) = seed_year(&app).await;
    let student_id = seed_student(&app, tenant_id).await;
    let enrollment_id = seed_enrollment(&app, tenant_id, year_id, student_id).await;

    sqlx::query("UPDATE enrollment SET status = 'promoted' WHERE enrollment_id = $1")
        .bind(enrollment_id)
        .execute(&app.pool)
        .await
        .expect("enrollment must accept 'promoted'");

    for status in ["lulus", "alumni"] {
        sqlx::query("UPDATE student SET status = $1 WHERE student_id = $2")
            .bind(status)
            .bind(student_id)
            .execute(&app.pool)
            .await
            .unwrap_or_else(|e| panic!("student must accept '{status}': {e}"));
    }
}
```

- [ ] **Step 2: Write the failing test in grading**

```rust
#[tokio::test]
async fn enrolled_student_projection_accepts_promoted() {
    let app = boot().await;
    let (tenant_id, year_id) = seed_year(&app).await;
    let student_id = seed_enrolled_student(&app, tenant_id, year_id).await;

    sqlx::query("UPDATE enrolled_student SET status = 'promoted' WHERE student_id = $1")
        .bind(student_id)
        .execute(&app.pool)
        .await
        .expect("the projection must accept 'promoted' or it will silently reject events");
}
```

- [ ] **Step 3: Run both and confirm they fail**

Run: `cargo test -p academic-ops-service --test integration enrollment_accepts_promoted -- --test-threads=4`
Run: `cargo test -p grading-service --test integration enrolled_student_projection_accepts_promoted -- --test-threads=4`
Expected: both FAIL with a CHECK constraint violation (SQLSTATE 23514).

- [ ] **Step 4: Write the academic-ops migration**

Create `academic-ops-service/migrations/V12__promotion_status_values.sql`:

```sql
-- Promotion introduces one enrollment state and two student states.
-- 'lulus' and 'alumni' are deliberately DISTINCT: execution sets 'lulus';
-- 'alumni' follows only once the academic year is Closed.
ALTER TABLE enrollment
  DROP CONSTRAINT IF EXISTS enrollment_status_chk;
ALTER TABLE enrollment
  ADD CONSTRAINT enrollment_status_chk CHECK
    (status IN ('active', 'transferred', 'unenrolled', 'promoted'));

ALTER TABLE student
  DROP CONSTRAINT IF EXISTS student_status_chk;
ALTER TABLE student
  ADD CONSTRAINT student_status_chk CHECK
    (status IN ('aktif', 'nonaktif', 'arsip', 'lulus', 'alumni'));
```

Then `touch services/academic-ops-service/src/lib.rs`.

- [ ] **Step 5: Write the grading migration**

Create `grading-service/migrations/V13__enrolled_student_promoted.sql`:

```sql
-- Mirrors the 'promoted' enrollment state added in academic-ops V12.
-- MUST ship together: enrolled_student is a projection of enrollment, and a
-- lagging CHECK makes the consumer reject events with no visible error.
ALTER TABLE enrolled_student
  DROP CONSTRAINT IF EXISTS enrolled_student_status_chk;
ALTER TABLE enrolled_student
  ADD CONSTRAINT enrolled_student_status_chk CHECK
    (status IN ('active', 'transferred', 'unenrolled', 'promoted'));
```

Then `touch services/grading-service/src/lib.rs`.

- [ ] **Step 6: Run both tests and confirm they pass**

Run: `cargo test -p academic-ops-service --test integration enrollment_accepts_promoted -- --test-threads=4`
Run: `cargo test -p grading-service --test integration enrolled_student_projection_accepts_promoted -- --test-threads=4`
Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
cd apps/backend
git add services/academic-ops-service/migrations/V12__promotion_status_values.sql \
        services/grading-service/migrations/V13__enrolled_student_promoted.sql \
        services/academic-ops-service/tests/integration.rs \
        services/grading-service/tests/integration.rs
git commit -m "feat(promotion): allow promoted enrollment and graduation student states"
```

---

### Task 4: Projection tables in `academic-ops-service`

**Files:**
- Create: `apps/backend/services/academic-ops-service/migrations/V13__known_report_score.sql`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn known_projection_tables_exist_with_expected_keys() {
    let app = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = Uuid::new_v4();
    let student_id = Uuid::new_v4();
    let subject_id = Uuid::new_v4();
    let type_a = Uuid::new_v4();
    let type_b = Uuid::new_v4();

    let insert = "INSERT INTO known_report_score \
        (tenant_id, academic_year_id, student_id, subject_id, report_type_id, final_score, is_promotion_source) \
        VALUES ($1,$2,$3,$4,$5,$6,$7)";

    sqlx::query(insert).bind(tenant_id).bind(year_id).bind(student_id)
        .bind(subject_id).bind(type_a).bind(80.0).bind(true)
        .execute(&app.pool).await.unwrap();

    // Same student and subject, DIFFERENT report type: must coexist.
    sqlx::query(insert).bind(tenant_id).bind(year_id).bind(student_id)
        .bind(subject_id).bind(type_b).bind(70.0).bind(false)
        .execute(&app.pool).await
        .expect("scores from different report types must coexist");

    sqlx::query(
        "INSERT INTO known_grading_policy (tenant_id, academic_year_id, minimum_passing_score) \
         VALUES ($1,$2,$3)",
    )
    .bind(tenant_id).bind(year_id).bind(75.0)
    .execute(&app.pool).await.unwrap();
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cargo test -p academic-ops-service --test integration known_projection_tables_exist -- --test-threads=4`
Expected: FAIL — `relation "known_report_score" does not exist`.

- [ ] **Step 3: Write the migration**

Create `academic-ops-service/migrations/V13__known_report_score.sql`:

```sql
-- Local projections feeding the promotion engine. CONVENTIONS.md forbids
-- cross-service HTTP, so both facts arrive as events and land here.

-- The PK includes report_type_id so scores from several report cards coexist:
-- a school may move the promotion-source flag after a card is published.
CREATE TABLE IF NOT EXISTS known_report_score (
  tenant_id           UUID NOT NULL,
  academic_year_id    UUID NOT NULL,
  student_id          UUID NOT NULL,
  subject_id          UUID NOT NULL,
  report_type_id      UUID NOT NULL,
  final_score         DOUBLE PRECISION NOT NULL,
  -- Snapshot of the flag AT PUBLISH TIME. Not the source of truth at
  -- evaluation time: the school can move the flag afterwards. Kept for audit.
  is_promotion_source BOOLEAN NOT NULL,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, report_type_id, student_id, subject_id)
);

CREATE INDEX IF NOT EXISTS known_report_score_year_student_idx
  ON known_report_score (tenant_id, academic_year_id, student_id);

-- DOUBLE PRECISION matches the producer (academic-config V1:64) and the
-- existing grading projection (grading V3:6). Do not use NUMERIC.
CREATE TABLE IF NOT EXISTS known_grading_policy (
  tenant_id             UUID NOT NULL,
  academic_year_id      UUID NOT NULL,
  minimum_passing_score DOUBLE PRECISION NOT NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, academic_year_id)
);
```

Then `touch services/academic-ops-service/src/lib.rs`.

- [ ] **Step 4: Run it and confirm it passes**

Run: `cargo test -p academic-ops-service --test integration known_projection_tables_exist -- --test-threads=4`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd apps/backend
git add services/academic-ops-service/migrations/V13__known_report_score.sql \
        services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): add promotion source projections"
```

---

### Task 5: Consume the events into the projections

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/repo.rs`, `src/events.rs`, `src/state.rs`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: event `report_card.published` (Task 2); tables from Task 4.
- Produces: `KnownReportScoreRepo::replace_for_card(...)`, `KnownGradingPolicyRepo::upsert(...)`.

- [ ] **Step 1: Write the failing idempotency + delete-then-upsert tests**

**Testing note — read before writing any test in this task.** `ProjectionConsumer::handle_event` is PRIVATE (`events.rs:63`); only `run()` is public, and it consumes from RabbitMQ. Tests therefore cannot call `handle_event` directly. The existing consumer test (`tests/integration.rs:738`) works by calling the REPO methods directly and asserting on the table — do the same here. `boot()` returns a 5-tuple `(pool, state, rabbitmq_url, _pg, _rabbit)`; the repos are reached via `state.known_report_scores` / `state.known_grading_policies`.

Write the repo-level tests in this style:

```rust
#[tokio::test]
async fn report_card_published_projects_every_score() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let student_id = uuid::Uuid::new_v4();
    let type_id = uuid::Uuid::new_v4();
    let subject_a = uuid::Uuid::new_v4();
    let subject_b = uuid::Uuid::new_v4();

    state
        .known_report_scores
        .replace_for_card(
            tenant_id, year_id, student_id, type_id, true,
            &[(subject_a, 82.5), (subject_b, 65.0)],
        )
        .await
        .unwrap();

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_report_score WHERE tenant_id=$1 AND student_id=$2",
    )
    .bind(tenant_id).bind(student_id)
    .fetch_one(&pool).await.unwrap();

    assert_eq!(count, 2);
}

#[tokio::test]
async fn redelivering_the_same_event_is_idempotent() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let student_id = uuid::Uuid::new_v4();
    let type_id = uuid::Uuid::new_v4();
    let subject_a = uuid::Uuid::new_v4();
    let scores = [(subject_a, 82.5)];

    state.known_report_scores
        .replace_for_card(tenant_id, year_id, student_id, type_id, true, &scores)
        .await.unwrap();
    state.known_report_scores
        .replace_for_card(tenant_id, year_id, student_id, type_id, true, &scores)
        .await.unwrap();

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_report_score WHERE tenant_id=$1 AND student_id=$2",
    )
    .bind(tenant_id).bind(student_id)
    .fetch_one(&pool).await.unwrap();

    assert_eq!(count, 1, "redelivery must not duplicate rows");
}

#[tokio::test]
async fn regenerating_with_fewer_subjects_removes_the_dropped_one() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let student_id = uuid::Uuid::new_v4();
    let type_id = uuid::Uuid::new_v4();
    let subject_a = uuid::Uuid::new_v4();
    let subject_b = uuid::Uuid::new_v4();

    state.known_report_scores
        .replace_for_card(tenant_id, year_id, student_id, type_id, true,
            &[(subject_a, 82.5), (subject_b, 65.0)])
        .await.unwrap();

    // Card regenerated with subject_b removed.
    state.known_report_scores
        .replace_for_card(tenant_id, year_id, student_id, type_id, true,
            &[(subject_a, 82.5)])
        .await.unwrap();

    let remaining: Vec<uuid::Uuid> = sqlx::query_scalar(
        "SELECT subject_id FROM known_report_score WHERE tenant_id=$1 AND student_id=$2",
    )
    .bind(tenant_id).bind(student_id)
    .fetch_all(&pool).await.unwrap();

    assert_eq!(remaining, vec![subject_a],
        "a dropped subject must not linger and drag the average");
}

#[tokio::test]
async fn scores_are_projected_even_when_not_the_promotion_source() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let student_id = uuid::Uuid::new_v4();
    let type_id = uuid::Uuid::new_v4();

    state.known_report_scores
        .replace_for_card(tenant_id, year_id, student_id, type_id, false,
            &[(uuid::Uuid::new_v4(), 82.5)])
        .await.unwrap();

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_report_score WHERE tenant_id=$1 AND student_id=$2",
    )
    .bind(tenant_id).bind(student_id)
    .fetch_one(&pool).await.unwrap();

    assert_eq!(count, 1, "every published card projects its scores; the flag can move later");
}

#[tokio::test]
async fn grading_policy_projection_stores_the_passing_score() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();

    state.known_grading_policies.upsert(tenant_id, year_id, 75.0).await.unwrap();
    state.known_grading_policies.upsert(tenant_id, year_id, 70.0).await.unwrap();

    let score: f64 = sqlx::query_scalar(
        "SELECT minimum_passing_score FROM known_grading_policy WHERE tenant_id=$1 AND academic_year_id=$2",
    )
    .bind(tenant_id).bind(year_id)
    .fetch_one(&pool).await.unwrap();

    assert_eq!(score, 70.0, "a later policy event must overwrite the earlier one");
}

#[tokio::test]
async fn projections_are_scoped_per_tenant() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_a = uuid::Uuid::new_v4();
    let tenant_b = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    let student_id = uuid::Uuid::new_v4();

    state.known_report_scores
        .replace_for_card(tenant_a, year_id, student_id, uuid::Uuid::new_v4(), true,
            &[(uuid::Uuid::new_v4(), 82.5)])
        .await.unwrap();

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_report_score WHERE tenant_id = $1",
    )
    .bind(tenant_b)
    .fetch_one(&pool).await.unwrap();

    assert_eq!(count, 0, "one tenant's scores must never appear under another");
}
```

Additionally, add ONE test that proves the match arm itself is wired (the repo tests above bypass it). Follow the existing consumer test at `tests/integration.rs:738`: build a `ProjectionConsumer`, spawn `run()`, publish a `report_card.published` envelope to the exchange the consumer binds, poll the table until the row appears or a short timeout elapses, then `handle.abort()`. If the existing test harness offers no way to publish an envelope, state that in your report and skip only this one test — do NOT make `handle_event` public to work around it.

- [ ] **Step 2: Run them and confirm they fail**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4 known_report_score report_card_published redelivering regenerating grading_policy_configured projections_are_scoped`
Expected: FAIL — the event types are unhandled, so nothing is written.

- [ ] **Step 3: Add the repos**

In `src/repo.rs`, following the `KnownAcademicTermRepo` pattern at `repo.rs:804`:

```rust
#[derive(Clone, Debug)]
pub struct KnownReportScoreRepo(PgPool);

impl KnownReportScoreRepo {
    pub fn new(pool: PgPool) -> Self {
        Self(pool)
    }

    /// Replaces the scores for one card in a single transaction: delete the
    /// subjects that are no longer present, then upsert the ones that are.
    /// A plain upsert would leave orphan rows when a card is regenerated with
    /// fewer subjects, and those stale rows would drag the average.
    pub async fn replace_for_card(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
        student_id: Uuid,
        report_type_id: Uuid,
        is_promotion_source: bool,
        scores: &[(Uuid, f64)],
    ) -> Result<(), sqlx::Error> {
        let subject_ids: Vec<Uuid> = scores.iter().map(|(id, _)| *id).collect();
        let mut tx = self.0.begin().await?;

        sqlx::query(
            "DELETE FROM known_report_score \
             WHERE tenant_id = $1 AND report_type_id = $2 AND student_id = $3 \
               AND NOT (subject_id = ANY($4))",
        )
        .bind(tenant_id)
        .bind(report_type_id)
        .bind(student_id)
        .bind(&subject_ids)
        .execute(&mut *tx)
        .await?;

        for (subject_id, final_score) in scores {
            sqlx::query(
                "INSERT INTO known_report_score \
                 (tenant_id, academic_year_id, student_id, subject_id, report_type_id, final_score, is_promotion_source) \
                 VALUES ($1,$2,$3,$4,$5,$6,$7) \
                 ON CONFLICT (tenant_id, report_type_id, student_id, subject_id) DO UPDATE SET \
                   final_score = EXCLUDED.final_score, \
                   is_promotion_source = EXCLUDED.is_promotion_source, \
                   academic_year_id = EXCLUDED.academic_year_id, \
                   updated_at = NOW()",
            )
            .bind(tenant_id)
            .bind(academic_year_id)
            .bind(student_id)
            .bind(subject_id)
            .bind(report_type_id)
            .bind(final_score)
            .bind(is_promotion_source)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await
    }
}

#[derive(Clone, Debug)]
pub struct KnownGradingPolicyRepo(PgPool);

impl KnownGradingPolicyRepo {
    pub fn new(pool: PgPool) -> Self {
        Self(pool)
    }

    pub async fn upsert(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
        minimum_passing_score: f64,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO known_grading_policy (tenant_id, academic_year_id, minimum_passing_score) \
             VALUES ($1,$2,$3) \
             ON CONFLICT (tenant_id, academic_year_id) DO UPDATE SET \
               minimum_passing_score = EXCLUDED.minimum_passing_score, updated_at = NOW()",
        )
        .bind(tenant_id)
        .bind(academic_year_id)
        .bind(minimum_passing_score)
        .execute(&self.0)
        .await?;
        Ok(())
    }
}
```

- [ ] **Step 4: Wire them into `AppState` AND `ProjectionConsumer`**

Both. The repos are FIELDS ON `AppState` (that is how tests reach them), and `ProjectionConsumer::new` receives clones of them as positional arguments.

First, in `src/state.rs`, add two fields alongside the existing `known_years`, `known_terms`, `known_tenant_users`, `subscriptions`, and construct them from the pool:

```rust
pub known_report_scores: KnownReportScoreRepo,
pub known_grading_policies: KnownGradingPolicyRepo,
```

Then in `src/events.rs`, add matching fields to `ProjectionConsumer` (declared at `events.rs:28`) and two matching parameters to `ProjectionConsumer::new`, following the existing four exactly.

Finally, update every `ProjectionConsumer::new(...)` call site the compiler flags — including `tests/integration.rs:744`, which passes the repos positionally and will not compile until it passes the two new ones.

- [ ] **Step 5: Add the payload types and the match arms**

In `src/events.rs`, add the payload structs:

```rust
#[derive(Debug, serde::Deserialize)]
struct ReportCardPublishedScore {
    subject_id: Uuid,
    final_score: f64,
}

#[derive(Debug, serde::Deserialize)]
struct ReportCardPublishedPayload {
    tenant_id: Uuid,
    student_id: Uuid,
    academic_year_id: Uuid,
    report_type_id: Uuid,
    #[serde(default)]
    is_promotion_source: bool,
    #[serde(default)]
    scores: Vec<ReportCardPublishedScore>,
}

#[derive(Debug, serde::Deserialize)]
struct GradingPolicyConfiguredPayload {
    tenant_id: Uuid,
    academic_year_id: Uuid,
    minimum_passing_score: f64,
}
```

Then add the arms alongside the existing ones (the match starts at `events.rs:65`):

```rust
"report_card.published" => {
    let payload: ReportCardPublishedPayload = serde_json::from_value(envelope.payload)?;
    let scores: Vec<(Uuid, f64)> = payload
        .scores
        .iter()
        .map(|s| (s.subject_id, s.final_score))
        .collect();
    self.known_report_scores
        .replace_for_card(
            payload.tenant_id,
            payload.academic_year_id,
            payload.student_id,
            payload.report_type_id,
            payload.is_promotion_source,
            &scores,
        )
        .await?;
}
"grading_policy.configured" => {
    let payload: GradingPolicyConfiguredPayload = serde_json::from_value(envelope.payload)?;
    self.known_grading_policies
        .upsert(
            payload.tenant_id,
            payload.academic_year_id,
            payload.minimum_passing_score,
        )
        .await?;
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4 known_report_score report_card_published redelivering regenerating grading_policy_configured projections_are_scoped`
Expected: PASS (6 tests).

- [ ] **Step 7: Run the whole academic-ops suite**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4`
Expected: no new failures.

- [ ] **Step 8: Commit**

```bash
cd apps/backend
git add services/academic-ops-service/src/repo.rs services/academic-ops-service/src/events.rs \
        services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): project report card scores and grading policy"
```

---

### Task 6: Guard rails the promotion engine will depend on

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/queries.rs`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: `promotion_score_readiness(tenant_id, academic_year_id, report_type_id) -> Result<ScoreReadiness, sqlx::Error>` where `ScoreReadiness { students_with_scores: i64, students_without_scores: Vec<Uuid> }`.

**Context:** Plan 3 builds the evaluation engine. These two queries exist so that it CANNOT silently compute a wrong answer. They are written here, with the projection, because they are properties of the projection rather than of the engine.

- [ ] **Step 1: Write the failing tests**

```rust
#[tokio::test]
async fn students_without_any_score_are_reported_not_treated_as_zero() {
    let app = boot().await;
    let ctx = fixture_ids();
    let scored = ctx.student_id;
    let unscored = Uuid::new_v4();

    handle_event(&app, "report_card.published",
        &published_payload(&ctx, &[(ctx.subject_a, 82.5)])).await;
    seed_active_enrollment(&app, ctx.tenant_id, ctx.year_id, unscored).await;

    let readiness = promotion_score_readiness(&app, ctx.tenant_id, ctx.year_id, ctx.report_type_id)
        .await
        .unwrap();

    assert_eq!(readiness.students_with_scores, 1);
    assert_eq!(
        readiness.students_without_scores, vec![unscored],
        "a student with no scores must be named, never silently scored 0"
    );
    assert!(!readiness.students_without_scores.contains(&scored));
}

#[tokio::test]
async fn ambiguous_promotion_source_is_detectable_by_the_consumer() {
    let app = boot().await;
    let ctx = fixture_ids();
    let other_type = Uuid::new_v4();

    let mut first = published_payload(&ctx, &[(ctx.subject_a, 82.5)]);
    first["is_promotion_source"] = json!(true);
    handle_event(&app, "report_card.published", &first).await;

    let mut second = published_payload(&ctx, &[(ctx.subject_a, 70.0)]);
    second["report_type_id"] = json!(other_type);
    second["is_promotion_source"] = json!(true);
    handle_event(&app, "report_card.published", &second).await;

    let flagged: i64 = sqlx::query_scalar(
        "SELECT count(DISTINCT report_type_id) FROM known_report_score \
         WHERE tenant_id = $1 AND academic_year_id = $2 AND is_promotion_source",
    )
    .bind(ctx.tenant_id).bind(ctx.year_id)
    .fetch_one(&app.pool).await.unwrap();

    assert_eq!(flagged, 2,
        "the consumer must be able to SEE ambiguity rather than trust the producer");
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4 students_without_any_score ambiguous_promotion_source`
Expected: FAIL — `promotion_score_readiness` does not exist.

- [ ] **Step 3: Implement the readiness query**

In `src/queries.rs`. Note the signature takes `state: &AppState` and returns `AppError`, matching every neighbouring query in this file (`dashboard_stats`, `list_students`, ...) — not a bare `&PgPool`:

```rust
pub struct ScoreReadiness {
    pub students_with_scores: i64,
    pub students_without_scores: Vec<Uuid>,
}

/// Which actively-enrolled students have no projected scores for the given
/// report type. Plan 3's evaluation MUST refuse to run when this list is
/// non-empty: a missing score is not a zero, and a zero means held back.
pub async fn promotion_score_readiness(
    state: &AppState,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    report_type_id: Uuid,
) -> Result<ScoreReadiness, AppError> {
    let students_without_scores: Vec<Uuid> = sqlx::query_scalar(
        "SELECT e.student_id FROM enrollment e \
         WHERE e.tenant_id = $1 AND e.academic_year_id = $2 AND e.status = 'active' \
           AND NOT EXISTS ( \
             SELECT 1 FROM known_report_score k \
             WHERE k.tenant_id = e.tenant_id AND k.student_id = e.student_id \
               AND k.report_type_id = $3 \
           ) \
         ORDER BY e.student_id",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .bind(report_type_id)
    .fetch_all(&state.pool)
    .await
    .map_err(AppError::internal)?;

    let students_with_scores: i64 = sqlx::query_scalar(
        "SELECT count(DISTINCT student_id) FROM known_report_score \
         WHERE tenant_id = $1 AND academic_year_id = $2 AND report_type_id = $3",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .bind(report_type_id)
    .fetch_one(&state.pool)
    .await
    .map_err(AppError::internal)?;

    Ok(ScoreReadiness { students_with_scores, students_without_scores })
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4 students_without_any_score ambiguous_promotion_source`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd apps/backend
git add services/academic-ops-service/src/queries.rs services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): report students missing promotion scores"
```

---

### Task 7: Documentation

**Files:**
- Create: `docs/internal/11_integration_contracts/events/report-card-published.md`
- Delete: `docs/internal/11_integration_contracts/events/report-card-approved.md`
- Modify: `docs/internal/10_data_design/` — the grading ERD and the academic-ops ERD

**Context:** Work in the PARENT repo (`/home/fitrah/projects/akademiq`), NOT a submodule. `apps/backend` will show as modified; do NOT stage it. Verify every claim against the shipped code — the plan text may have drifted during implementation, and documentation that contradicts the code is worse than none.

- [ ] **Step 1: Write the new event contract**

Create `report-card-published.md`, matching the style of the sibling contracts:

```markdown
# Event: ReportCardPublished

**Produced By:** Grading Service
**Consumed By:** Academic Ops Service (promotion projections)

## When It Is Emitted
When a report card transitions to `Published` — that is, on principal approval
of the final step. Emitted for EVERY published card, whether or not its report
type is the promotion source.

## Payload Schema (v1)
```json
{
  "event_id": "uuid",
  "occurred_at": "datetime",
  "tenant_id": "uuid",
  "student_id": "uuid",
  "academic_year_id": "uuid",
  "report_card_id": "uuid",
  "report_type_id": "uuid",
  "is_promotion_source": true,
  "scores": [
    { "subject_id": "uuid", "final_score": 82.5 }
  ]
}
```

## Notes
`scores` come from `report_subject_score` — the values frozen when the card was
generated — not from the mutable `subject_report_score`. Editing grades after a
card is published does not change what was projected.

`is_promotion_source` is a SNAPSHOT at publish time. A school may move the flag
to a different report type afterwards, so consumers must resolve the currently
flagged report type rather than trusting this field at evaluation time.

Replaces the former `report_card.approved`, which was misnamed: it already fired
on the transition to `Published`. That name had no consumers, so it was renamed
in place rather than versioned.
```

- [ ] **Step 2: Delete the superseded contract**

```bash
git rm docs/internal/11_integration_contracts/events/report-card-approved.md
```

- [ ] **Step 3: Update the ERDs**

In the grading ERD, add `is_promotion_source BOOLEAN` to the `report_type` entity. In the academic-ops ERD, add the `known_report_score` and `known_grading_policy` entities with the columns actually shipped in V13. Use Mermaid in fenced ```mermaid blocks, matching the surrounding file — never PlantUML or images.

- [ ] **Step 4: Verify the docs against the shipped code**

Re-read `grading-service/migrations/V12`, `academic-ops-service/migrations/V13`, and the payload built in `grading-service/src/commands.rs`. Confirm every column name, type and field name in the docs matches. Fix the docs where they differ — the code wins.

- [ ] **Step 5: Confirm only docs are staged, then commit**

```bash
cd /home/fitrah/projects/akademiq
git status   # apps/backend will show as modified — do NOT stage it
git add docs/internal/
git commit -m "docs(contracts): document the report card published event"
```

---

### Task 8: Full verification

- [ ] **Step 1: Run the grading suite**

Run: `cd apps/backend && cargo test -p grading-service --test integration -- --test-threads=4`
Expected: all pass.

- [ ] **Step 2: Run the academic-ops suite**

Run: `cargo test -p academic-ops-service --test integration -- --test-threads=4`
Expected: all pass.

- [ ] **Step 3: Run the workspace unit tests**

Run: `cargo test --workspace --lib 2>&1 | grep -E "^test result|^error"`
Expected: every crate green. Do NOT pipe through `tail` — it hides all but the last crate's result.

- [ ] **Step 4: Verify the migrations against the real dev database**

```bash
cd apps/backend
docker compose exec -T postgres psql -U akademiq -d akademiq \
  -c "SELECT version FROM grading.refinery_schema_history ORDER BY version DESC LIMIT 2;" \
  -c "SELECT version FROM academic_ops.refinery_schema_history ORDER BY version DESC LIMIT 2;"
```

Confirm the new versions applied cleanly, or that the service will apply them on next boot.

- [ ] **Step 5: Confirm no stale references to the old event name**

```bash
cd apps/backend
grep -rn "report_card.approved" --include=*.rs services/ libs/
```

Expected: no output.

---

## Self-Review Notes

Checked against the spec:

- §2.1/§2.2 rename + no versioning → Task 2.
- §3.2/§3.3 flag, command-layer rule, consumer safety belt → Tasks 1 and 6.
- §4.1/§4.2 payload shape, scores always carried → Task 2, plus the `scores_are_projected_even_when_not_the_promotion_source` test in Task 5.
- §5.1 tables and the `DOUBLE PRECISION` correction → Task 4.
- §5.2 snapshot-not-truth → Task 4 (column comment) and Task 6 (ambiguity test).
- §5.3 idempotency and delete-then-upsert → Task 5.
- §6 constraint changes across two services in one task → Task 3.
- §7 missing-data recovery → Task 6 readiness query.
- §10 required tests → distributed across Tasks 1, 2, 5, 6.

Deliberately NOT in this plan (spec §8): the evaluation engine, the `report_type`
projection into academic-ops, and the UI for the flag — all Plan 3, each needs a
consumer that does not exist yet.
