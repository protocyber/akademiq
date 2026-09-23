# Tingkat Kelas (grade_level) Implementation Plan — A1 Plan 1 of 4

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `grade_level` from a free-text string into a first-class ordered entity in `academic-config-service`, so promotion can compute "next grade level" and detect the final grade level.

**Architecture:** New `grade_level` table in `academic-config-service` scoped per academic year (same pattern as the existing `class_template`). `homeroom` and `class_template` gain a nullable `grade_level_id` FK; the old string column stays during transition. A data migration seeds one `grade_level` row per distinct existing string with a *guessed* ordinal that an admin must review. New CRUD endpoints + a new web page at `/settings/academic/grade-levels`.

**Tech Stack:** Rust + Axum + SQLx + refinery (backend), Next.js 15 + shadcn/ui + TanStack Query + Zod (web), testcontainers for backend integration tests, Vitest for web.

**Spec:** `docs/superpowers/specs/2026-09-23-promotion-design.md` (section 2)

**Roadmap:** `.ai/plans/21_academic_year_cycle_roadmap.md` (feature A1)

## Plan Split

The spec's section 10 lists 10 implementation steps across three backend
services plus web. That is too much for one plan. It is split into four,
each producing working, testable software on its own:

| Plan | Covers | Spec sections |
|---|---|---|
| **1 (this one)** | `grade_level` entity + migration + API + UI | 2 |
| 2 | Status constraints (`promoted`, `lulus`, `alumni`) + `report_card.published` event + projections `known_report_score`, `known_grading_policy` | 3.2, 5 |
| 3 | Promotion tables + evaluation engine + run API + execution + events | 3, 4, 6 |
| 4 | Web `/promotion` UI + SK print components | 7, 8 |

Plan 1 ships alone: after it, schools can define ordered grade levels and
mark the final one, which is useful on its own for consistent class naming.

## Global Constraints

Copied verbatim from the spec and the repo's CONVENTIONS files.

- API base path: `/api/v1/academic-config`. Success envelope `{ "data": ..., "meta": ... }`; error envelope `{ "error": { "code": ..., "message": ... } }`; validation errors `{ "error": { "code": "VALIDATION_ERROR", "fields": { "name": ["msg"] } } }`.
- Never trust a client-supplied `tenant_id` — always resolve from `auth.tenant_id` (JWT).
- Migrations use `refinery`, embedded per crate. Applied migrations are immutable — never edit one after it has been applied; add a new `V<N>__*.sql`.
- Command and query handlers live in separate modules (`commands.rs` / `queries.rs`). CQRS is mandatory.
- Feature gating uses `RequiredFeature<AcademicConfigFeature>`; feature code is `academic_config`. Permission for writes: `academic.config.write` via `require_academic_config_write`; reads: `academic.config.read`.
- `ordinal` is `INT NOT NULL`, must be `> 0`, unique per `(tenant_id, academic_year_id)`.
- `code` is `VARCHAR(32)`, unique per `(tenant_id, academic_year_id)`. `label` is `VARCHAR(64)`.
- Exactly one `grade_level` per academic year may have `is_final = TRUE` — enforced in the command layer, not by a DB constraint (partial unique index would also work but the command layer must return a `VALIDATION_ERROR`, not a 500).
- Web page UI uses shadcn/ui only; all data access goes through TanStack Query; error copy comes from `@/lib/errors/messages`.
- Backend tests: `cargo test --workspace --lib` for units; integration tests live in `services/<name>/tests/integration.rs` and use `common_testing::harness::{start_postgres, start_rabbitmq}`.
- Web tests: `pnpm test:unit` (Vitest), files in `__tests__/` or colocated `*.test.tsx`.

## Review Focus

Input classes the spec implies but no obvious task exercises. Each has a test pinned to the task that owns the code.

1. **Two grade levels marked `is_final` in the same year** — the second must be rejected with `VALIDATION_ERROR`, not silently accepted, or promotion will graduate the wrong cohort. *(Task 4, Step 9)*
2. **Duplicate `ordinal` within one academic year** — must surface as a `409 CONFLICT`, not a raw SQLx unique-violation 500. *(Task 4, Step 13)*
3. **Migration on a tenant whose `grade_level` strings are inconsistent (`"X"`, `"x"`, `"10"`)** — these become three separate rows with guessed ordinals; the migration must not crash and must not merge them silently. *(Task 2, Step 5)*
4. **Migration on a year with zero homerooms/templates** — must produce zero `grade_level` rows and still succeed, rather than failing on an empty aggregate. *(Task 2, Step 7)*
5. **Cross-tenant read/update of a `grade_level_id`** — must 404, never return or mutate another tenant's row. *(Task 4, Step 15)*

---

## File Structure

**Backend — `apps/backend/services/academic-config-service/`**

| File | Responsibility |
|---|---|
| `migrations/V8__grade_level.sql` (create) | Table, indexes, `grade_level_id` columns on `class_template` |
| `migrations/V9__backfill_grade_level.sql` (create) | Data migration seeding rows from existing strings |
| `src/domain.rs` (modify) | `GradeLevel` struct |
| `src/repo.rs` (modify) | `GradeLevelRepo` — insert/list/count/find/update/delete/reorder |
| `src/commands.rs` (modify) | `add_grade_level`, `update_grade_level`, `delete_grade_level`, `reorder_grade_levels` |
| `src/queries.rs` (modify) | `list_grade_levels` |
| `src/state.rs` (modify) | Wire `grade_level_repo` into `AppState` |
| `src/http.rs` (modify) | Routes + handlers |
| `tests/integration.rs` (modify) | Integration tests |

`homeroom` lives in `academic-ops-service`, a different database. Its
`grade_level_id` column is **out of scope for this plan** — it is added in
Plan 3 where promotion actually reads it. Adding it now would create a
column nothing writes.

**Web — `apps/web/`**

| File | Responsibility |
|---|---|
| `src/lib/schemas/grade-level.ts` (create) | Zod form schema |
| `src/lib/query/queries/use-academic-config.ts` (modify) | `GradeLevel` type, `GRADE_LEVELS_QUERY_KEY`, `useGradeLevels` |
| `src/lib/query/mutations/use-academic-config.ts` (modify) | Add/update/delete/reorder mutations |
| `src/components/features/academic-config/academic-settings.tsx` (modify) | Add nav tab |
| `src/app/settings/academic/grade-levels/page.tsx` (create) | The page |
| `__tests__/grade-levels-page.test.tsx` (create) | Component tests |

---

## Task 1: Create the `grade_level` table

**Files:**
- Create: `apps/backend/services/academic-config-service/migrations/V8__grade_level.sql`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: nothing.
- Produces: table `grade_level` with columns `grade_level_id UUID PK`, `tenant_id UUID`, `academic_year_id UUID`, `code VARCHAR(32)`, `label VARCHAR(64)`, `ordinal INT`, `is_final BOOLEAN`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ`. Column `class_template.grade_level_id UUID NULL`.

- [ ] **Step 1: Write the failing test**

Add to `apps/backend/services/academic-config-service/tests/integration.rs`:

```rust
#[tokio::test]
async fn grade_level_table_exists_with_expected_constraints() {
    let (pool, _state, _rabbitmq_url, _pg, _rabbit) = boot().await;

    // Table exists and accepts a well-formed row.
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO academic_year
             (academic_year_id, tenant_id, name, start_date, end_date, status, created_at, updated_at)
           VALUES ($1, $2, '2026/2027', '2026-07-01', '2027-06-30', 'Draft', NOW(), NOW())"#,
    )
    .bind(year_id)
    .bind(tenant_id)
    .execute(&pool)
    .await
    .expect("seed year");

    sqlx::query(
        r#"INSERT INTO grade_level
             (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
           VALUES ($1, $2, $3, 'X', 'Kelas X', 1, FALSE, NOW(), NOW())"#,
    )
    .bind(uuid::Uuid::new_v4())
    .bind(tenant_id)
    .bind(year_id)
    .execute(&pool)
    .await
    .expect("insert grade level");

    // ordinal must be > 0
    let bad_ordinal = sqlx::query(
        r#"INSERT INTO grade_level
             (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
           VALUES ($1, $2, $3, 'Z', 'Kelas Z', 0, FALSE, NOW(), NOW())"#,
    )
    .bind(uuid::Uuid::new_v4())
    .bind(tenant_id)
    .bind(year_id)
    .execute(&pool)
    .await;
    assert!(bad_ordinal.is_err(), "ordinal 0 must violate the check constraint");

    // duplicate code in the same year is rejected
    let dup_code = sqlx::query(
        r#"INSERT INTO grade_level
             (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
           VALUES ($1, $2, $3, 'X', 'Kelas X lagi', 2, FALSE, NOW(), NOW())"#,
    )
    .bind(uuid::Uuid::new_v4())
    .bind(tenant_id)
    .bind(year_id)
    .execute(&pool)
    .await;
    assert!(dup_code.is_err(), "duplicate code in one year must be rejected");

    // duplicate ordinal in the same year is rejected
    let dup_ordinal = sqlx::query(
        r#"INSERT INTO grade_level
             (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
           VALUES ($1, $2, $3, 'XI', 'Kelas XI', 1, FALSE, NOW(), NOW())"#,
    )
    .bind(uuid::Uuid::new_v4())
    .bind(tenant_id)
    .bind(year_id)
    .execute(&pool)
    .await;
    assert!(dup_ordinal.is_err(), "duplicate ordinal in one year must be rejected");
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_table_exists -- --nocapture
```

Expected: FAIL — `relation "grade_level" does not exist`.

- [ ] **Step 3: Write the migration**

Create `apps/backend/services/academic-config-service/migrations/V8__grade_level.sql`:

```sql
-- Grade level as a first-class ordered entity.
--
-- Replaces the free-text `grade_level` VARCHAR on class_template (and, in
-- academic-ops, on homeroom). Promotion needs three things a string cannot
-- provide: a deterministic ordering (`ordinal`), a marker for the terminal
-- grade (`is_final`), and a guarantee that one grade level is spelled one way.
--
-- Scoped per academic year, matching class_template: a school may restructure
-- its grade ladder between years without rewriting history.

CREATE TABLE IF NOT EXISTS grade_level (
  grade_level_id   UUID PRIMARY KEY,
  tenant_id        UUID NOT NULL,
  academic_year_id UUID NOT NULL REFERENCES academic_year(academic_year_id) ON DELETE CASCADE,
  code             VARCHAR(32) NOT NULL,
  label            VARCHAR(64) NOT NULL,
  ordinal          INT NOT NULL,
  is_final         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT grade_level_code_unique    UNIQUE (tenant_id, academic_year_id, code),
  CONSTRAINT grade_level_ordinal_unique UNIQUE (tenant_id, academic_year_id, ordinal),
  CONSTRAINT grade_level_ordinal_chk    CHECK (ordinal > 0)
);

CREATE INDEX IF NOT EXISTS grade_level_year_ordinal_idx
  ON grade_level (tenant_id, academic_year_id, ordinal);

-- Nullable during transition: the string column stays authoritative until
-- every tenant has reviewed the backfilled ordinals.
ALTER TABLE class_template
  ADD COLUMN IF NOT EXISTS grade_level_id UUID NULL REFERENCES grade_level(grade_level_id);
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_table_exists -- --nocapture
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/services/academic-config-service/migrations/V8__grade_level.sql \
        apps/backend/services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): add grade_level table"
```

---

## Task 2: Backfill grade levels from existing strings

**Files:**
- Create: `apps/backend/services/academic-config-service/migrations/V9__backfill_grade_level.sql`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: table `grade_level` from Task 1.
- Produces: one `grade_level` row per distinct `class_template.grade_level` string per `(tenant_id, academic_year_id)`, with `ordinal` assigned by a Roman-numeral-aware ordering and `is_final` always `FALSE`. `class_template.grade_level_id` is populated.

This is the migration the spec calls a *guess*. It must never merge two
different strings and must never claim to know the final grade level.

- [ ] **Step 1: Write the failing test — happy path ordering**

Add to `tests/integration.rs`:

```rust
/// Seeds class templates directly, then re-runs migrations to exercise the
/// backfill. Returns the backfilled rows ordered by ordinal.
async fn backfilled_levels(pool: &PgPool, tenant_id: uuid::Uuid, year_id: uuid::Uuid)
    -> Vec<(String, i32, bool)>
{
    sqlx::query_as::<_, (String, i32, bool)>(
        r#"SELECT code, ordinal, is_final
             FROM grade_level
            WHERE tenant_id = $1 AND academic_year_id = $2
            ORDER BY ordinal"#,
    )
    .bind(tenant_id)
    .bind(year_id)
    .fetch_all(pool)
    .await
    .expect("fetch backfilled levels")
}

#[tokio::test]
async fn backfill_orders_roman_numerals_correctly() {
    let (pool, _state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = seed_year_row(&pool, tenant_id, "2026/2027").await;

    // Deliberately inserted out of order; X must still come before XI and XII.
    for (code, capacity) in [("XII", 30), ("X", 30), ("XI", 30)] {
        seed_class_template_row(&pool, tenant_id, year_id, code, capacity).await;
    }

    run_backfill(&pool).await;

    let levels = backfilled_levels(&pool, tenant_id, year_id).await;
    assert_eq!(
        levels,
        vec![
            ("X".to_string(), 1, false),
            ("XI".to_string(), 2, false),
            ("XII".to_string(), 3, false),
        ],
        "roman numerals must be ordered by value, not alphabetically"
    );
}
```

Add these helpers next to the other test helpers in the same file:

```rust
async fn seed_year_row(pool: &PgPool, tenant_id: uuid::Uuid, name: &str) -> uuid::Uuid {
    let year_id = uuid::Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO academic_year
             (academic_year_id, tenant_id, name, start_date, end_date, status, created_at, updated_at)
           VALUES ($1, $2, $3, '2026-07-01', '2027-06-30', 'Draft', NOW(), NOW())"#,
    )
    .bind(year_id)
    .bind(tenant_id)
    .bind(name)
    .execute(pool)
    .await
    .expect("seed year row");
    year_id
}

async fn seed_class_template_row(
    pool: &PgPool,
    tenant_id: uuid::Uuid,
    year_id: uuid::Uuid,
    grade_level: &str,
    capacity: i32,
) -> uuid::Uuid {
    let template_id = uuid::Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO class_template
             (template_id, tenant_id, academic_year_id, grade_level, default_capacity, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, NOW(), NOW())"#,
    )
    .bind(template_id)
    .bind(tenant_id)
    .bind(year_id)
    .bind(grade_level)
    .bind(capacity)
    .execute(pool)
    .await
    .expect("seed class template row");
    template_id
}

/// The V9 migration body, callable from tests. Migrations run once at boot,
/// before these rows exist, so tests invoke the same SQL directly.
async fn run_backfill(pool: &PgPool) {
    let sql = include_str!("../migrations/V9__backfill_grade_level.sql");
    // Strip refinery's leading comments is unnecessary; Postgres ignores them.
    sqlx::raw_sql(sql).execute(pool).await.expect("run backfill");
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration backfill_orders_roman -- --nocapture
```

Expected: FAIL to compile — `V9__backfill_grade_level.sql` does not exist.

- [ ] **Step 3: Write the migration**

Create `apps/backend/services/academic-config-service/migrations/V9__backfill_grade_level.sql`:

```sql
-- Seed grade_level rows from the existing free-text class_template.grade_level.
--
-- The assigned `ordinal` is a GUESS: Roman numerals are decoded to their
-- numeric value, plain integers are used directly, and anything else falls
-- back to alphabetical order after the recognised values. `is_final` is
-- always FALSE — no heuristic may decide which grade graduates a student.
-- An administrator must review both before promotion can run (enforced in
-- the promotion service, not here).
--
-- Idempotent: ON CONFLICT DO NOTHING means re-running changes nothing.
-- Distinct strings are never merged: "X", "x" and "10" become three rows,
-- which is the honest representation of inconsistent source data.
--
-- The rank expression is inlined rather than extracted into a pg_temp
-- function: pg_temp objects are session-scoped, and neither refinery nor a
-- pooled connection guarantees the CREATE and the INSERT share a session.

INSERT INTO grade_level
  (grade_level_id, tenant_id, academic_year_id, code, label, ordinal, is_final, created_at, updated_at)
SELECT
  gen_random_uuid(),
  ranked.tenant_id,
  ranked.academic_year_id,
  ranked.grade_level,
  ranked.grade_level,
  ranked.ordinal,
  FALSE,
  NOW(),
  NOW()
FROM (
  SELECT
    tenant_id,
    academic_year_id,
    grade_level,
    ROW_NUMBER() OVER (
      PARTITION BY tenant_id, academic_year_id
      ORDER BY
        CASE upper(trim(grade_level))
          WHEN 'I'   THEN 1  WHEN 'II'   THEN 2  WHEN 'III'  THEN 3
          WHEN 'IV'  THEN 4  WHEN 'V'    THEN 5  WHEN 'VI'   THEN 6
          WHEN 'VII' THEN 7  WHEN 'VIII' THEN 8  WHEN 'IX'   THEN 9
          WHEN 'X'   THEN 10 WHEN 'XI'   THEN 11 WHEN 'XII'  THEN 12
          ELSE CASE
            WHEN trim(grade_level) ~ '^[0-9]+$' THEN trim(grade_level)::INT
            ELSE NULL
          END
        END NULLS LAST,
        grade_level
    )::INT AS ordinal
  FROM (
    SELECT DISTINCT tenant_id, academic_year_id, grade_level
      FROM class_template
     WHERE grade_level IS NOT NULL
       AND trim(grade_level) <> ''
  ) distinct_levels
) ranked
ON CONFLICT (tenant_id, academic_year_id, code) DO NOTHING;

-- Point existing class templates at their new grade_level row.
UPDATE class_template ct
   SET grade_level_id = gl.grade_level_id
  FROM grade_level gl
 WHERE ct.grade_level_id IS NULL
   AND gl.tenant_id        = ct.tenant_id
   AND gl.academic_year_id = ct.academic_year_id
   AND gl.code             = ct.grade_level;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration backfill_orders_roman -- --nocapture
```

Expected: PASS.

- [ ] **Step 5: Write the failing test — inconsistent strings stay separate** *(Review Focus #3)*

```rust
#[tokio::test]
async fn backfill_keeps_inconsistent_strings_separate() {
    let (pool, _state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = seed_year_row(&pool, tenant_id, "2026/2027").await;

    for code in ["X", "x", "10"] {
        seed_class_template_row(&pool, tenant_id, year_id, code, 30).await;
    }

    run_backfill(&pool).await;

    let levels = backfilled_levels(&pool, tenant_id, year_id).await;
    assert_eq!(levels.len(), 3, "inconsistent strings must NOT be silently merged");

    let codes: Vec<&str> = levels.iter().map(|(c, _, _)| c.as_str()).collect();
    assert!(codes.contains(&"X"));
    assert!(codes.contains(&"x"));
    assert!(codes.contains(&"10"));

    // Ordinals are still unique and contiguous from 1.
    let mut ordinals: Vec<i32> = levels.iter().map(|(_, o, _)| *o).collect();
    ordinals.sort_unstable();
    assert_eq!(ordinals, vec![1, 2, 3]);

    // No heuristic may guess the final grade.
    assert!(levels.iter().all(|(_, _, is_final)| !is_final),
        "backfill must never set is_final");
}
```

- [ ] **Step 6: Run it**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration backfill_keeps_inconsistent -- --nocapture
```

Expected: PASS with the migration from Step 3 (no code change needed — this test pins behaviour that must not regress).

- [ ] **Step 7: Write the failing test — empty year** *(Review Focus #4)*

```rust
#[tokio::test]
async fn backfill_on_year_without_templates_succeeds_and_creates_nothing() {
    let (pool, _state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = seed_year_row(&pool, tenant_id, "2026/2027").await;

    run_backfill(&pool).await;

    let levels = backfilled_levels(&pool, tenant_id, year_id).await;
    assert!(levels.is_empty(), "a year with no templates yields no grade levels");
}

#[tokio::test]
async fn backfill_is_idempotent() {
    let (pool, _state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = seed_year_row(&pool, tenant_id, "2026/2027").await;
    seed_class_template_row(&pool, tenant_id, year_id, "X", 30).await;

    run_backfill(&pool).await;
    run_backfill(&pool).await;

    let levels = backfilled_levels(&pool, tenant_id, year_id).await;
    assert_eq!(levels.len(), 1, "re-running the backfill must not duplicate rows");
}
```

- [ ] **Step 8: Run both**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration backfill_ -- --nocapture
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add apps/backend/services/academic-config-service/migrations/V9__backfill_grade_level.sql \
        apps/backend/services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): backfill grade_level rows from class templates"
```

---

## Task 3: Domain type and repository

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/domain.rs`
- Modify: `apps/backend/services/academic-config-service/src/repo.rs`
- Modify: `apps/backend/services/academic-config-service/src/state.rs`

**Interfaces:**
- Consumes: table `grade_level` (Task 1).
- Produces:
  - `domain::GradeLevel { grade_level_id: Uuid, tenant_id: Uuid, academic_year_id: Uuid, code: String, label: String, ordinal: i32, is_final: bool, created_at: DateTime<Utc>, updated_at: DateTime<Utc> }`
  - `repo::GradeLevelRepo::new(pool: PgPool) -> Self`
  - `GradeLevelRepo::insert(&self, level: &GradeLevel) -> sqlx::Result<()>`
  - `GradeLevelRepo::list_for_year(&self, tenant_id: Uuid, academic_year_id: Uuid) -> sqlx::Result<Vec<GradeLevel>>`
  - `GradeLevelRepo::find_by_id(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<Option<GradeLevel>>`
  - `GradeLevelRepo::update(&self, tenant_id: Uuid, id: Uuid, code: &str, label: &str, ordinal: i32, is_final: bool) -> sqlx::Result<u64>`
  - `GradeLevelRepo::delete(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<u64>`
  - `GradeLevelRepo::find_final(&self, tenant_id: Uuid, academic_year_id: Uuid) -> sqlx::Result<Option<GradeLevel>>`
  - `GradeLevelRepo::count_templates_using(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<i64>`
  - `AppState.grade_level_repo: GradeLevelRepo`

Listing is intentionally **unpaginated** — a school has at most ~13 grade
levels, and the reorder UI needs them all at once. This differs from
`class_template` on purpose.

- [ ] **Step 1: Write the failing test**

Add to `tests/integration.rs`:

```rust
#[tokio::test]
async fn grade_level_repo_round_trips() {
    use academic_config_service::domain::GradeLevel;

    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let other_tenant = uuid::Uuid::new_v4();
    let year_id = seed_year_row(&pool, tenant_id, "2026/2027").await;

    let now = chrono::Utc::now();
    let level = GradeLevel {
        grade_level_id: uuid::Uuid::new_v4(),
        tenant_id,
        academic_year_id: year_id,
        code: "X".to_string(),
        label: "Kelas X".to_string(),
        ordinal: 1,
        is_final: false,
        created_at: now,
        updated_at: now,
    };
    state.grade_level_repo.insert(&level).await.expect("insert");

    let listed = state
        .grade_level_repo
        .list_for_year(tenant_id, year_id)
        .await
        .expect("list");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].code, "X");
    assert_eq!(listed[0].ordinal, 1);

    // find_final returns None until one is marked
    assert!(state
        .grade_level_repo
        .find_final(tenant_id, year_id)
        .await
        .expect("find_final")
        .is_none());

    let affected = state
        .grade_level_repo
        .update(tenant_id, level.grade_level_id, "XII", "Kelas XII", 3, true)
        .await
        .expect("update");
    assert_eq!(affected, 1);

    let found = state
        .grade_level_repo
        .find_final(tenant_id, year_id)
        .await
        .expect("find_final")
        .expect("a final level exists");
    assert_eq!(found.code, "XII");
    assert!(found.is_final);

    // tenant isolation: another tenant sees nothing and cannot update
    assert!(state
        .grade_level_repo
        .find_by_id(other_tenant, level.grade_level_id)
        .await
        .expect("find_by_id")
        .is_none());
    let cross = state
        .grade_level_repo
        .update(other_tenant, level.grade_level_id, "Z", "Z", 9, false)
        .await
        .expect("cross-tenant update");
    assert_eq!(cross, 0, "cross-tenant update must affect zero rows");

    let deleted = state
        .grade_level_repo
        .delete(tenant_id, level.grade_level_id)
        .await
        .expect("delete");
    assert_eq!(deleted, 1);
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_repo_round_trips -- --nocapture
```

Expected: FAIL to compile — `GradeLevel` and `grade_level_repo` do not exist.

- [ ] **Step 3: Add the domain type**

Append to `src/domain.rs`, next to `ClassTemplate` (around line 244, before the `#[cfg(test)] mod tests` block):

```rust
/// An ordered grade level within one academic year.
///
/// `ordinal` is what makes promotion computable: the next grade level is
/// simply `ordinal + 1`. `is_final` marks the terminal grade, whose students
/// graduate rather than advance.
#[derive(Debug, Clone, Serialize)]
pub struct GradeLevel {
    pub grade_level_id: Uuid,
    pub tenant_id: Uuid,
    pub academic_year_id: Uuid,
    pub code: String,
    pub label: String,
    pub ordinal: i32,
    pub is_final: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
```

- [ ] **Step 4: Add the repository**

Append to `src/repo.rs`, following the `ClassTemplateRepo` pattern:

```rust
#[derive(Clone)]
pub struct GradeLevelRepo {
    pool: PgPool,
}

const GRADE_LEVEL_COLUMNS: &str = "grade_level_id, tenant_id, academic_year_id, code, label, \
                                   ordinal, is_final, created_at, updated_at";

fn map_grade_level(row: sqlx::postgres::PgRow) -> GradeLevel {
    GradeLevel {
        grade_level_id: row.get("grade_level_id"),
        tenant_id: row.get("tenant_id"),
        academic_year_id: row.get("academic_year_id"),
        code: row.get("code"),
        label: row.get("label"),
        ordinal: row.get("ordinal"),
        is_final: row.get("is_final"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
    }
}

impl GradeLevelRepo {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn insert(&self, level: &GradeLevel) -> sqlx::Result<()> {
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
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Unpaginated on purpose: a school has at most ~13 grade levels and the
    /// reorder UI needs the whole ladder at once.
    pub async fn list_for_year(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
    ) -> sqlx::Result<Vec<GradeLevel>> {
        let rows = sqlx::query(&format!(
            r#"SELECT {GRADE_LEVEL_COLUMNS}
                 FROM grade_level
                WHERE tenant_id = $1 AND academic_year_id = $2
                ORDER BY ordinal"#
        ))
        .bind(tenant_id)
        .bind(academic_year_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.into_iter().map(map_grade_level).collect())
    }

    pub async fn find_by_id(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<Option<GradeLevel>> {
        let row = sqlx::query(&format!(
            r#"SELECT {GRADE_LEVEL_COLUMNS}
                 FROM grade_level
                WHERE tenant_id = $1 AND grade_level_id = $2"#
        ))
        .bind(tenant_id)
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(map_grade_level))
    }

    /// The terminal grade level for a year, if one has been marked.
    pub async fn find_final(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
    ) -> sqlx::Result<Option<GradeLevel>> {
        let row = sqlx::query(&format!(
            r#"SELECT {GRADE_LEVEL_COLUMNS}
                 FROM grade_level
                WHERE tenant_id = $1 AND academic_year_id = $2 AND is_final = TRUE"#
        ))
        .bind(tenant_id)
        .bind(academic_year_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(map_grade_level))
    }

    pub async fn update(
        &self,
        tenant_id: Uuid,
        id: Uuid,
        code: &str,
        label: &str,
        ordinal: i32,
        is_final: bool,
    ) -> sqlx::Result<u64> {
        let result = sqlx::query(
            r#"UPDATE grade_level
                  SET code = $3, label = $4, ordinal = $5, is_final = $6, updated_at = NOW()
                WHERE tenant_id = $1 AND grade_level_id = $2"#,
        )
        .bind(tenant_id)
        .bind(id)
        .bind(code)
        .bind(label)
        .bind(ordinal)
        .bind(is_final)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected())
    }

    pub async fn delete(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<u64> {
        let result =
            sqlx::query(r#"DELETE FROM grade_level WHERE tenant_id = $1 AND grade_level_id = $2"#)
                .bind(tenant_id)
                .bind(id)
                .execute(&self.pool)
                .await?;
        Ok(result.rows_affected())
    }

    /// How many class templates still point at this grade level. Used to
    /// refuse a delete that would orphan them.
    pub async fn count_templates_using(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<i64> {
        sqlx::query_scalar(
            r#"SELECT COUNT(*) FROM class_template
                WHERE tenant_id = $1 AND grade_level_id = $2"#,
        )
        .bind(tenant_id)
        .bind(id)
        .fetch_one(&self.pool)
        .await
    }
}
```

Add `GradeLevel` to the `use crate::domain::{...}` import list at the top of `repo.rs`.

- [ ] **Step 5: Wire it into `AppState`**

In `src/state.rs`, add `GradeLevelRepo` to the `use crate::repo::{...}` list, add the field, and initialise it:

```rust
// in the struct
pub grade_level_repo: GradeLevelRepo,

// in AppState::new, next to class_template_repo
grade_level_repo: GradeLevelRepo::new(pool.clone()),
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_repo_round_trips -- --nocapture
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/services/academic-config-service/src/domain.rs \
        apps/backend/services/academic-config-service/src/repo.rs \
        apps/backend/services/academic-config-service/src/state.rs \
        apps/backend/services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): add GradeLevel domain type and repository"
```

---

## Task 4: Commands, queries and HTTP endpoints

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/commands.rs`
- Modify: `apps/backend/services/academic-config-service/src/queries.rs`
- Modify: `apps/backend/services/academic-config-service/src/http.rs`
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: `GradeLevelRepo` (Task 3), `ensure_year_exists`, `validate_name`, `validation` (existing in `commands.rs`), `require_academic_config_write` / `require_academic_config_read` (existing in `http.rs`).
- Produces these routes:

| Method | Path |
|---|---|
| POST | `/api/v1/academic-config/academic-years/:academic_year_id/grade-levels` |
| GET | `/api/v1/academic-config/academic-years/:academic_year_id/grade-levels` |
| PATCH | `/api/v1/academic-config/grade-levels/:grade_level_id` |
| DELETE | `/api/v1/academic-config/grade-levels/:grade_level_id` |
| PUT | `/api/v1/academic-config/academic-years/:academic_year_id/grade-levels/order` |

- Produces command signatures:
  - `commands::AddGradeLevel { tenant_id, academic_year_id, code, label, ordinal, is_final }`
  - `commands::add_grade_level(&AppState, AddGradeLevel) -> Result<GradeLevel, AppError>`
  - `commands::UpdateGradeLevel { tenant_id, grade_level_id, code, label, ordinal, is_final }`
  - `commands::update_grade_level(&AppState, UpdateGradeLevel) -> Result<GradeLevel, AppError>`
  - `commands::delete_grade_level(&AppState, tenant_id: Uuid, grade_level_id: Uuid) -> Result<(), AppError>`
  - `commands::ReorderGradeLevels { tenant_id, academic_year_id, ordered_ids: Vec<Uuid> }`
  - `commands::reorder_grade_levels(&AppState, ReorderGradeLevels) -> Result<Vec<GradeLevel>, AppError>`
  - `queries::list_grade_levels(&AppState, tenant_id: Uuid, academic_year_id: Uuid) -> Result<Vec<GradeLevel>, AppError>`

- [ ] **Step 1: Write the failing test — create and list**

```rust
async fn create_grade_level(
    app: &axum::Router,
    token: &str,
    year_id: uuid::Uuid,
    code: &str,
    label: &str,
    ordinal: i32,
    is_final: bool,
) -> axum::response::Response {
    app.clone()
        .oneshot(json_request(
            "POST",
            &format!("/api/v1/academic-config/academic-years/{year_id}/grade-levels"),
            token,
            json!({
                "code": code,
                "label": label,
                "ordinal": ordinal,
                "is_final": is_final
            }),
        ))
        .await
        .unwrap()
}

#[tokio::test]
async fn grade_level_create_and_list() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let resp = create_grade_level(&app, &token, year_id, "X", "Kelas X", 1, false).await;
    assert_eq!(resp.status(), StatusCode::CREATED);
    let body = body_to_json(resp).await;
    assert_eq!(body["data"]["code"], "X");
    assert_eq!(body["data"]["ordinal"], 1);
    assert_eq!(body["data"]["is_final"], false);

    let resp = create_grade_level(&app, &token, year_id, "XII", "Kelas XII", 3, true).await;
    assert_eq!(resp.status(), StatusCode::CREATED);

    let resp = app
        .clone()
        .oneshot(get_request(
            &format!("/api/v1/academic-config/academic-years/{year_id}/grade-levels"),
            &token,
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = body_to_json(resp).await;
    let data = body["data"].as_array().expect("array");
    assert_eq!(data.len(), 2);
    assert_eq!(data[0]["code"], "X", "must be ordered by ordinal");
    assert_eq!(data[1]["code"], "XII");
}
```

`json_request`, `get_request`, `delete_request`, `create_year` and
`seed_active_subscription` already exist in `tests/integration.rs` — reuse
them, do not redefine them.

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_create_and_list -- --nocapture
```

Expected: FAIL — 404, the route does not exist.

- [ ] **Step 3: Write the commands**

Append to `src/commands.rs`, after `add_class_template`:

```rust
// ----------------------------------------------------------------------------
// Grade levels. Ordered ladder of grades within one academic year; the
// foundation promotion uses to compute "next grade" and detect graduation.
// ----------------------------------------------------------------------------

pub struct AddGradeLevel {
    pub tenant_id: Uuid,
    pub academic_year_id: Uuid,
    pub code: String,
    pub label: String,
    pub ordinal: i32,
    pub is_final: bool,
}

pub async fn add_grade_level(
    state: &AppState,
    input: AddGradeLevel,
) -> Result<GradeLevel, AppError> {
    validate_name("code", &input.code)?;
    validate_name("label", &input.label)?;
    validate_position("ordinal", input.ordinal)?;
    ensure_year_exists(state, input.tenant_id, input.academic_year_id).await?;

    if input.is_final {
        ensure_no_other_final(state, input.tenant_id, input.academic_year_id, None).await?;
    }

    let now = Utc::now();
    let level = GradeLevel {
        grade_level_id: Uuid::new_v4(),
        tenant_id: input.tenant_id,
        academic_year_id: input.academic_year_id,
        code: input.code.trim().to_string(),
        label: input.label.trim().to_string(),
        ordinal: input.ordinal,
        is_final: input.is_final,
        created_at: now,
        updated_at: now,
    };

    state
        .grade_level_repo
        .insert(&level)
        .await
        .map_err(map_grade_level_conflict)?;
    Ok(level)
}

pub struct UpdateGradeLevel {
    pub tenant_id: Uuid,
    pub grade_level_id: Uuid,
    pub code: String,
    pub label: String,
    pub ordinal: i32,
    pub is_final: bool,
}

pub async fn update_grade_level(
    state: &AppState,
    input: UpdateGradeLevel,
) -> Result<GradeLevel, AppError> {
    validate_name("code", &input.code)?;
    validate_name("label", &input.label)?;
    validate_position("ordinal", input.ordinal)?;

    let existing = state
        .grade_level_repo
        .find_by_id(input.tenant_id, input.grade_level_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("grade level"))?;

    if input.is_final {
        ensure_no_other_final(
            state,
            input.tenant_id,
            existing.academic_year_id,
            Some(input.grade_level_id),
        )
        .await?;
    }

    state
        .grade_level_repo
        .update(
            input.tenant_id,
            input.grade_level_id,
            input.code.trim(),
            input.label.trim(),
            input.ordinal,
            input.is_final,
        )
        .await
        .map_err(map_grade_level_conflict)?;

    Ok(GradeLevel {
        code: input.code.trim().to_string(),
        label: input.label.trim().to_string(),
        ordinal: input.ordinal,
        is_final: input.is_final,
        updated_at: Utc::now(),
        ..existing
    })
}

pub async fn delete_grade_level(
    state: &AppState,
    tenant_id: Uuid,
    grade_level_id: Uuid,
) -> Result<(), AppError> {
    state
        .grade_level_repo
        .find_by_id(tenant_id, grade_level_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("grade level"))?;

    let in_use = state
        .grade_level_repo
        .count_templates_using(tenant_id, grade_level_id)
        .await
        .map_err(AppError::internal)?;
    if in_use > 0 {
        return Err(AppError::conflict(
            "GRADE_LEVEL_IN_USE",
            "grade level is still referenced by class templates",
        ));
    }

    state
        .grade_level_repo
        .delete(tenant_id, grade_level_id)
        .await
        .map_err(AppError::internal)?;
    Ok(())
}

pub struct ReorderGradeLevels {
    pub tenant_id: Uuid,
    pub academic_year_id: Uuid,
    /// Grade level ids in their new order; position in this vec becomes the
    /// new `ordinal` (1-based).
    pub ordered_ids: Vec<Uuid>,
}

pub async fn reorder_grade_levels(
    state: &AppState,
    input: ReorderGradeLevels,
) -> Result<Vec<GradeLevel>, AppError> {
    let current = state
        .grade_level_repo
        .list_for_year(input.tenant_id, input.academic_year_id)
        .await
        .map_err(AppError::internal)?;

    if current.len() != input.ordered_ids.len() {
        return Err(validation(
            "ordered_ids",
            "must list every grade level in the academic year exactly once",
        ));
    }
    let known: std::collections::BTreeSet<Uuid> =
        current.iter().map(|l| l.grade_level_id).collect();
    let submitted: std::collections::BTreeSet<Uuid> = input.ordered_ids.iter().copied().collect();
    if known != submitted {
        return Err(validation(
            "ordered_ids",
            "must list every grade level in the academic year exactly once",
        ));
    }

    // Two-phase to dodge the (tenant_id, academic_year_id, ordinal) unique
    // constraint: park every row at a negative ordinal, then assign finals.
    // A single transaction so a failure leaves the ladder untouched.
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    for (idx, id) in input.ordered_ids.iter().enumerate() {
        sqlx::query(
            r#"UPDATE grade_level SET ordinal = $3
                WHERE tenant_id = $1 AND grade_level_id = $2"#,
        )
        .bind(input.tenant_id)
        .bind(id)
        .bind(-(idx as i32 + 1))
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    }
    for (idx, id) in input.ordered_ids.iter().enumerate() {
        sqlx::query(
            r#"UPDATE grade_level SET ordinal = $3, updated_at = NOW()
                WHERE tenant_id = $1 AND grade_level_id = $2"#,
        )
        .bind(input.tenant_id)
        .bind(id)
        .bind(idx as i32 + 1)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    }
    tx.commit().await.map_err(AppError::internal)?;

    state
        .grade_level_repo
        .list_for_year(input.tenant_id, input.academic_year_id)
        .await
        .map_err(AppError::internal)
}

/// Refuses a second `is_final` in the same academic year. `skip` excludes the
/// row being updated so re-saving the existing final level is not a conflict.
async fn ensure_no_other_final(
    state: &AppState,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    skip: Option<Uuid>,
) -> Result<(), AppError> {
    if let Some(existing) = state
        .grade_level_repo
        .find_final(tenant_id, academic_year_id)
        .await
        .map_err(AppError::internal)?
    {
        if Some(existing.grade_level_id) != skip {
            return Err(validation(
                "is_final",
                "another grade level in this academic year is already marked as final",
            ));
        }
    }
    Ok(())
}

/// Turns the unique-index violations into 409s instead of 500s.
fn map_grade_level_conflict(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(ref db) = err {
        match db.constraint() {
            Some("grade_level_code_unique") => {
                return AppError::conflict(
                    "GRADE_LEVEL_CODE_TAKEN",
                    "a grade level with this code already exists in the academic year",
                )
            }
            Some("grade_level_ordinal_unique") => {
                return AppError::conflict(
                    "GRADE_LEVEL_ORDINAL_TAKEN",
                    "a grade level with this ordinal already exists in the academic year",
                )
            }
            _ => {}
        }
    }
    AppError::internal(err)
}
```

Add `GradeLevel` to the `use crate::domain::{...}` import list in `commands.rs`.

- [ ] **Step 4: Write the query**

Append to `src/queries.rs`:

```rust
/// Unpaginated: the reorder UI needs the entire ladder in one response.
pub async fn list_grade_levels(
    state: &AppState,
    tenant_id: Uuid,
    academic_year_id: Uuid,
) -> Result<Vec<GradeLevel>, AppError> {
    state
        .grade_level_repo
        .list_for_year(tenant_id, academic_year_id)
        .await
        .map_err(AppError::internal)
}
```

Add `GradeLevel` to the `use crate::domain::{...}` import list and `use uuid::Uuid;` if not already present.

- [ ] **Step 5: Write the HTTP handlers**

Append to `src/http.rs`:

```rust
#[derive(Debug, Deserialize)]
struct AddGradeLevelBody {
    code: String,
    label: String,
    ordinal: i32,
    #[serde(default)]
    is_final: bool,
}

async fn add_grade_level(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicConfigEntitlement,
    Path(academic_year_id): Path<Uuid>,
    Json(body): Json<AddGradeLevelBody>,
) -> Result<(StatusCode, Json<Value>), AppError> {
    require_academic_config_write(&auth)?;
    let level = commands::add_grade_level(
        &state,
        commands::AddGradeLevel {
            tenant_id: auth.tenant_id,
            academic_year_id,
            code: body.code,
            label: body.label,
            ordinal: body.ordinal,
            is_final: body.is_final,
        },
    )
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(json!({ "data": level, "meta": {} })),
    ))
}

async fn list_grade_levels(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicConfigEntitlement,
    Path(academic_year_id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    require_academic_config_read(&auth)?;
    let levels = queries::list_grade_levels(&state, auth.tenant_id, academic_year_id).await?;
    Ok(Json(json!({ "data": levels, "meta": {} })))
}

#[derive(Debug, Deserialize)]
struct UpdateGradeLevelBody {
    code: String,
    label: String,
    ordinal: i32,
    #[serde(default)]
    is_final: bool,
}

async fn update_grade_level(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicConfigEntitlement,
    Path(grade_level_id): Path<Uuid>,
    Json(body): Json<UpdateGradeLevelBody>,
) -> Result<Json<Value>, AppError> {
    require_academic_config_write(&auth)?;
    let level = commands::update_grade_level(
        &state,
        commands::UpdateGradeLevel {
            tenant_id: auth.tenant_id,
            grade_level_id,
            code: body.code,
            label: body.label,
            ordinal: body.ordinal,
            is_final: body.is_final,
        },
    )
    .await?;
    Ok(Json(json!({ "data": level, "meta": {} })))
}

async fn delete_grade_level(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicConfigEntitlement,
    Path(grade_level_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    require_academic_config_write(&auth)?;
    commands::delete_grade_level(&state, auth.tenant_id, grade_level_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct ReorderGradeLevelsBody {
    ordered_ids: Vec<Uuid>,
}

async fn reorder_grade_levels(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicConfigEntitlement,
    Path(academic_year_id): Path<Uuid>,
    Json(body): Json<ReorderGradeLevelsBody>,
) -> Result<Json<Value>, AppError> {
    require_academic_config_write(&auth)?;
    let levels = commands::reorder_grade_levels(
        &state,
        commands::ReorderGradeLevels {
            tenant_id: auth.tenant_id,
            academic_year_id,
            ordered_ids: body.ordered_ids,
        },
    )
    .await?;
    Ok(Json(json!({ "data": levels, "meta": {} })))
}
```

- [ ] **Step 6: Register the routes**

In `src/http.rs`, inside `pub fn router(state: AppState) -> Router`, add before `.with_state(state)`:

```rust
        .route(
            "/api/v1/academic-config/academic-years/:academic_year_id/grade-levels",
            post(add_grade_level).get(list_grade_levels),
        )
        .route(
            "/api/v1/academic-config/academic-years/:academic_year_id/grade-levels/order",
            put(reorder_grade_levels),
        )
        .route(
            "/api/v1/academic-config/grade-levels/:grade_level_id",
            patch(update_grade_level).delete(delete_grade_level),
        )
```

Add `put` to the `use axum::routing::{...}` import list.

- [ ] **Step 7: Run the test to verify it passes**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration grade_level_create_and_list -- --nocapture
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/services/academic-config-service/src/commands.rs \
        apps/backend/services/academic-config-service/src/queries.rs \
        apps/backend/services/academic-config-service/src/http.rs \
        apps/backend/services/academic-config-service/tests/integration.rs
git commit -m "feat(academic-config): add grade level CRUD endpoints"
```

- [ ] **Step 9: Write the failing test — a second `is_final` is rejected** *(Review Focus #1)*

```rust
#[tokio::test]
async fn second_final_grade_level_is_rejected() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let resp = create_grade_level(&app, &token, year_id, "XII", "Kelas XII", 3, true).await;
    assert_eq!(resp.status(), StatusCode::CREATED);

    // A second final level in the same year would graduate the wrong cohort.
    let resp = create_grade_level(&app, &token, year_id, "XI", "Kelas XI", 2, true).await;
    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let body = body_to_json(resp).await;
    assert_eq!(body["error"]["code"], "VALIDATION_ERROR");
    assert!(body["error"]["fields"]["is_final"].is_array());
}

#[tokio::test]
async fn resaving_the_same_final_grade_level_is_allowed() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let resp = create_grade_level(&app, &token, year_id, "XII", "Kelas XII", 3, true).await;
    let level_id: uuid::Uuid = body_to_json(resp).await["data"]["grade_level_id"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();

    // Editing the label of the existing final level must not trip the guard.
    let resp = app
        .clone()
        .oneshot(json_request(
            "PATCH",
            &format!("/api/v1/academic-config/grade-levels/{level_id}"),
            &token,
            json!({ "code": "XII", "label": "Kelas 12", "ordinal": 3, "is_final": true }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(body_to_json(resp).await["data"]["label"], "Kelas 12");
}
```

- [ ] **Step 10: Run both**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration final_grade_level -- --nocapture
```

Expected: PASS (the guard was written in Step 3).

- [ ] **Step 11: Write the failing test — reorder**

```rust
#[tokio::test]
async fn reorder_rewrites_ordinals_contiguously() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let mut ids = Vec::new();
    for (code, ordinal) in [("X", 1), ("XI", 2), ("XII", 3)] {
        let resp = create_grade_level(&app, &token, year_id, code, code, ordinal, false).await;
        ids.push(
            body_to_json(resp).await["data"]["grade_level_id"]
                .as_str()
                .unwrap()
                .parse::<uuid::Uuid>()
                .unwrap(),
        );
    }

    // Reverse the ladder. The swap passes through ordinals that already exist,
    // so this also proves the two-phase update dodges the unique constraint.
    let reversed: Vec<uuid::Uuid> = ids.iter().rev().copied().collect();
    let resp = app
        .clone()
        .oneshot(json_request(
            "PUT",
            &format!("/api/v1/academic-config/academic-years/{year_id}/grade-levels/order"),
            &token,
            json!({ "ordered_ids": reversed }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = body_to_json(resp).await;
    let data = body["data"].as_array().unwrap();
    assert_eq!(data[0]["code"], "XII");
    assert_eq!(data[0]["ordinal"], 1);
    assert_eq!(data[2]["code"], "X");
    assert_eq!(data[2]["ordinal"], 3);
}

#[tokio::test]
async fn reorder_with_incomplete_id_list_is_rejected() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let resp = create_grade_level(&app, &token, year_id, "X", "Kelas X", 1, false).await;
    let first: uuid::Uuid = body_to_json(resp).await["data"]["grade_level_id"]
        .as_str().unwrap().parse().unwrap();
    create_grade_level(&app, &token, year_id, "XI", "Kelas XI", 2, false).await;

    // Only one of two ids — a partial reorder would leave a gap.
    let resp = app
        .clone()
        .oneshot(json_request(
            "PUT",
            &format!("/api/v1/academic-config/academic-years/{year_id}/grade-levels/order"),
            &token,
            json!({ "ordered_ids": [first] }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body_to_json(resp).await["error"]["code"], "VALIDATION_ERROR");
}
```

- [ ] **Step 12: Run them**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration reorder_ -- --nocapture
```

Expected: PASS.

- [ ] **Step 13: Write the failing test — duplicate ordinal is a 409, not a 500** *(Review Focus #2)*

```rust
#[tokio::test]
async fn duplicate_ordinal_returns_conflict_not_internal_error() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    create_grade_level(&app, &token, year_id, "X", "Kelas X", 1, false).await;

    let resp = create_grade_level(&app, &token, year_id, "XI", "Kelas XI", 1, false).await;
    assert_eq!(resp.status(), StatusCode::CONFLICT);
    assert_eq!(
        body_to_json(resp).await["error"]["code"],
        "GRADE_LEVEL_ORDINAL_TAKEN"
    );
}

#[tokio::test]
async fn duplicate_code_returns_conflict() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    create_grade_level(&app, &token, year_id, "X", "Kelas X", 1, false).await;

    let resp = create_grade_level(&app, &token, year_id, "X", "Kelas X lain", 2, false).await;
    assert_eq!(resp.status(), StatusCode::CONFLICT);
    assert_eq!(
        body_to_json(resp).await["error"]["code"],
        "GRADE_LEVEL_CODE_TAKEN"
    );
}
```

- [ ] **Step 14: Run them**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration duplicate_ -- --nocapture
```

Expected: PASS (`map_grade_level_conflict` from Step 3 handles both).

- [ ] **Step 15: Write the failing test — cross-tenant access 404s** *(Review Focus #5)*

```rust
#[tokio::test]
async fn cross_tenant_grade_level_access_is_not_found() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let owner = uuid::Uuid::new_v4();
    let intruder = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, owner).await;
    seed_active_subscription(&pool, intruder).await;

    let owner_token = jwt_for(owner, "tenant_admin");
    let intruder_token = jwt_for(intruder, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());

    let year_id = create_year(&app, &owner_token).await;
    let resp = create_grade_level(&app, &owner_token, year_id, "X", "Kelas X", 1, false).await;
    let level_id: uuid::Uuid = body_to_json(resp).await["data"]["grade_level_id"]
        .as_str().unwrap().parse().unwrap();

    // Update from the wrong tenant
    let resp = app
        .clone()
        .oneshot(json_request(
            "PATCH",
            &format!("/api/v1/academic-config/grade-levels/{level_id}"),
            &intruder_token,
            json!({ "code": "HACK", "label": "HACK", "ordinal": 1, "is_final": false }),
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // Delete from the wrong tenant
    let resp = app
        .clone()
        .oneshot(delete_request(
            &format!("/api/v1/academic-config/grade-levels/{level_id}"),
            &intruder_token,
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // The row is untouched.
    let resp = app
        .clone()
        .oneshot(get_request(
            &format!("/api/v1/academic-config/academic-years/{year_id}/grade-levels"),
            &owner_token,
        ))
        .await
        .unwrap();
    let body = body_to_json(resp).await;
    assert_eq!(body["data"][0]["code"], "X");
}
```

- [ ] **Step 16: Run it**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration cross_tenant_grade_level -- --nocapture
```

Expected: PASS.

- [ ] **Step 17: Write the failing test — delete guarded by usage**

```rust
#[tokio::test]
async fn delete_grade_level_in_use_is_rejected() {
    let (pool, state, _rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let token = jwt_for(tenant_id, "tenant_admin");
    let app = academic_config_service::http::router(state.clone());
    let year_id = create_year(&app, &token).await;

    let resp = create_grade_level(&app, &token, year_id, "X", "Kelas X", 1, false).await;
    let level_id: uuid::Uuid = body_to_json(resp).await["data"]["grade_level_id"]
        .as_str().unwrap().parse().unwrap();

    let template_id = seed_class_template_row(&pool, tenant_id, year_id, "X", 30).await;
    sqlx::query("UPDATE class_template SET grade_level_id = $1 WHERE template_id = $2")
        .bind(level_id)
        .bind(template_id)
        .execute(&pool)
        .await
        .expect("link template to grade level");

    let resp = app
        .clone()
        .oneshot(delete_request(
            &format!("/api/v1/academic-config/grade-levels/{level_id}"),
            &token,
        ))
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CONFLICT);
    assert_eq!(body_to_json(resp).await["error"]["code"], "GRADE_LEVEL_IN_USE");
}
```

- [ ] **Step 18: Run it, then run the whole suite**

```bash
cd apps/backend
cargo test -p academic-config-service --test integration delete_grade_level_in_use -- --nocapture
cargo test -p academic-config-service
```

Expected: all PASS.

- [ ] **Step 19: Commit**

```bash
git add apps/backend/services/academic-config-service/tests/integration.rs
git commit -m "test(academic-config): cover grade level guards, reorder and tenant isolation"
```

---

## Task 5: Web data layer

**Files:**
- Create: `apps/web/src/lib/schemas/grade-level.ts`
- Modify: `apps/web/src/lib/query/queries/use-academic-config.ts`
- Modify: `apps/web/src/lib/query/mutations/use-academic-config.ts`
- Test: `apps/web/__tests__/schemas.test.ts`

**Interfaces:**
- Consumes: the endpoints from Task 4; existing `apiFetch`, `apiFetchEnvelope`, `buildQuery` helpers in those files.
- Produces:
  - `type GradeLevel = { grade_level_id: string; tenant_id: string; academic_year_id: string; code: string; label: string; ordinal: number; is_final: boolean; created_at: string; updated_at: string }`
  - `GRADE_LEVELS_QUERY_KEY`
  - `useGradeLevels(academicYearId?: string)` → `UseQueryResult<GradeLevel[]>`
  - `useAddGradeLevel(academicYearId: string)`, `useUpdateGradeLevel(gradeLevelId: string)`, `useDeleteGradeLevel()`, `useReorderGradeLevels(academicYearId: string)`
  - `gradeLevelSchema`, `type GradeLevelForm`

- [ ] **Step 1: Write the failing test**

Add to `apps/web/__tests__/schemas.test.ts`:

```ts
import { gradeLevelSchema } from "@/lib/schemas/grade-level";

describe("gradeLevelSchema", () => {
  it("accepts a well-formed grade level", () => {
    const parsed = gradeLevelSchema.safeParse({
      academic_year_id: "0b5f3e1a-1111-4111-8111-111111111111",
      code: "X",
      label: "Kelas X",
      ordinal: 1,
      is_final: false,
    });
    expect(parsed.success).toBe(true);
  });

  it("rejects an empty code", () => {
    const parsed = gradeLevelSchema.safeParse({
      academic_year_id: "0b5f3e1a-1111-4111-8111-111111111111",
      code: "",
      label: "Kelas X",
      ordinal: 1,
      is_final: false,
    });
    expect(parsed.success).toBe(false);
  });

  it("rejects ordinal below 1", () => {
    const parsed = gradeLevelSchema.safeParse({
      academic_year_id: "0b5f3e1a-1111-4111-8111-111111111111",
      code: "X",
      label: "Kelas X",
      ordinal: 0,
      is_final: false,
    });
    expect(parsed.success).toBe(false);
  });

  it("coerces a numeric string ordinal from the form input", () => {
    const parsed = gradeLevelSchema.safeParse({
      academic_year_id: "0b5f3e1a-1111-4111-8111-111111111111",
      code: "X",
      label: "Kelas X",
      ordinal: "2",
      is_final: false,
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.ordinal).toBe(2);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/web
pnpm test:unit -- schemas
```

Expected: FAIL — cannot resolve `@/lib/schemas/grade-level`.

- [ ] **Step 3: Write the schema**

Create `apps/web/src/lib/schemas/grade-level.ts`:

```ts
import { z } from "zod";

export const gradeLevelSchema = z.object({
  academic_year_id: z.string().uuid("Pilih tahun ajaran terlebih dahulu"),
  code: z.string().min(1, "Kode tingkat wajib diisi").max(32, "Maksimal 32 karakter"),
  label: z.string().min(1, "Nama tingkat wajib diisi").max(64, "Maksimal 64 karakter"),
  ordinal: z.coerce.number().int().min(1, "Urutan minimal 1"),
  is_final: z.boolean().default(false),
});

export type GradeLevelForm = z.infer<typeof gradeLevelSchema>;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd apps/web
pnpm test:unit -- schemas
```

Expected: PASS.

- [ ] **Step 5: Add the query hook**

In `apps/web/src/lib/query/queries/use-academic-config.ts`, add the type next to `ClassTemplate`:

```ts
export type GradeLevel = {
  grade_level_id: string;
  tenant_id: string;
  academic_year_id: string;
  code: string;
  label: string;
  ordinal: number;
  is_final: boolean;
  created_at: string;
  updated_at: string;
};
```

Add the query key next to `CLASS_TEMPLATES_QUERY_KEY`:

```ts
export const GRADE_LEVELS_QUERY_KEY = ["academic-config", "grade-levels"] as const;
```

Add the hook at the end of the file:

```ts
/**
 * Grade levels for one academic year, ordered by `ordinal`.
 *
 * Unpaginated by design — the backend returns the whole ladder (a school has
 * at most ~13 levels) because the reorder UI needs every row at once.
 */
export function useGradeLevels(academicYearId?: string) {
  return useQuery({
    queryKey: [...GRADE_LEVELS_QUERY_KEY, academicYearId ?? ""],
    queryFn: async () => {
      const envelope = await apiFetchEnvelope<GradeLevel[]>({
        service: "academic-config",
        path: `/api/v1/academic-config/academic-years/${academicYearId}/grade-levels`,
        authenticated: true,
      });
      return envelope.data;
    },
    enabled: Boolean(academicYearId),
  });
}
```

- [ ] **Step 6: Add the mutation hooks**

In `apps/web/src/lib/query/mutations/use-academic-config.ts`, add `GradeLevel` and `GRADE_LEVELS_QUERY_KEY` to the import from the queries file, add `import type { GradeLevelForm } from "@/lib/schemas/grade-level";`, then append:

```ts
// ---------------------------------------------------------------------------
// Grade levels
// ---------------------------------------------------------------------------

export function useAddGradeLevel(academicYearId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: Omit<GradeLevelForm, "academic_year_id">) =>
      apiFetch<GradeLevel>({
        service: "academic-config",
        path: `/api/v1/academic-config/academic-years/${academicYearId}/grade-levels`,
        method: "POST",
        authenticated: true,
        body: input,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: GRADE_LEVELS_QUERY_KEY }),
  });
}

export function useUpdateGradeLevel(gradeLevelId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: Omit<GradeLevelForm, "academic_year_id">) =>
      apiFetch<GradeLevel>({
        service: "academic-config",
        path: `/api/v1/academic-config/grade-levels/${gradeLevelId}`,
        method: "PATCH",
        authenticated: true,
        body: input,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: GRADE_LEVELS_QUERY_KEY }),
  });
}

export function useDeleteGradeLevel() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (gradeLevelId: string) =>
      apiFetch<void>({
        service: "academic-config",
        path: `/api/v1/academic-config/grade-levels/${gradeLevelId}`,
        method: "DELETE",
        authenticated: true,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: GRADE_LEVELS_QUERY_KEY }),
  });
}

export function useReorderGradeLevels(academicYearId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (orderedIds: string[]) =>
      apiFetch<GradeLevel[]>({
        service: "academic-config",
        path: `/api/v1/academic-config/academic-years/${academicYearId}/grade-levels/order`,
        method: "PUT",
        authenticated: true,
        body: { ordered_ids: orderedIds },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: GRADE_LEVELS_QUERY_KEY }),
  });
}
```

- [ ] **Step 7: Typecheck and commit**

```bash
cd apps/web
pnpm typecheck
pnpm test:unit -- schemas
git add src/lib/schemas/grade-level.ts \
        src/lib/query/queries/use-academic-config.ts \
        src/lib/query/mutations/use-academic-config.ts \
        __tests__/schemas.test.ts
git commit -m "feat(web): add grade level schema, queries and mutations"
```

---

## Task 6: Grade levels page

**Files:**
- Create: `apps/web/src/app/settings/academic/grade-levels/page.tsx`
- Modify: `apps/web/src/components/features/academic-config/academic-settings.tsx`
- Test: `apps/web/__tests__/grade-levels-page.test.tsx`

**Interfaces:**
- Consumes: `useGradeLevels`, `useAddGradeLevel`, `useUpdateGradeLevel`, `useDeleteGradeLevel`, `useReorderGradeLevels` (Task 5); `AcademicSettingsPage` wrapper; `useAcademicScope` hook.
- Produces: route `/settings/academic/grade-levels`; a nav tab labelled `Tingkat Kelas`.

Reorder uses explicit **Move up / Move down** buttons rather than
drag-and-drop: it is keyboard accessible, testable without simulating
pointer events, and a school reorders its grade ladder roughly once.

- [ ] **Step 1: Write the failing test**

Create `apps/web/__tests__/grade-levels-page.test.tsx`:

```tsx
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it, vi, beforeEach } from "vitest";

import { GradeLevelsTable } from "@/app/settings/academic/grade-levels/page";

const levels = [
  {
    grade_level_id: "11111111-1111-4111-8111-111111111111",
    tenant_id: "t",
    academic_year_id: "y",
    code: "X",
    label: "Kelas X",
    ordinal: 1,
    is_final: false,
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T00:00:00Z",
  },
  {
    grade_level_id: "22222222-2222-4222-8222-222222222222",
    tenant_id: "t",
    academic_year_id: "y",
    code: "XII",
    label: "Kelas XII",
    ordinal: 2,
    is_final: true,
    created_at: "2026-07-01T00:00:00Z",
    updated_at: "2026-07-01T00:00:00Z",
  },
];

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

describe("GradeLevelsTable", () => {
  it("lists grade levels in ordinal order", () => {
    wrap(
      <GradeLevelsTable
        levels={levels}
        canEdit
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onReorder={vi.fn()}
      />,
    );
    const rows = screen.getAllByRole("row").slice(1); // skip header
    expect(rows[0]).toHaveTextContent("X");
    expect(rows[1]).toHaveTextContent("XII");
  });

  it("marks the final grade level", () => {
    wrap(
      <GradeLevelsTable
        levels={levels}
        canEdit
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onReorder={vi.fn()}
      />,
    );
    expect(screen.getByText("Tingkat akhir")).toBeInTheDocument();
  });

  it("moving a level down emits the reordered id list", async () => {
    const onReorder = vi.fn();
    wrap(
      <GradeLevelsTable
        levels={levels}
        canEdit
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onReorder={onReorder}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: /turunkan kelas x/i }));
    expect(onReorder).toHaveBeenCalledWith([
      "22222222-2222-4222-8222-222222222222",
      "11111111-1111-4111-8111-111111111111",
    ]);
  });

  it("hides mutating controls when the user cannot edit", () => {
    wrap(
      <GradeLevelsTable
        levels={levels}
        canEdit={false}
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onReorder={vi.fn()}
      />,
    );
    expect(screen.queryByRole("button", { name: /turunkan/i })).not.toBeInTheDocument();
  });

  it("shows an empty state when there are no grade levels", () => {
    wrap(
      <GradeLevelsTable
        levels={[]}
        canEdit
        onEdit={vi.fn()}
        onDelete={vi.fn()}
        onReorder={vi.fn()}
      />,
    );
    expect(screen.getByText(/belum ada tingkat kelas/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd apps/web
pnpm test:unit -- grade-levels-page
```

Expected: FAIL — module not found.

- [ ] **Step 3: Write the page**

Create `apps/web/src/app/settings/academic/grade-levels/page.tsx`. Export
`GradeLevelsTable` separately so the test can mount it without the data
layer:

```tsx
"use client";

import * as React from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowDown, ArrowUp, MoreHorizontal, Pencil, Plus, Trash2 } from "lucide-react";
import { useForm } from "react-hook-form";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Form, FormControl, FormField, FormItem, FormLabelRequired, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { toast } from "@/components/ui/toaster";
import { AcademicSettingsPage } from "@/components/features/academic-config/academic-settings";
import { getErrorMessage } from "@/lib/errors/messages";
import { applyServerFieldErrors } from "@/lib/forms/apply-server-field-errors";
import {
  useAddGradeLevel,
  useDeleteGradeLevel,
  useReorderGradeLevels,
  useUpdateGradeLevel,
} from "@/lib/query/mutations/use-academic-config";
import { type GradeLevel, useGradeLevels } from "@/lib/query/queries/use-academic-config";
import { gradeLevelSchema, type GradeLevelForm } from "@/lib/schemas/grade-level";
import { useAcademicScope } from "@/hooks/use-academic-scope";

/**
 * Presentational table. Reorder is exposed as explicit up/down buttons rather
 * than drag-and-drop: keyboard accessible, testable without pointer
 * simulation, and a school reorders its grade ladder about once.
 */
export function GradeLevelsTable({
  levels,
  canEdit,
  onEdit,
  onDelete,
  onReorder,
}: {
  levels: GradeLevel[];
  canEdit: boolean;
  onEdit: (level: GradeLevel) => void;
  onDelete: (level: GradeLevel) => void;
  onReorder: (orderedIds: string[]) => void;
}) {
  if (levels.length === 0) {
    return (
      <div className="py-10 text-center text-sm text-muted-foreground">
        Belum ada tingkat kelas. Tambahkan tingkat untuk tahun ajaran ini.
      </div>
    );
  }

  function move(index: number, delta: number) {
    const next = [...levels];
    const target = index + delta;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    onReorder(next.map((l) => l.grade_level_id));
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="w-16">Urutan</TableHead>
          <TableHead>Kode</TableHead>
          <TableHead>Nama</TableHead>
          <TableHead />
          {canEdit ? <TableHead className="w-32 text-right">Aksi</TableHead> : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {levels.map((level, index) => (
          <TableRow key={level.grade_level_id}>
            <TableCell className="tabular-nums">{level.ordinal}</TableCell>
            <TableCell className="font-semibold text-foreground">{level.code}</TableCell>
            <TableCell>{level.label}</TableCell>
            <TableCell>
              {level.is_final ? <Badge variant="secondary">Tingkat akhir</Badge> : null}
            </TableCell>
            {canEdit ? (
              <TableCell className="text-right">
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Naikkan ${level.label}`}
                  disabled={index === 0}
                  onClick={() => move(index, -1)}
                >
                  <ArrowUp className="h-4 w-4" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Turunkan ${level.label}`}
                  disabled={index === levels.length - 1}
                  onClick={() => move(index, 1)}
                >
                  <ArrowDown className="h-4 w-4" />
                </Button>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="ghost" size="icon" aria-label={`Menu ${level.label}`}>
                      <MoreHorizontal className="h-4 w-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuLabel>{level.label}</DropdownMenuLabel>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={() => onEdit(level)}>
                      <Pencil className="mr-2 h-4 w-4" /> Ubah
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      className="text-destructive"
                      onClick={() => onDelete(level)}
                    >
                      <Trash2 className="mr-2 h-4 w-4" /> Hapus
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </TableCell>
            ) : null}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export default function GradeLevelsPage() {
  return (
    <AcademicSettingsPage
      title="Tingkat Kelas"
      description="Urutan tingkat kelas menentukan kenaikan kelas dan menandai tingkat akhir yang meluluskan siswa."
    >
      {({ canManageAcademicConfig }) => (
        <GradeLevelsScreen canEdit={canManageAcademicConfig} />
      )}
    </AcademicSettingsPage>
  );
}

function GradeLevelsScreen({ canEdit }: { canEdit: boolean }) {
  const { yearId } = useAcademicScope();
  const academicYearId = yearId ?? undefined;
  const query = useGradeLevels(academicYearId);
  const reorder = useReorderGradeLevels(academicYearId ?? "");
  const remove = useDeleteGradeLevel();

  const [editing, setEditing] = React.useState<GradeLevel | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [deleting, setDeleting] = React.useState<GradeLevel | null>(null);

  const levels = query.data ?? [];

  function handleReorder(orderedIds: string[]) {
    reorder.mutate(orderedIds, {
      onError: (error) => toast.error(getErrorMessage(error)),
    });
  }

  function handleDelete() {
    if (!deleting) return;
    remove.mutate(deleting.grade_level_id, {
      onSuccess: () => {
        toast.success("Tingkat kelas dihapus");
        setDeleting(null);
      },
      onError: (error) => toast.error(getErrorMessage(error)),
    });
  }

  return (
    <Card>
      <CardContent className="space-y-4 pt-6">
        {canEdit ? (
          <div className="flex justify-end">
            <Button onClick={() => setCreating(true)} disabled={!academicYearId}>
              <Plus className="mr-2 h-4 w-4" /> Tambah Tingkat
            </Button>
          </div>
        ) : null}

        {query.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : (
          <GradeLevelsTable
            levels={levels}
            canEdit={canEdit}
            onEdit={setEditing}
            onDelete={setDeleting}
            onReorder={handleReorder}
          />
        )}
      </CardContent>

      {academicYearId ? (
        <GradeLevelDialog
          key={editing?.grade_level_id ?? "create"}
          open={creating || editing !== null}
          level={editing}
          academicYearId={academicYearId}
          nextOrdinal={levels.length + 1}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
        />
      ) : null}

      <ConfirmDialog
        open={deleting !== null}
        title="Hapus tingkat kelas?"
        description={`Tingkat ${deleting?.label ?? ""} akan dihapus.`}
        confirmLabel="Hapus"
        onConfirm={handleDelete}
        onOpenChange={(open) => {
          if (!open) setDeleting(null);
        }}
      />
    </Card>
  );
}

function GradeLevelDialog({
  open,
  level,
  academicYearId,
  nextOrdinal,
  onClose,
}: {
  open: boolean;
  level: GradeLevel | null;
  academicYearId: string;
  nextOrdinal: number;
  onClose: () => void;
}) {
  const add = useAddGradeLevel(academicYearId);
  const update = useUpdateGradeLevel(level?.grade_level_id ?? "");

  const form = useForm<GradeLevelForm>({
    resolver: zodResolver(gradeLevelSchema),
    defaultValues: {
      academic_year_id: academicYearId,
      code: level?.code ?? "",
      label: level?.label ?? "",
      ordinal: level?.ordinal ?? nextOrdinal,
      is_final: level?.is_final ?? false,
    },
  });

  function onSubmit(values: GradeLevelForm) {
    const payload = {
      code: values.code,
      label: values.label,
      ordinal: values.ordinal,
      is_final: values.is_final,
    };
    const mutation = level ? update : add;
    mutation.mutate(payload, {
      onSuccess: () => {
        toast.success(level ? "Tingkat kelas diperbarui" : "Tingkat kelas ditambahkan");
        onClose();
      },
      onError: (error) => {
        // applyServerFieldErrors returns the list of fields it mapped; an
        // empty list means nothing matched a form field, so fall back to a toast.
        const applied = applyServerFieldErrors(form, error);
        if (applied.length === 0) {
          toast.error(
            getErrorMessage(error, { fallback: "Tidak bisa menyimpan tingkat kelas." }),
          );
        }
      },
    });
  }

  return (
    <Dialog open={open} onOpenChange={(next) => (!next ? onClose() : undefined)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{level ? "Ubah Tingkat Kelas" : "Tambah Tingkat Kelas"}</DialogTitle>
          <DialogDescription>
            Urutan menentukan tingkat berikutnya saat kenaikan kelas.
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="code"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Kode</FormLabelRequired>
                  <FormControl>
                    <Input placeholder="X" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="label"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Nama</FormLabelRequired>
                  <FormControl>
                    <Input placeholder="Kelas X" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="ordinal"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Urutan</FormLabelRequired>
                  <FormControl>
                    <Input type="number" min={1} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="is_final"
              render={({ field }) => (
                <FormItem className="flex flex-row items-center gap-2 space-y-0">
                  <FormControl>
                    <Checkbox
                      checked={field.value}
                      onCheckedChange={(checked) => field.onChange(checked === true)}
                    />
                  </FormControl>
                  <span className="text-sm">
                    Tingkat akhir — siswa di tingkat ini lulus, bukan naik kelas
                  </span>
                  <FormMessage />
                </FormItem>
              )}
            />
            <DialogFooter>
              <Button type="button" variant="outline" onClick={onClose}>
                Batal
              </Button>
              <Button type="submit" disabled={add.isPending || update.isPending}>
                Simpan
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd apps/web
pnpm test:unit -- grade-levels-page
```

Expected: PASS.

- [ ] **Step 5: Add the nav tab**

In `apps/web/src/components/features/academic-config/academic-settings.tsx`, add to the `academicNav` array after `Template Kelas`:

```ts
  { href: "/settings/academic/grade-levels", label: "Tingkat Kelas" },
```

- [ ] **Step 6: Verify the nav test still passes**

```bash
cd apps/web
pnpm test:unit -- academic-config-restructure
pnpm test:unit
pnpm typecheck
pnpm lint
```

Expected: all PASS. If `academic-config-restructure.test.tsx` asserts an exact tab count, update that assertion to include the new tab.

- [ ] **Step 7: Commit**

```bash
git add src/app/settings/academic/grade-levels/page.tsx \
        src/components/features/academic-config/academic-settings.tsx \
        __tests__/grade-levels-page.test.tsx
git commit -m "feat(web): add grade levels settings page"
```

---

## Task 7: Update the architecture docs

**Files:**
- Modify: `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`
- Modify: `docs/internal/11_integration_contracts/apis/academic-config-api.md`

**Interfaces:**
- Consumes: the shipped schema and routes from Tasks 1-4.
- Produces: no code.

`docs/internal/` is the source of truth for architecture. Shipping a new
table without updating it leaves the next person reading a lie.

- [ ] **Step 1: Add `grade_level` to the ERD**

In `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`, add to the `erDiagram` block:

```
GRADE_LEVEL {
  uuid grade_level_id PK
  uuid tenant_id
  uuid academic_year_id FK
  string code
  string label
  int ordinal
  bool is_final
}

ACADEMIC_YEAR ||--o{ GRADE_LEVEL : defines
GRADE_LEVEL ||--o{ CLASS_TEMPLATE : categorises
```

Add a row to the entity table in the same file:

| Grade Level | Ordered grade ladder per academic year; `ordinal` drives promotion, `is_final` marks the graduating grade |

- [ ] **Step 2: Document the endpoints**

Append to `docs/internal/11_integration_contracts/apis/academic-config-api.md`:

```markdown
## Grade Levels

Ordered grade ladder for one academic year. `ordinal` is what makes promotion
computable (next grade = `ordinal + 1`); `is_final` marks the grade whose
students graduate rather than advance. Exactly one grade level per academic
year may be final — a second returns `VALIDATION_ERROR` on the `is_final` field.

### POST /academic-years/{academic_year_id}/grade-levels
Create a grade level. Body: `{ "code": "X", "label": "Kelas X", "ordinal": 1, "is_final": false }`.
Returns 201. Conflicts: `GRADE_LEVEL_CODE_TAKEN`, `GRADE_LEVEL_ORDINAL_TAKEN` (both 409).

### GET /academic-years/{academic_year_id}/grade-levels
List all grade levels for the year, ordered by `ordinal`. Unpaginated.

### PATCH /grade-levels/{grade_level_id}
Update code, label, ordinal and final flag.

### DELETE /grade-levels/{grade_level_id}
Delete. Returns 409 `GRADE_LEVEL_IN_USE` when class templates still reference it.

### PUT /academic-years/{academic_year_id}/grade-levels/order
Rewrite the ladder order. Body: `{ "ordered_ids": ["<uuid>", ...] }` listing
every grade level in the year exactly once; position becomes the new `ordinal`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/internal/10_data_design/03_Academic_Config_Service_ERD.md \
        docs/internal/11_integration_contracts/apis/academic-config-api.md
git commit -m "docs(contracts): document the grade level entity and endpoints"
```

---

## Task 8: Full verification

**Files:** none modified.

- [ ] **Step 1: Run the backend suite**

```bash
cd apps/backend
cargo test -p academic-config-service
```

Expected: all PASS.

- [ ] **Step 2: Run the workspace unit tests**

```bash
cd apps/backend
make test
```

Expected: PASS — nothing outside academic-config-service should be affected.

- [ ] **Step 3: Run the web suite**

```bash
cd apps/web
pnpm test:unit
pnpm typecheck
pnpm lint
```

Expected: all PASS.

- [ ] **Step 4: Manually verify the migration against a real dev database**

```bash
cd apps/backend
make up
make migrate
```

Then confirm the backfill produced sane rows:

```bash
docker compose exec postgres psql -U akademiq -d akademiq -c \
  "SELECT academic_year_id, code, ordinal, is_final FROM academic_config.grade_level ORDER BY academic_year_id, ordinal LIMIT 20;"
```

Expected: one row per distinct grade string per year, ordinals contiguous
from 1, `is_final` false everywhere. If the dev database has no class
templates the table is legitimately empty.

---

## Notes for Plan 2

Plan 2 picks up at spec sections 3.2 and 5. Two things from this plan
carry forward:

- `GradeLevelRepo::find_final` is what the promotion engine calls to decide
  graduation. It returns `None` when no grade level is marked — Plan 3 must
  treat that as a hard refusal to run, not as "nobody graduates".
- `class_template.grade_level_id` is populated but `homeroom.grade_level_id`
  does not exist yet. Plan 3 adds it in `academic-ops-service`, where
  promotion actually reads it.
