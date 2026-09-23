# Promotion Foundation (Plan 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `academic-ops` every fact the promotion engine will need — grade levels it can read locally, homerooms linked to them, the promotion tables, and the IAM permissions — without building anything that decides a student's fate.

**Architecture:** `academic-config` starts emitting `grade_level.*` events on its outbox (all four commands become transactional first, so a write and its event can never diverge). `academic-ops` consumes them into a new `known_grade_level` projection, following the consumer pattern Plan 2 established. A nullable `homeroom.grade_level_id` links classes to grade levels, backfilled by matching `code` — and the backfill reports loudly what it cannot match, because the dev database proves the two services' grade vocabularies disagree. Finally the five promotion tables land with their constraints proven, but nothing writes to them until Plan 3b.

**Tech Stack:** Rust, Axum, SQLx 0.8, refinery, PostgreSQL 18, RabbitMQ (lapin), tokio, testcontainers

**Spec:** `docs/superpowers/specs/2026-09-24-promotion-foundation-design.md`

## Global Constraints

- Every migration is idempotent: `IF NOT EXISTS` on tables/columns/indexes, `DROP CONSTRAINT IF EXISTS` before `ADD CONSTRAINT`. Proven by applying twice.
- Score-like numbers are **`DOUBLE PRECISION`**, never `NUMERIC`. Plan 2 established this: producers and every existing projection of the same fact use `DOUBLE PRECISION`, and a type mismatch across projections of one fact produces subtle comparison bugs in the comparison that decides whether a child repeats a year.
- Every promotion table carries `tenant_id`; every index leads with `tenant_id`.
- A domain write and its outbox event share ONE transaction: `begin()` → repo write → `enqueue()` → `commit()`.
- Event payloads carry **full current state**, not deltas.
- Event names follow `domain.action.past`.
- Commit messages contain ONLY the message — no `Co-authored-by:`, no `Signed-off-by:`, no "Generated with", no tool or model identifiers.
- Backend tests run with `--test-threads=4` (real Postgres + RabbitMQ testcontainers). A full suite takes several minutes.
- **Refinery gotcha:** `embed_migrations!` inlines SQL at compile time. After adding a migration you MUST `touch services/<service>/src/lib.rs` or the new migration is invisible to the test binary.
- Known pre-existing failures, not to be fixed here: academic-ops `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url`; academic-config `status_transition_legal_and_illegal_paths`.

## Review Focus

Five things the spec implies but which no obvious task would test, most likely to bite first:

1. **A grade level renamed after homerooms were linked** — the projection updates, but `homeroom.grade_level_id` still points at the right row while `homeroom.grade_level` text goes stale. Task 5's test pins that the link survives a rename and the ID stays authoritative.
2. **`reorder` emitting the temporary parking ordinals** — the two-phase update parks rows at ordinals outside the real range. If the event is emitted mid-transaction or per row, consumers see an impossible ladder. Task 4 pins that exactly one event is emitted, after both phases, carrying only final ordinals.
3. **Deleting a grade level that homerooms still reference** — the projection row vanishes while `homeroom.grade_level_id` still holds the UUID. Task 5 pins that this leaves a legible dangling link rather than a crash, and Task 6's readiness view reports it.
4. **A tenant with zero grade levels at all** — bootstrap and projection both produce nothing, and the engine must later refuse rather than divide by zero. Task 7 pins that the bootstrap handles an empty tenant without error.
5. **Two tenants with identical grade-level codes** — `code` is only unique per `(tenant_id, academic_year_id)`. A backfill matching on `code` alone would cross tenants. Task 5 pins that the backfill is tenant-scoped and never links a homeroom to another tenant's grade level.

---

## Task 1: Make the grade level repo transaction-capable

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/repo.rs:1987-2110`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Produces: `GradeLevelRepo::insert<'e, E: PgExecutor<'e>>(&self, executor: E, level: &GradeLevel)`, `GradeLevelRepo::update<'e, E: PgExecutor<'e>>(&self, executor: E, ...)`, `GradeLevelRepo::delete<'e, E: PgExecutor<'e>>(&self, executor: E, tenant_id: Uuid, id: Uuid) -> sqlx::Result<u64>`

**Context:** `GradeLevelRepo` currently hardcodes `.execute(&self.pool)` on its write methods, so a caller cannot enrol them in a transaction. `GradingPolicyRepo::upsert` at `repo.rs:1438` already takes an executor — that is the house pattern and the shape to copy. This task only changes plumbing; behaviour is identical.

- [ ] **Step 1: Read the two patterns side by side**

Read `GradingPolicyRepo::upsert` (`repo.rs:1438-1470`) and `GradeLevelRepo::insert` (`repo.rs:1992-2012`). The only difference that matters is the executor parameter.

- [ ] **Step 2: Change the three write methods to take an executor**

```rust
pub async fn insert<'e, E: PgExecutor<'e>>(
    &self,
    executor: E,
    level: &GradeLevel,
) -> sqlx::Result<()> {
    sqlx::query(
        r#"
        INSERT INTO grade_level
          (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(level.grade_level_id)
    .bind(level.tenant_id)
    .bind(level.academic_year_id)
    .bind(&level.code)
    .bind(&level.label)
    .bind(level.ordinal)
    .bind(level.is_final)
    .bind(level.created_at)
    .bind(level.updated_at)
    .execute(executor)
    .await?;
    Ok(())
}
```

Apply the same change to `update` and `delete`: add `executor: E` as the first parameter after `&self`, and swap `.execute(&self.pool)` for `.execute(executor)`. Leave the read methods (`list_for_year`, `find_by_id`, `find_final`, `count_templates_using`) exactly as they are — they have no reason to join a transaction.

- [ ] **Step 3: Fix every call site**

Run `cargo check -p academic-config-service` and let the compiler list them. Each call becomes `.insert(&state.pool, &level)` for now — the transaction comes in Tasks 2-4. Do not change behaviour in this step.

- [ ] **Step 4: Verify the suite is unchanged**

Run: `cargo test -p academic-config-service --test integration -- --test-threads=4`
Expected: same pass/fail counts as before this task. This is a pure refactor; any change in results means something was altered by accident.

- [ ] **Step 5: Commit**

```bash
git add services/academic-config-service/src/repo.rs services/academic-config-service/src/commands.rs
git commit -m "refactor(academic-config): let grade level writes join a transaction"
```

---

## Task 2: Emit `grade_level.created` transactionally

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/commands.rs:621-653`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: `GradeLevelRepo::insert<'e, E: PgExecutor<'e>>` from Task 1
- Produces: outbox event `grade_level.created` with payload `{tenant_id, academic_year_id, grade_level_id, code, label, ordinal, is_final}`

**Context:** The house pattern is at `commands.rs:548-570` (`configure_grading_policy`): `begin()`, repo write on `&mut *tx`, `enqueue()` on `&mut *tx`, `commit()`. Plan 2 fixed this exact class of bug in grading-service — a write and its event on separate connections mean a crash between them leaves a permanent change that never emitted its event.

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn adding_a_grade_level_emits_an_event() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_academic_year(&pool, tenant_id).await;

    let level = commands::add_grade_level(
        &state,
        commands::AddGradeLevel {
            tenant_id,
            academic_year_id: year_id,
            code: "X".into(),
            label: "Kelas X".into(),
            ordinal: 1,
            is_final: false,
        },
    )
    .await
    .expect("add_grade_level should succeed");

    let payload: serde_json::Value = sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'grade_level.created'",
    )
    .fetch_one(&pool)
    .await
    .expect("one grade_level.created event should exist");

    assert_eq!(payload["grade_level_id"], json!(level.grade_level_id));
    assert_eq!(payload["code"], json!("X"));
    assert_eq!(payload["ordinal"], json!(1));
    assert_eq!(payload["is_final"], json!(false));
    assert_eq!(payload["academic_year_id"], json!(year_id));
    assert_eq!(payload["tenant_id"], json!(tenant_id));
}
```

Check the existing test file for the real name of `boot()` before writing this. **There is no `seed_academic_year` helper** — academic-config tests insert the year directly, e.g. `sqlx::query(r#"INSERT INTO academic_year (academic_year_id, tenant_id, name, start_date, end_date, status, created_at, updated_at) VALUES ($1, $2, '2026/2027', '2026-07-01', '2027-06-30', 'Draft', NOW(), NOW())"#)` — see `tests/integration.rs:2122`. Follow that style; do not invent a helper.

- [ ] **Step 2: Run it and watch it fail**

Run: `cargo test -p academic-config-service --test integration adding_a_grade_level_emits_an_event -- --test-threads=4`
Expected: FAIL — no row found, because no event is emitted yet.

- [ ] **Step 3: Wrap the command in a transaction and emit**

```rust
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    state
        .grade_level_repo
        .insert(&mut *tx, &level)
        .await
        .map_err(map_grade_level_conflict)?;
    state
        .outbox_repo
        .enqueue(
            &mut *tx,
            Uuid::new_v4(),
            "grade_level.created",
            &json!({
                "tenant_id": level.tenant_id,
                "academic_year_id": level.academic_year_id,
                "grade_level_id": level.grade_level_id,
                "code": level.code,
                "label": level.label,
                "ordinal": level.ordinal,
                "is_final": level.is_final,
            }),
        )
        .await
        .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(level)
```

- [ ] **Step 4: Run it and watch it pass**

Run: `cargo test -p academic-config-service --test integration adding_a_grade_level_emits_an_event -- --test-threads=4`
Expected: PASS

- [ ] **Step 5: Write the atomicity test**

```rust
#[tokio::test]
async fn failed_outbox_enqueue_rolls_back_the_grade_level() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_academic_year(&pool, tenant_id).await;

    sqlx::query(
        "ALTER TABLE outbox ADD CONSTRAINT no_grade_level_created \
         CHECK (event_type <> 'grade_level.created')",
    )
    .execute(&pool)
    .await
    .expect("test constraint should apply");

    let result = commands::add_grade_level(
        &state,
        commands::AddGradeLevel {
            tenant_id,
            academic_year_id: year_id,
            code: "XI".into(),
            label: "Kelas XI".into(),
            ordinal: 2,
            is_final: false,
        },
    )
    .await;

    assert!(result.is_err(), "the command must fail when its event cannot be written");

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM grade_level WHERE tenant_id = $1 AND code = 'XI'",
    )
    .bind(tenant_id)
    .fetch_one(&pool)
    .await
    .expect("count should succeed");

    assert_eq!(count, 0, "the grade level must roll back with its event");
}
```

- [ ] **Step 6: Run both tests**

Run: `cargo test -p academic-config-service --test integration grade_level -- --test-threads=4`
Expected: both PASS. If the atomicity test passes without the transaction, the test is wrong — verify it fails when you temporarily move the `enqueue` after `tx.commit()`.

- [ ] **Step 7: Commit**

```bash
git add services/academic-config-service/src/commands.rs services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): publish grade level creation on the outbox"
```

---

## Task 3: Emit `grade_level.updated` and `grade_level.deleted`

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/commands.rs:664-751`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: `GradeLevelRepo::update`, `GradeLevelRepo::delete` from Task 1
- Produces: outbox events `grade_level.updated` (payload identical in shape to `grade_level.created`) and `grade_level.deleted` (payload `{tenant_id, grade_level_id}`)

**Context:** Same transactional pattern as Task 2, applied to the other two commands. `grade_level.updated` carries the **full current state**, not a delta — a projection consumer receiving full state is idempotent by construction and cannot drift when a message is missed. `grade_level.deleted` carries only the identity, because there is no state left to describe.

- [ ] **Step 1: Write the failing tests**

```rust
#[tokio::test]
async fn updating_a_grade_level_emits_full_current_state() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_academic_year(&pool, tenant_id).await;
    let level = commands::add_grade_level(&state, commands::AddGradeLevel {
        tenant_id, academic_year_id: year_id,
        code: "X".into(), label: "Kelas X".into(), ordinal: 1, is_final: false,
    }).await.expect("seed level");

    commands::update_grade_level(&state, commands::UpdateGradeLevel {
        tenant_id,
        grade_level_id: level.grade_level_id,
        code: "XII".into(),
        label: "Kelas XII".into(),
        ordinal: 3,
        is_final: true,
    }).await.expect("update should succeed");

    let payload: serde_json::Value = sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'grade_level.updated'",
    ).fetch_one(&pool).await.expect("one updated event");

    assert_eq!(payload["code"], json!("XII"));
    assert_eq!(payload["label"], json!("Kelas XII"));
    assert_eq!(payload["ordinal"], json!(3));
    assert_eq!(payload["is_final"], json!(true));
    assert_eq!(payload["grade_level_id"], json!(level.grade_level_id));
    assert_eq!(payload["academic_year_id"], json!(year_id),
        "full state includes the year, so a consumer never has to look it up");
}

#[tokio::test]
async fn deleting_a_grade_level_emits_its_identity() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_academic_year(&pool, tenant_id).await;
    let level = commands::add_grade_level(&state, commands::AddGradeLevel {
        tenant_id, academic_year_id: year_id,
        code: "X".into(), label: "Kelas X".into(), ordinal: 1, is_final: false,
    }).await.expect("seed level");

    commands::delete_grade_level(&state, tenant_id, level.grade_level_id)
        .await.expect("delete should succeed");

    let payload: serde_json::Value = sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'grade_level.deleted'",
    ).fetch_one(&pool).await.expect("one deleted event");

    assert_eq!(payload["grade_level_id"], json!(level.grade_level_id));
    assert_eq!(payload["tenant_id"], json!(tenant_id));
}
```

Check the real signature of `delete_grade_level` before writing the second test — it may take a struct rather than positional arguments.

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p academic-config-service --test integration grade_level_emits -- --test-threads=4`
Expected: FAIL on both — no events emitted.

- [ ] **Step 3: Wrap both commands in transactions and emit**

Follow Task 2's Step 3 shape exactly. For `update_grade_level`, build the payload from the **updated** values, not the input struct, so the event matches what is actually stored. For `delete_grade_level`, emit `{tenant_id, grade_level_id}` only.

- [ ] **Step 4: Run them and watch them pass**

Run: `cargo test -p academic-config-service --test integration grade_level -- --test-threads=4`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add services/academic-config-service/src/commands.rs services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): publish grade level updates and deletions"
```

---

## Task 4: Emit one `grade_level.reordered` for the whole ladder

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/commands.rs:752-820`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Produces: outbox event `grade_level.reordered` with payload `{tenant_id, academic_year_id, levels: [{grade_level_id, ordinal}]}`

**Context:** `reorder_grade_levels` already opens a transaction and writes raw SQL directly in `commands.rs`, bypassing the repo. It is **two-phase**: every row is first parked at a temporary ordinal outside the real range to dodge the `(tenant_id, academic_year_id, ordinal)` unique constraint, then moved to its final ordinal. Emitting per row, or emitting between the phases, would broadcast an impossible ladder. Emit exactly one event, after both phases, inside the same transaction.

- [ ] **Step 1: Write the failing test**

```rust
#[tokio::test]
async fn reordering_emits_exactly_one_event_with_final_ordinals() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_academic_year(&pool, tenant_id).await;

    let a = commands::add_grade_level(&state, commands::AddGradeLevel {
        tenant_id, academic_year_id: year_id,
        code: "A".into(), label: "A".into(), ordinal: 1, is_final: false,
    }).await.expect("seed A");
    let b = commands::add_grade_level(&state, commands::AddGradeLevel {
        tenant_id, academic_year_id: year_id,
        code: "B".into(), label: "B".into(), ordinal: 2, is_final: false,
    }).await.expect("seed B");

    commands::reorder_grade_levels(&state, commands::ReorderGradeLevels {
        tenant_id,
        academic_year_id: year_id,
        ordered_ids: vec![b.grade_level_id, a.grade_level_id],
    }).await.expect("reorder should succeed");

    let events: Vec<serde_json::Value> = sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'grade_level.reordered'",
    ).fetch_all(&pool).await.expect("query should succeed");

    assert_eq!(events.len(), 1, "the whole ladder moves in one event, not one per row");

    let levels = events[0]["levels"].as_array().expect("levels array");
    assert_eq!(levels.len(), 2);
    assert_eq!(levels[0]["grade_level_id"], json!(b.grade_level_id));
    assert_eq!(levels[0]["ordinal"], json!(1));
    assert_eq!(levels[1]["grade_level_id"], json!(a.grade_level_id));
    assert_eq!(levels[1]["ordinal"], json!(2));

    for level in levels {
        let ordinal = level["ordinal"].as_i64().expect("ordinal is a number");
        assert!(ordinal >= 1 && ordinal <= 2,
            "the temporary parking ordinals must never reach a consumer, got {ordinal}");
    }
}
```

Check the real name and shape of the reorder input struct before writing this.

- [ ] **Step 2: Run it and watch it fail**

Run: `cargo test -p academic-config-service --test integration reordering_emits -- --test-threads=4`
Expected: FAIL — zero events found.

- [ ] **Step 3: Emit once, after both phases, inside the existing transaction**

Add the `enqueue` call after the second phase's loop completes and before `tx.commit()`. Build `levels` from `input.ordered_ids` with the final ordinal being the 1-based index:

```rust
    let levels: Vec<serde_json::Value> = input
        .ordered_ids
        .iter()
        .enumerate()
        .map(|(idx, id)| json!({ "grade_level_id": id, "ordinal": (idx as i32) + 1 }))
        .collect();
    state
        .outbox_repo
        .enqueue(
            &mut *tx,
            Uuid::new_v4(),
            "grade_level.reordered",
            &json!({
                "tenant_id": input.tenant_id,
                "academic_year_id": input.academic_year_id,
                "levels": levels,
            }),
        )
        .await
        .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
```

- [ ] **Step 4: Run it and watch it pass**

Run: `cargo test -p academic-config-service --test integration reordering_emits -- --test-threads=4`
Expected: PASS

- [ ] **Step 5: Run the whole service suite**

Run: `cargo test -p academic-config-service --test integration -- --test-threads=4`
Expected: all four grade-level event tests pass; the one known pre-existing failure (`status_transition_legal_and_illegal_paths`) is unchanged.

- [ ] **Step 6: Commit**

```bash
git add services/academic-config-service/src/commands.rs services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): publish grade level reordering as one event"
```

---

## Task 5: Project grade levels into academic-ops

**Files:**
- Create: `apps/backend/services/academic-ops-service/migrations/V14__known_grade_level.sql`
- Modify: `apps/backend/services/academic-ops-service/src/repo.rs`
- Modify: `apps/backend/services/academic-ops-service/src/state.rs`
- Modify: `apps/backend/services/academic-ops-service/src/events.rs`
- Modify: `apps/backend/services/academic-ops-service/src/main.rs`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: events `grade_level.created`, `grade_level.updated`, `grade_level.deleted`, `grade_level.reordered` from Tasks 2-4
- Produces: `KnownGradeLevelRepo::upsert(tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final)`, `KnownGradeLevelRepo::delete(tenant_id, grade_level_id)`, `KnownGradeLevelRepo::reorder(tenant_id, academic_year_id, &[(Uuid, i32)])`, `AppState.known_grade_levels`

**Context:** Follow the consumer pattern Plan 2 built for `report_card.published` (`events.rs`, match arm plus `ROUTING_KEYS`). **`ROUTING_KEYS` at `events.rs:14-26` decides which routing keys the queue binds.** A match arm for an event missing from `ROUTING_KEYS` never fires — the consumer looks complete and receives nothing. `ProjectionConsumer::new` has two call sites (`main.rs`, `tests/integration.rs`); adding a repo parameter breaks both.

- [ ] **Step 1: Write the migration**

```sql
-- Grade levels are owned by academic-config. academic-ops needs `is_final`
-- (graduate vs promote) and `ordinal` (which grade comes next) to evaluate
-- promotions, and CONVENTIONS.md forbids calling that service over HTTP.
--
-- Keyed by grade_level_id because that is the identity academic-config owns.
-- `code` is mutable and `ordinal` changes on every reorder, so neither is a
-- stable key.
CREATE TABLE IF NOT EXISTS known_grade_level (
  tenant_id        UUID NOT NULL,
  grade_level_id   UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  code             VARCHAR(64) NOT NULL,
  label            VARCHAR(64) NOT NULL,
  ordinal          INT NOT NULL,
  is_final         BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tenant_id, grade_level_id)
);

CREATE INDEX IF NOT EXISTS known_grade_level_year_idx
  ON known_grade_level (tenant_id, academic_year_id, ordinal);
```

Then `touch services/academic-ops-service/src/lib.rs` so refinery picks it up.

- [ ] **Step 2: Write the failing tests**

```rust
#[tokio::test]
async fn grade_level_events_populate_the_projection() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = Uuid::new_v4();
    let level_id = Uuid::new_v4();

    state.known_grade_levels
        .upsert(tenant_id, level_id, year_id, "X", "Kelas X", 1, false)
        .await.expect("upsert should succeed");

    let (code, ordinal, is_final): (String, i32, bool) = sqlx::query_as(
        "SELECT code, ordinal, is_final FROM known_grade_level \
         WHERE tenant_id = $1 AND grade_level_id = $2",
    ).bind(tenant_id).bind(level_id)
    .fetch_one(&pool).await.expect("row should exist");

    assert_eq!(code, "X");
    assert_eq!(ordinal, 1);
    assert!(!is_final);
}

#[tokio::test]
async fn a_renamed_grade_level_keeps_its_identity() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = Uuid::new_v4();
    let level_id = Uuid::new_v4();

    state.known_grade_levels
        .upsert(tenant_id, level_id, year_id, "X", "Kelas X", 1, false)
        .await.expect("first upsert");
    state.known_grade_levels
        .upsert(tenant_id, level_id, year_id, "XII", "Kelas XII", 3, true)
        .await.expect("rename");

    let rows: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_grade_level WHERE tenant_id = $1",
    ).bind(tenant_id).fetch_one(&pool).await.expect("count");
    assert_eq!(rows, 1, "a rename updates in place, it does not insert a second row");

    let (code, is_final): (String, bool) = sqlx::query_as(
        "SELECT code, is_final FROM known_grade_level \
         WHERE tenant_id = $1 AND grade_level_id = $2",
    ).bind(tenant_id).bind(level_id)
    .fetch_one(&pool).await.expect("row");
    assert_eq!(code, "XII");
    assert!(is_final, "every mutable field must follow the rename, not just code");
}

#[tokio::test]
async fn reorder_moves_the_whole_ladder() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = Uuid::new_v4();
    let a = Uuid::new_v4();
    let b = Uuid::new_v4();

    state.known_grade_levels.upsert(tenant_id, a, year_id, "A", "A", 1, false).await.unwrap();
    state.known_grade_levels.upsert(tenant_id, b, year_id, "B", "B", 2, false).await.unwrap();

    state.known_grade_levels
        .reorder(tenant_id, year_id, &[(b, 1), (a, 2)])
        .await.expect("reorder should succeed");

    let ordinal_b: i32 = sqlx::query_scalar(
        "SELECT ordinal FROM known_grade_level WHERE tenant_id = $1 AND grade_level_id = $2",
    ).bind(tenant_id).bind(b).fetch_one(&pool).await.unwrap();
    let ordinal_a: i32 = sqlx::query_scalar(
        "SELECT ordinal FROM known_grade_level WHERE tenant_id = $1 AND grade_level_id = $2",
    ).bind(tenant_id).bind(a).fetch_one(&pool).await.unwrap();

    assert_eq!(ordinal_b, 1);
    assert_eq!(ordinal_a, 2);
}

#[tokio::test]
async fn grade_level_projection_is_scoped_per_tenant() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_a = Uuid::new_v4();
    let tenant_b = Uuid::new_v4();
    let year_id = Uuid::new_v4();
    let level_id = Uuid::new_v4();

    state.known_grade_levels
        .upsert(tenant_a, level_id, year_id, "X", "Kelas X", 1, false)
        .await.expect("upsert");

    let seen_by_a: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_grade_level WHERE tenant_id = $1",
    ).bind(tenant_a).fetch_one(&pool).await.unwrap();
    let seen_by_b: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM known_grade_level WHERE tenant_id = $1",
    ).bind(tenant_b).fetch_one(&pool).await.unwrap();

    assert_eq!(seen_by_a, 1, "the owning tenant must see its own row");
    assert_eq!(seen_by_b, 0, "another tenant must never see it");
}

#[tokio::test]
async fn grade_level_created_event_is_consumed_end_to_end() {
    // Proves ROUTING_KEYS and the match arm agree. A match arm for an event
    // missing from ROUTING_KEYS never fires, and every repo-level test above
    // would still pass.
    // Follow the shape of `report_card_published_event_is_consumed_end_to_end`
    // in this file: spawn `consumer.run()`, publish on a second real AMQP
    // connection, then poll the table with a timeout.
}
```

The last test's body must be written by following the existing end-to-end test in this file — read it rather than inventing the harness.

- [ ] **Step 3: Run them and watch them fail**

Run: `cargo test -p academic-ops-service --test integration grade_level -- --test-threads=4`
Expected: compile error — `known_grade_levels` does not exist on `AppState`.

- [ ] **Step 4: Add the repo**

Follow `KnownGradingPolicyRepo` (`repo.rs:2251`) for the struct shape. `upsert` uses `ON CONFLICT (tenant_id, grade_level_id) DO UPDATE` and must update **every** mutable column — `academic_year_id`, `code`, `label`, `ordinal`, `is_final`, `updated_at`. `reorder` runs its updates inside one transaction.

- [ ] **Step 5: Wire it into `AppState`, `ROUTING_KEYS`, and the match arms**

Add `known_grade_levels: KnownGradeLevelRepo` to `AppState` and construct it alongside the others. Add all four routing keys to `ROUTING_KEYS`. Add four match arms in `handle_event`. **Do not make `handle_event` public** — the end-to-end test drives it through `run()`. Update both `ProjectionConsumer::new` call sites.

- [ ] **Step 6: Run them and watch them pass**

Run: `cargo test -p academic-ops-service --test integration grade_level -- --test-threads=4`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add services/academic-ops-service/
git commit -m "feat(academic-ops): project grade levels from academic-config"
```

---

## Task 6: Link homerooms to grade levels, and report what will not match

**Files:**
- Create: `apps/backend/services/academic-ops-service/migrations/V15__homeroom_grade_level_link.sql`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: nullable column `homeroom.grade_level_id`

**Context:** This is the task the spec's §2.1 finding is about. In the dev database, `academic_config.grade_level.code` holds `A, B, C, D, E, F` while `academic_ops.homeroom.grade_level` holds `1, 2, 3` — a FULL OUTER JOIN on `code` returns **nine rows and zero matches**. A backfill that silently matches nothing is the worst outcome, because the migration reports success and the failure surfaces months later as "promotion refuses to run" with no legible cause.

No foreign key: `known_grade_level` is a projection and therefore eventually consistent. A hard FK would make homeroom writes fail whenever the projection lags.

- [ ] **Step 1: Write the migration**

```sql
-- Homerooms carry a free-text grade level (VARCHAR(64), e.g. '1' or 'X').
-- The promotion engine needs a real reference: `is_final` to decide
-- graduate-vs-promote, `ordinal` to find the next grade.
--
-- NULLABLE ON PURPOSE. When this was written, the dev database held
-- `A, B, C, D, E, F` in academic_config.grade_level.code and `1, 2, 3` in
-- academic_ops.homeroom.grade_level — zero overlap. The two services have
-- stored different vocabularies for the same concept for a long time and
-- nothing noticed, because nothing had ever compared them. Forcing NOT NULL
-- would make this migration fail outright on such a tenant. NULL is a legible
-- "not yet reconciled" state; a failed migration is not.
--
-- NO FOREIGN KEY to known_grade_level: it is a projection and therefore
-- eventually consistent. A hard FK would make homeroom writes fail whenever
-- the projection lags behind its events.
ALTER TABLE homeroom
  ADD COLUMN IF NOT EXISTS grade_level_id UUID NULL;

CREATE INDEX IF NOT EXISTS homeroom_grade_level_idx
  ON homeroom (tenant_id, grade_level_id);

-- Link what can be linked, scoped by tenant AND year: `code` is only unique
-- per (tenant_id, academic_year_id), so matching on code alone would link a
-- homeroom to another tenant's grade level.
UPDATE homeroom h
   SET grade_level_id = kgl.grade_level_id
  FROM known_grade_level kgl
 WHERE h.grade_level_id IS NULL
   AND kgl.tenant_id        = h.tenant_id
   AND kgl.academic_year_id = h.academic_year_id
   AND kgl.code             = h.grade_level;

-- Report what did not match. A migration that succeeds while linking nothing
-- looks like progress and is not.
DO $$
DECLARE
  unlinked INT;
  samples  TEXT;
BEGIN
  SELECT count(*) INTO unlinked FROM homeroom WHERE grade_level_id IS NULL;
  IF unlinked > 0 THEN
    SELECT string_agg(DISTINCT grade_level, ', ')
      INTO samples
      FROM homeroom
     WHERE grade_level_id IS NULL;
    RAISE WARNING
      'homeroom.grade_level_id: % row(s) could not be linked to a grade level. Unmatched grade_level values: %. Promotion evaluation will refuse to run for these homerooms until they are reconciled.',
      unlinked, samples;
  END IF;
END $$;
```

Then `touch services/academic-ops-service/src/lib.rs`.

- [ ] **Step 2: Write the failing tests**

```rust
#[tokio::test]
async fn backfill_links_matching_homerooms_and_leaves_the_rest_null() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_known_year(&pool, tenant_id).await;
    let level_id = Uuid::new_v4();

    state.known_grade_levels
        .upsert(tenant_id, level_id, year_id, "X", "Kelas X", 1, false)
        .await.expect("seed projection");

    let matching = seed_homeroom(&pool, tenant_id, year_id, "X A", "X").await;
    let unmatched = seed_homeroom(&pool, tenant_id, year_id, "1 A", "1").await;

    sqlx::query(
        "UPDATE homeroom h SET grade_level_id = kgl.grade_level_id \
         FROM known_grade_level kgl \
         WHERE h.grade_level_id IS NULL AND kgl.tenant_id = h.tenant_id \
           AND kgl.academic_year_id = h.academic_year_id AND kgl.code = h.grade_level",
    ).execute(&pool).await.expect("backfill should run");

    let linked: Option<Uuid> = sqlx::query_scalar(
        "SELECT grade_level_id FROM homeroom WHERE homeroom_id = $1",
    ).bind(matching).fetch_one(&pool).await.unwrap();
    assert_eq!(linked, Some(level_id), "a matching code must link");

    let still_null: Option<Uuid> = sqlx::query_scalar(
        "SELECT grade_level_id FROM homeroom WHERE homeroom_id = $1",
    ).bind(unmatched).fetch_one(&pool).await.unwrap();
    assert!(still_null.is_none(),
        "an unmatched vocabulary must stay NULL rather than link to the wrong level");
}

#[tokio::test]
async fn backfill_never_links_across_tenants() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_a = Uuid::new_v4();
    let tenant_b = Uuid::new_v4();
    let year_a = seed_known_year(&pool, tenant_a).await;
    let year_b = seed_known_year(&pool, tenant_b).await;

    // Both tenants use the same code. Only tenant A has the projection row.
    state.known_grade_levels
        .upsert(tenant_a, Uuid::new_v4(), year_a, "X", "Kelas X", 1, false)
        .await.expect("seed A");

    let b_homeroom = seed_homeroom(&pool, tenant_b, year_b, "X A", "X").await;

    sqlx::query(
        "UPDATE homeroom h SET grade_level_id = kgl.grade_level_id \
         FROM known_grade_level kgl \
         WHERE h.grade_level_id IS NULL AND kgl.tenant_id = h.tenant_id \
           AND kgl.academic_year_id = h.academic_year_id AND kgl.code = h.grade_level",
    ).execute(&pool).await.expect("backfill should run");

    let linked: Option<Uuid> = sqlx::query_scalar(
        "SELECT grade_level_id FROM homeroom WHERE homeroom_id = $1",
    ).bind(b_homeroom).fetch_one(&pool).await.unwrap();
    assert!(linked.is_none(),
        "an identical code in another tenant must never link");
}

#[tokio::test]
async fn deleting_a_grade_level_leaves_a_legible_dangling_link() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = Uuid::new_v4();
    let year_id = seed_known_year(&pool, tenant_id).await;
    let level_id = Uuid::new_v4();

    state.known_grade_levels
        .upsert(tenant_id, level_id, year_id, "X", "Kelas X", 1, false)
        .await.expect("seed");
    let homeroom_id = seed_homeroom(&pool, tenant_id, year_id, "X A", "X").await;
    sqlx::query("UPDATE homeroom SET grade_level_id = $1 WHERE homeroom_id = $2")
        .bind(level_id).bind(homeroom_id)
        .execute(&pool).await.expect("link");

    state.known_grade_levels.delete(tenant_id, level_id)
        .await.expect("delete should succeed, there is no FK");

    let dangling: Option<Uuid> = sqlx::query_scalar(
        "SELECT grade_level_id FROM homeroom WHERE homeroom_id = $1",
    ).bind(homeroom_id).fetch_one(&pool).await.unwrap();

    assert_eq!(dangling, Some(level_id),
        "the link survives so the mismatch is visible and reportable, not a crash");

    let orphaned: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM homeroom h \
         WHERE h.grade_level_id IS NOT NULL \
           AND NOT EXISTS (SELECT 1 FROM known_grade_level k \
                           WHERE k.tenant_id = h.tenant_id \
                             AND k.grade_level_id = h.grade_level_id)",
    ).fetch_one(&pool).await.unwrap();
    assert_eq!(orphaned, 1, "the orphan must be findable by a readiness query");
}
```

**None of `seed_homeroom`, `seed_known_year` or `seed_promotion_run` exist in this file.** academic-ops tests insert directly — see `tests/integration.rs:80` for the year (`INSERT INTO known_academic_year (academic_year_id, tenant_id, status) VALUES ($1, $2, $3)`) and `:2317` for a homeroom (`INSERT INTO homeroom (homeroom_id, tenant_id, name, grade_level, capacity, academic_year_id) VALUES (...)`). Write these as local helpers in this file following that exact insert style. A homeroom needs its `known_academic_year` row first: `homeroom.academic_year_id` is a foreign key to it.

- [ ] **Step 3: Run them and watch them fail**

Run: `cargo test -p academic-ops-service --test integration homeroom -- --test-threads=4`
Expected: FAIL — column `grade_level_id` does not exist.

- [ ] **Step 4: Apply the migration and re-run**

Run: `cargo test -p academic-ops-service --test integration homeroom -- --test-threads=4`
Expected: all PASS.

- [ ] **Step 5: Prove the migration is idempotent**

Apply the migration twice against a scratch database and confirm the second run produces no error.

- [ ] **Step 6: Commit**

```bash
git add services/academic-ops-service/
git commit -m "feat(academic-ops): link homerooms to grade levels"
```

---

## Task 7: Bootstrap the projection for existing tenants

**Files:**
- Modify: `apps/backend/scripts/bootstrap-projections.sh`

**Context:** Events only carry changes forward. Without a bootstrap, `known_grade_level` stays empty until somebody edits a grade level, and promotion evaluation refuses to run for every school that already exists. The script already handles cross-schema projection seeding — extend it rather than inventing a new mechanism.

- [ ] **Step 1: Read the existing script**

Read `scripts/bootstrap-projections.sh` and follow its `table_exists` guard style and `_psql` helper.

- [ ] **Step 2: Add the grade level bootstrap**

```sql
INSERT INTO academic_ops.known_grade_level
  (tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final, updated_at)
SELECT tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final, NOW()
  FROM academic_config.grade_level
ON CONFLICT (tenant_id, grade_level_id) DO UPDATE
   SET academic_year_id = EXCLUDED.academic_year_id,
       code             = EXCLUDED.code,
       label            = EXCLUDED.label,
       ordinal          = EXCLUDED.ordinal,
       is_final         = EXCLUDED.is_final,
       updated_at       = NOW();
```

Guard it with the script's existing `table_exists` check on both tables, so it is a no-op on a database where either side has not migrated yet.

- [ ] **Step 3: Run it against the dev database**

Run: `bash scripts/bootstrap-projections.sh`
Expected: completes without error. A tenant with zero grade levels must produce zero rows and no failure.

- [ ] **Step 4: Run it a second time**

Expected: completes without error and the row count is unchanged — the `ON CONFLICT` makes it safe to re-run.

- [ ] **Step 5: Verify the result**

```bash
docker compose exec -T postgres psql -U akademiq -d akademiq -c \
  "SELECT count(*) FROM academic_ops.known_grade_level;"
```

Expected: matches `SELECT count(*) FROM academic_config.grade_level`.

- [ ] **Step 6: Commit**

```bash
git add scripts/bootstrap-projections.sh
git commit -m "chore(backend): bootstrap the grade level projection"
```

---

## Task 8: Create the promotion tables

**Files:**
- Create: `apps/backend/services/academic-ops-service/migrations/V16__promotion_tables.sql`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Context:** Parent spec §3, with `NUMERIC` corrected to `DOUBLE PRECISION` throughout. Nothing writes to these tables in this plan — Task 8 creates them and proves their constraints reject what they must. Plan 3b builds the engine that fills them.

- [ ] **Step 1: Write the migration**

```sql
-- Promotion tables. Nothing writes to these in Plan 3a; the evaluation engine
-- in Plan 3b does. They land here so their constraints are proven before any
-- code depends on them.
--
-- DOUBLE PRECISION, not NUMERIC: every producer and every existing projection
-- of a score or threshold in this system uses DOUBLE PRECISION. A type
-- mismatch across projections of the same fact produces subtle comparison
-- bugs, and the comparison here decides whether a child repeats a year.

-- Rules are frozen when an evaluation runs, so an old decision stays
-- explainable even after the school changes its rules next year.
CREATE TABLE IF NOT EXISTS promotion_rule_snapshot (
  rule_id                UUID PRIMARY KEY,
  tenant_id              UUID NOT NULL,
  academic_year_id       UUID NOT NULL,
  min_average            DOUBLE PRECISION NULL,
  max_subjects_below_kkm INT NULL,
  min_attendance_percent DOUBLE PRECISION NULL,
  kkm_snapshot           DOUBLE PRECISION NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS promotion_rule_snapshot_tenant_year_idx
  ON promotion_rule_snapshot (tenant_id, academic_year_id);

CREATE TABLE IF NOT EXISTS promotion_run (
  run_id           UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  rule_id          UUID NOT NULL REFERENCES promotion_rule_snapshot(rule_id),
  status           VARCHAR(32) NOT NULL,
  created_by       UUID NOT NULL,
  approved_by      UUID NULL,
  executed_at      TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT promotion_run_status_chk
    CHECK (status IN ('draft', 'submitted', 'approved', 'executed'))
);

CREATE INDEX IF NOT EXISTS promotion_run_tenant_year_idx
  ON promotion_run (tenant_id, academic_year_id);

CREATE TABLE IF NOT EXISTS promotion_decision (
  decision_id        UUID PRIMARY KEY,
  run_id             UUID NOT NULL REFERENCES promotion_run(run_id) ON DELETE CASCADE,
  tenant_id          UUID NOT NULL,
  student_id         UUID NOT NULL,
  enrollment_id      UUID NOT NULL,
  academic_year_id   UUID NOT NULL,
  homeroom_id        UUID NOT NULL,
  recommended        VARCHAR(16) NOT NULL,
  result             VARCHAR(16) NOT NULL,
  overridden         BOOLEAN NOT NULL DEFAULT FALSE,
  reason             TEXT NULL,
  computed_metrics   JSONB NOT NULL,
  target_homeroom_id UUID NULL,
  CONSTRAINT promotion_decision_recommended_chk
    CHECK (recommended IN ('promote', 'retain', 'graduate')),
  CONSTRAINT promotion_decision_result_chk
    CHECK (result IN ('promote', 'retain', 'graduate')),
  -- An override without a real reason is an unexplained decision about a
  -- child's year. Ten characters is a low bar that still rejects "ok".
  CONSTRAINT promotion_decision_override_reason_chk
    CHECK (NOT overridden OR (reason IS NOT NULL AND length(trim(reason)) >= 10)),
  CONSTRAINT promotion_decision_run_student_unique UNIQUE (run_id, student_id)
);

CREATE INDEX IF NOT EXISTS promotion_decision_tenant_run_idx
  ON promotion_decision (tenant_id, run_id);

CREATE TABLE IF NOT EXISTS graduation_record (
  graduation_id      UUID PRIMARY KEY,
  tenant_id          UUID NOT NULL,
  student_id         UUID NOT NULL,
  academic_year_id   UUID NOT NULL,
  graduation_date    DATE NOT NULL,
  certificate_number VARCHAR(64) NULL,
  CONSTRAINT graduation_record_student_year_unique UNIQUE (student_id, academic_year_id)
);

CREATE INDEX IF NOT EXISTS graduation_record_tenant_idx
  ON graduation_record (tenant_id, academic_year_id);

CREATE TABLE IF NOT EXISTS retention_record (
  retention_id     UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  student_id       UUID NOT NULL,
  academic_year_id UUID NOT NULL,
  reason           TEXT NOT NULL,
  CONSTRAINT retention_record_student_year_unique UNIQUE (student_id, academic_year_id)
);

CREATE INDEX IF NOT EXISTS retention_record_tenant_idx
  ON retention_record (tenant_id, academic_year_id);
```

Then `touch services/academic-ops-service/src/lib.rs`.

- [ ] **Step 2: Write the failing constraint tests**

```rust
#[tokio::test]
async fn promotion_decision_rejects_an_override_without_a_reason() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;

    let result = sqlx::query(
        "INSERT INTO promotion_decision \
         (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
          homeroom_id, recommended, result, overridden, reason, computed_metrics) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'promote', 'retain', TRUE, NULL, '{}'::jsonb)",
    )
    .bind(Uuid::new_v4()).bind(run_id).bind(tenant_id)
    .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
    .execute(&pool).await;

    assert!(result.is_err(),
        "overriding a child's promotion without a reason must be impossible");
}

#[tokio::test]
async fn promotion_decision_rejects_a_token_reason() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;

    let result = sqlx::query(
        "INSERT INTO promotion_decision \
         (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
          homeroom_id, recommended, result, overridden, reason, computed_metrics) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'promote', 'retain', TRUE, '   ok   ', '{}'::jsonb)",
    )
    .bind(Uuid::new_v4()).bind(run_id).bind(tenant_id)
    .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
    .execute(&pool).await;

    assert!(result.is_err(),
        "whitespace padding must not satisfy the minimum reason length");
}

#[tokio::test]
async fn promotion_run_rejects_an_unknown_status() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let rule_id = seed_promotion_rule(&pool).await;

    let result = sqlx::query(
        "INSERT INTO promotion_run \
         (run_id, tenant_id, academic_year_id, rule_id, status, created_by) \
         VALUES ($1, $2, $3, $4, 'not_a_real_status', $5)",
    )
    .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
    .bind(rule_id).bind(Uuid::new_v4())
    .execute(&pool).await;

    assert!(result.is_err(), "the status vocabulary must stay closed");
}

#[tokio::test]
async fn promotion_decision_rejects_two_decisions_for_one_student_in_a_run() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;
    let student_id = Uuid::new_v4();

    for _ in 0..1 {
        sqlx::query(
            "INSERT INTO promotion_decision \
             (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
              homeroom_id, recommended, result, computed_metrics) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, 'promote', 'promote', '{}'::jsonb)",
        )
        .bind(Uuid::new_v4()).bind(run_id).bind(tenant_id).bind(student_id)
        .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
        .execute(&pool).await.expect("the first decision should insert");
    }

    let second = sqlx::query(
        "INSERT INTO promotion_decision \
         (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
          homeroom_id, recommended, result, computed_metrics) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'retain', 'retain', '{}'::jsonb)",
    )
    .bind(Uuid::new_v4()).bind(run_id).bind(tenant_id).bind(student_id)
    .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
    .execute(&pool).await;

    assert!(second.is_err(),
        "one student cannot have two decisions in the same run");
}

#[tokio::test]
async fn promotion_decision_rejects_an_unknown_result() {
    let (pool, _state, _url, _pg, _rabbit) = boot().await;
    let (run_id, tenant_id) = seed_promotion_run(&pool).await;

    let result = sqlx::query(
        "INSERT INTO promotion_decision \
         (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, \
          homeroom_id, recommended, result, computed_metrics) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'promote', 'expelled', '{}'::jsonb)",
    )
    .bind(Uuid::new_v4()).bind(run_id).bind(tenant_id)
    .bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4()).bind(Uuid::new_v4())
    .execute(&pool).await;

    assert!(result.is_err(), "the result vocabulary must stay closed");
}
```

Write `seed_promotion_rule` and `seed_promotion_run` as local test helpers that insert one valid row each and return the ids.

- [ ] **Step 3: Run them and watch them fail**

Run: `cargo test -p academic-ops-service --test integration promotion_ -- --test-threads=4`
Expected: FAIL — relation `promotion_run` does not exist.

- [ ] **Step 4: Apply the migration and re-run**

Run: `cargo test -p academic-ops-service --test integration promotion_ -- --test-threads=4`
Expected: all PASS.

- [ ] **Step 5: Prove the constraints have teeth**

Temporarily relax `promotion_decision_override_reason_chk` to `CHECK (true)` in a scratch database, confirm the two reason tests FAIL, then revert exactly. A constraint test that passes against a permissive constraint is not a guard.

- [ ] **Step 6: Commit**

```bash
git add services/academic-ops-service/
git commit -m "feat(academic-ops): add promotion run and decision tables"
```

---

## Task 9: Seed the promotion permissions

**Files:**
- Create: `apps/backend/services/iam-service/migrations/V26__seed_promotion_permissions.sql`
- Test: `apps/backend/services/iam-service/tests/integration.rs`

**Context:** Follow `V21__seed_academic_ops_manage_permission.sql` exactly. Feature code `promotion` already exists at `features.toml:32` and needs no new entry.

`promotion.manage` and `promotion.approve` are deliberately separate. One permission would let whoever computes the decisions also approve them, collapsing the only human check in the entire flow.

- [ ] **Step 1: Read the precedent**

Read `services/iam-service/migrations/V21__seed_academic_ops_manage_permission.sql` and copy its structure, including how it assigns the permission to roles.

- [ ] **Step 2: Write the migration**

Insert both permissions with fixed UUIDs following V21's numbering convention, and assign them to roles as V21 does. `promotion.manage` goes to the role that manages academic operations; `promotion.approve` goes only to the principal-equivalent role. Use `ON CONFLICT DO NOTHING` so the migration is re-runnable.

Then `touch services/iam-service/src/lib.rs`.

- [ ] **Step 3: Write the failing test**

```rust
#[tokio::test]
async fn promotion_permissions_are_seeded_and_separate() {
    let (pool, _state, _c) = boot_state().await;

    let codes: Vec<String> = sqlx::query_scalar(
        "SELECT code FROM permission WHERE code LIKE 'promotion.%' ORDER BY code",
    ).fetch_all(&pool).await.expect("query should succeed");

    assert_eq!(codes, vec!["promotion.approve", "promotion.manage"]);

    let same_role: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM role_permission rp1 \
         JOIN role_permission rp2 ON rp1.role_id = rp2.role_id \
         JOIN permission p1 ON p1.permission_id = rp1.permission_id \
         JOIN permission p2 ON p2.permission_id = rp2.permission_id \
         WHERE p1.code = 'promotion.manage' AND p2.code = 'promotion.approve'",
    ).fetch_one(&pool).await.expect("query should succeed");

    assert_eq!(same_role, 0,
        "no role may both compute and approve promotions - that is the only human check");
}
```

`role_permission` joins on `role_id` (UUID, FK to `role`), not a role code — verified in `V1__init.sql:42-46`. Read V21 to see how it resolves a role name to its id before writing the migration.

- [ ] **Step 4: Run it and watch it fail**

Run: `cargo test -p iam-service --test integration promotion_permissions -- --test-threads=4`
Expected: FAIL — empty result.

- [ ] **Step 5: Run it and watch it pass**

Run: `cargo test -p iam-service --test integration promotion_permissions -- --test-threads=4`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add services/iam-service/
git commit -m "feat(iam): seed promotion manage and approve permissions"
```

---

## Task 10: Final verification

**Context:** Run by the orchestrator, not delegated. This is the gate.

- [ ] **Step 1: Full suites for all three touched services**

```bash
cargo test -p academic-config-service --test integration -- --test-threads=4
cargo test -p academic-ops-service --test integration -- --test-threads=4
cargo test -p iam-service --test integration -- --test-threads=4
```

Expected: pass counts up; failure counts unchanged from the known pre-existing list.

- [ ] **Step 2: Workspace build and unit tests**

```bash
cargo test --workspace --lib
cargo check --workspace
```

- [ ] **Step 3: Apply every new migration to the real dev database, twice**

Prove idempotence against real data, not just empty testcontainers. Confirm `known_grade_level`, `homeroom.grade_level_id` and all five promotion tables exist afterwards.

- [ ] **Step 4: Run the bootstrap and confirm the projection matches its source**

```bash
bash scripts/bootstrap-projections.sh
docker compose exec -T postgres psql -U akademiq -d akademiq -c \
  "SELECT (SELECT count(*) FROM academic_config.grade_level) AS source, \
          (SELECT count(*) FROM academic_ops.known_grade_level) AS projected;"
```

Expected: the two counts match.

- [ ] **Step 5: Confirm the end-to-end event path**

Verify all four `grade_level.*` routing keys appear in `ROUTING_KEYS` **and** in the match arms. A match arm without its routing key never fires.

- [ ] **Step 6: Bump the submodule pointer in the parent repo**

```bash
cd /home/fitrah/projects/akademiq
git add apps/backend
git commit -m "chore: bump backend to promotion foundation"
```
