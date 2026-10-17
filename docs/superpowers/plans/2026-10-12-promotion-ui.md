# Promotion UI Implementation Plan (Plan 3d)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school admin and principal can run promotion end to end in the browser: link homerooms to grade levels, evaluate, override, submit, approve, set the target year, place students, and execute.

**Architecture:** Two small additive backend changes in academic-ops-service (homeroom ↔ grade level link with read fields and a year filter; richer decision rows), then a web feature under `/promotion` built from one pure placement module, TanStack Query hooks, and shadcn components. No migration, no new endpoint, no new error code, no event.

**Tech Stack:** Rust + Axum 0.7 + SQLx 0.8 (PostgreSQL 18); Next.js 16 + React 19 + TanStack Query 5 + React Hook Form 7 + Zod 3 + shadcn/ui; Vitest 2 + Testing Library.

**Spec:** `docs/superpowers/specs/2026-10-12-promotion-ui-design.md` (read §3.0, §3a, §4–§7 before your task).

## Global Constraints

- Backend rules: `apps/backend/CONVENTIONS.md`. Every new or changed query filters by `tenant_id`, including every JOIN.
- Backend test cadence (§7.1): per task, `cargo check --workspace` plus that task's new tests run by exact name. Full suites run once, in Task 10.
- RED must be a real failing assertion, a 404/405 from a missing route, or the compile error the task names. "0 tests matched" is not RED. In zsh, pass several test names as separate argv words.
- Web rules: `apps/web/CONVENTIONS.md`. shadcn/ui only (no native `<button>/<input>/<select>/<textarea>`); data only through TanStack hooks in `src/lib/query/**`; forms use Zod + React Hook Form with field keys equal to backend keys; user-facing error copy through `getErrorMessage` and `src/lib/errors/messages.ts`.
- User-facing copy is Bahasa Indonesia; code, comments and commit messages are English.
- Commit messages carry no trailers (no Co-authored-by, Signed-off-by, "Generated with").
- No new backend error codes. Codes used: `VALIDATION_ERROR`, `PROMOTION_RUN_EXISTS`, `PROMOTION_RUN_INVALID_STATUS`, `PROMOTION_SELF_APPROVAL`, `FORBIDDEN`, `FEATURE_NOT_AVAILABLE`, 404.
- Feature gate is `academic_ops` (not `promotion`). Permissions: `promotion.manage`, `promotion.approve`.
- Branches: backend `feat/promotion-ui` from `develop`; web `feat/promotion-ui` from the commit the parent pins (`570640a`, branch `feat/grade-levels`; not on origin yet — see Task 10).

## Deviations from the spec decided while planning

| Spec | Plan | Why |
|---|---|---|
| §5.2 names from "the existing student list endpoint" | `GET /students/:id` per cannot-evaluate student (`useQueries`) | The list endpoint caps `page_size` at 100; a 1,500-student school would miss names. The cannot-evaluate list is short. |
| §5.1 override "result radio" | shadcn `Select` | No radio-group primitive is installed; adding one means a new Radix dependency for one field. |
| §4.3 "created by / approved by / executed by" | dates, plus "Anda" when the id is the current user | Names need `GET /tenant-users` (`user.read`), which the principal does not hold. |
| §5.3 "leaving the page asks for confirmation" | `beforeunload` only (reload/close/external) | The App Router has no route-change event to intercept `<Link>` navigation. |
| §3.1 `full_name`, `nis`, `homeroom_name` as string | nullable | Rows are LEFT JOINed so a later-deleted homeroom/student never hides a decision; the UI shows "—". |

## Review Focus

1. A homeroom whose grade level is in another academic year (or another tenant) must be rejected, never linked — `grade_level_id` is user input (Task 1 test `homeroom_grade_level_link_rejects_other_year_and_tenant`).
2. After execution the decisions list must still show names and source class, because the source enrollments are `promoted` and gone from rosters (Task 2 test `decisions_keep_student_and_class_after_execution`).
3. Applying a class default must never overwrite a student the admin corrected individually (Task 5 test "applyClassDefault skips corrected decisions").
4. A Save that the server rejects must keep the draft and show each `decision <id>: …` on its row; an id the page does not know must still be shown, not dropped (Task 5 `mapAssignmentErrors` tests; Task 8 wiring).
5. The execute button must stay disabled while any promote/retain student lacks a target or the typed year name differs, including leading/trailing spaces (Task 9 tests).

---

## File Structure

Backend (`apps/backend/services/academic-ops-service/`):
- `src/domain.rs` — `Homeroom` gains `grade_level_id`, `ordinal`.
- `src/repo.rs` — homeroom insert/list/find/update carry the link; list joins `known_grade_level`; `academic_year_id` filter; `KnownGradeLevelRepo::find_in_year`.
- `src/commands.rs` — create/update resolve and validate `grade_level_id`.
- `src/http.rs` — homeroom bodies and query accept the new fields.
- `src/promotion/repo.rs` — decision rows join `student`, `homeroom`, `known_grade_level`; `find_decision_view`.
- `src/promotion/commands.rs`, `src/promotion/queries.rs` — `DecisionView` gains four fields; override returns the joined row.
- `tests/integration.rs` — new tests.

Web (`apps/web/src/`):
- `lib/query/queries/use-academic-ops.ts` — `Homeroom` type fields; `useHomeroomsForYear`.
- `lib/schemas/academic-ops.ts` — `homeroomSchema` uses `grade_level_id`.
- `components/features/academic-ops/homerooms-screen.tsx` — grade level select, "Belum tertaut" badge.
- `lib/query/queries/use-promotion.ts` — types, read hooks, `usePromotionAccess`.
- `lib/query/mutations/use-promotion.ts` — write hooks.
- `lib/schemas/promotion.ts` (+ test) — criteria, override, target year.
- `lib/promotion/placement.ts` (+ test) — pure placement logic.
- `lib/errors/messages.ts` — promotion copy.
- `components/layout/sidebar-layout.tsx` — `moduleAndAnyPermission`, "Kenaikan Kelas".
- `components/features/promotion/*` — shell, runs screen, criteria dialog, run detail, action bar, decisions tab, override dialog, cannot-evaluate tab, placement tab, execute dialog.
- `app/promotion/page.tsx`, `app/promotion/[runId]/page.tsx`.

Parent: `docs/internal/11_integration_contracts/apis/{academic-operations-api,promotion-service-api}.md` (Task 10).

### Task 1: Homerooms carry a grade level link (backend)

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/domain.rs` (`struct Homeroom`, ~line 107)
- Modify: `apps/backend/services/academic-ops-service/src/repo.rs` (`ListHomeroomsParams` ~622, `push_homeroom_filters` ~657, `UpdateHomeroomParams` ~668, `HomeroomRepo` ~677–767, `map_homeroom`/`map_homeroom_with_count` ~1430, `KnownGradeLevelRepo` ~2314)
- Modify: `apps/backend/services/academic-ops-service/src/commands.rs` (`CreateHomeroom` ~132, `UpdateHomeroom` ~252, `create_homeroom` ~810, `update_homeroom` ~868)
- Modify: `apps/backend/services/academic-ops-service/src/http.rs` (`CreateHomeroomBody` ~741, `HomeroomsQuery` ~769, `UpdateHomeroomBody` ~816, both handlers)
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs` (append)

**Interfaces:**
- Produces (JSON, every homeroom response — list, create, patch): `grade_level_id: uuid | null`, `ordinal: integer | null`. `ordinal` is `known_grade_level.ordinal` of the linked level, null when unlinked or the link dangles.
- Produces: `POST /homerooms` body `{ name, grade_level?, grade_level_id?, capacity, academic_year_id }`; `PATCH /homerooms/:id` body `{ name, grade_level?, grade_level_id?: uuid|null, capacity, homeroom_teacher_id? }`.
- Produces: `GET /homerooms?academic_year_id=<uuid>` filter (plus existing `search`, `page`, `page_size`, `sort`).
- Produces (Rust): `KnownGradeLevelRepo::find_in_year(&self, tenant_id: Uuid, academic_year_id: Uuid, grade_level_id: Uuid) -> sqlx::Result<Option<(String, i32)>>` returning `(code, ordinal)`.

Rules (spec §3.0):
- `grade_level_id` given (non-null): must exist in `known_grade_level` with the same `tenant_id` and the homeroom's `academic_year_id`, else `400 VALIDATION_ERROR` field `grade_level_id`, message `grade level not found in this academic year`, nothing written. Stored `grade_level` text becomes the level's `code`; request `grade_level` text is ignored.
- `grade_level_id` absent: unchanged behaviour — `grade_level` text required (`must not be empty`), link untouched.
- PATCH `grade_level_id: null`: clears the link, keeps the text (request `grade_level` still required in that case).
- PATCH distinguishes absent from `null` with the existing `Option<Option<Uuid>>` + `#[serde(default)]` pattern used by `homeroom_teacher_id`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/integration.rs`:

```rust
// ---------------------------------------------------------------------------
// Plan 3d Task 1: homeroom ↔ grade level link
// ---------------------------------------------------------------------------

async fn seed_known_grade_level(
    pool: &PgPool,
    tenant_id: uuid::Uuid,
    academic_year_id: uuid::Uuid,
    code: &str,
    ordinal: i32,
) -> uuid::Uuid {
    let grade_level_id = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO known_grade_level \
         (tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final) \
         VALUES ($1, $2, $3, $4, $4, $5, FALSE)",
    )
    .bind(tenant_id)
    .bind(grade_level_id)
    .bind(academic_year_id)
    .bind(code)
    .bind(ordinal)
    .execute(pool)
    .await
    .unwrap();
    grade_level_id
}

#[tokio::test]
async fn homeroom_create_links_grade_level_and_uses_its_code() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let year_id = seed_year(&pool, tenant_id, "Active").await;
    let level = seed_known_grade_level(&pool, tenant_id, year_id, "X", 1).await;
    let token = jwt_for(tenant_id);
    let app = academic_ops_service::http::router(state);

    let resp = post_json(
        app.clone(),
        &token,
        "/api/v1/academic-ops/homerooms",
        json!({"name": "X-1", "grade_level_id": level, "capacity": 32, "academic_year_id": year_id}),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::CREATED);
    let body = body_to_json(resp).await;
    assert_eq!(body["data"]["grade_level_id"], level.to_string());
    assert_eq!(body["data"]["grade_level"], "X");
    assert_eq!(body["data"]["ordinal"], 1);

    let (status, body) = get_json(
        app,
        &token,
        &format!("/api/v1/academic-ops/homerooms?academic_year_id={year_id}"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rows = body["data"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["grade_level_id"], level.to_string());
    assert_eq!(rows[0]["ordinal"], 1);
}

#[tokio::test]
async fn homeroom_grade_level_link_rejects_other_year_and_tenant() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let year_id = seed_year(&pool, tenant_id, "Active").await;
    let other_year = seed_year(&pool, tenant_id, "Draft").await;
    let other_year_level = seed_known_grade_level(&pool, tenant_id, other_year, "X", 1).await;
    let other_tenant = uuid::Uuid::new_v4();
    let other_tenant_level = seed_known_grade_level(&pool, other_tenant, year_id, "X", 1).await;
    let own_level = seed_known_grade_level(&pool, tenant_id, year_id, "XI", 2).await;
    let token = jwt_for(tenant_id);
    let app = academic_ops_service::http::router(state);

    for level in [other_year_level, other_tenant_level] {
        let resp = post_json(
            app.clone(),
            &token,
            "/api/v1/academic-ops/homerooms",
            json!({"name": "Bad", "grade_level_id": level, "capacity": 32, "academic_year_id": year_id}),
        )
        .await;
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
        let body = body_to_json(resp).await;
        assert_eq!(
            body["error"]["fields"]["grade_level_id"][0],
            "grade level not found in this academic year"
        );
    }
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM homeroom WHERE tenant_id = $1")
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0, "a rejected create must write nothing");

    // PATCH with a foreign level is rejected and leaves the row untouched.
    let homeroom = create_homeroom_named(app.clone(), &token, year_id, "XI-1", "11").await;
    let (status, body) = patch_json(
        app.clone(),
        &token,
        &format!("/api/v1/academic-ops/homerooms/{homeroom}"),
        json!({"name": "XI-1", "grade_level_id": other_year_level, "capacity": 32}),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    let stored: (Option<uuid::Uuid>, String) =
        sqlx::query_as("SELECT grade_level_id, grade_level FROM homeroom WHERE homeroom_id = $1")
            .bind(homeroom)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(stored, (None, "11".to_string()));

    // PATCH with an own-year level links it.
    let (status, body) = patch_json(
        app,
        &token,
        &format!("/api/v1/academic-ops/homerooms/{homeroom}"),
        json!({"name": "XI-1", "grade_level_id": own_level, "capacity": 32}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["grade_level_id"], own_level.to_string());
    assert_eq!(body["data"]["grade_level"], "XI");
    assert_eq!(body["data"]["ordinal"], 2);
}

#[tokio::test]
async fn homeroom_patch_null_clears_link_and_absent_keeps_it() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let year_id = seed_year(&pool, tenant_id, "Active").await;
    let level = seed_known_grade_level(&pool, tenant_id, year_id, "X", 1).await;
    let token = jwt_for(tenant_id);
    let app = academic_ops_service::http::router(state);

    let resp = post_json(
        app.clone(),
        &token,
        "/api/v1/academic-ops/homerooms",
        json!({"name": "X-1", "grade_level_id": level, "capacity": 32, "academic_year_id": year_id}),
    )
    .await;
    let homeroom: uuid::Uuid = body_to_json(resp).await["data"]["homeroom_id"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();

    // Absent: link kept, capacity changes.
    let (status, body) = patch_json(
        app.clone(),
        &token,
        &format!("/api/v1/academic-ops/homerooms/{homeroom}"),
        json!({"name": "X-1", "grade_level": "X", "capacity": 30}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["grade_level_id"], level.to_string());
    assert_eq!(body["data"]["capacity"], 30);

    // Null: link cleared, text kept.
    let (status, body) = patch_json(
        app,
        &token,
        &format!("/api/v1/academic-ops/homerooms/{homeroom}"),
        json!({"name": "X-1", "grade_level": "X", "grade_level_id": null, "capacity": 30}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["data"]["grade_level_id"].is_null());
    assert!(body["data"]["ordinal"].is_null());
    assert_eq!(body["data"]["grade_level"], "X");
}

#[tokio::test]
async fn homeroom_list_filters_by_academic_year() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let year_a = seed_year(&pool, tenant_id, "Active").await;
    let year_b = seed_year(&pool, tenant_id, "Draft").await;
    seed_homeroom(&pool, tenant_id, year_a, "A-1", "1").await;
    seed_homeroom(&pool, tenant_id, year_b, "B-1", "1").await;
    let token = jwt_for(tenant_id);
    let app = academic_ops_service::http::router(state);

    let (status, body) = get_json(
        app,
        &token,
        &format!("/api/v1/academic-ops/homerooms?academic_year_id={year_b}"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rows = body["data"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["name"], "B-1");
    assert_eq!(body["meta"]["total"], 1);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `apps/backend`):
`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact homeroom_create_links_grade_level_and_uses_its_code homeroom_grade_level_link_rejects_other_year_and_tenant homeroom_patch_null_clears_link_and_absent_keeps_it homeroom_list_filters_by_academic_year`

Expected: all four FAIL on assertions — the create response has no `grade_level_id` (`assert_eq!` on `body["data"]["grade_level_id"]` gets `null`), the foreign-level create returns 400 for the missing text `grade_level` *field*, not `grade_level_id` (or 201), and the year filter is ignored (`rows.len()` is 2). `homeroom_patch_null_clears_teacher` (added in Step 5) fails on `is_null()`: the teacher stays set. Record each failing assertion.

- [ ] **Step 3: Domain and repo**

`src/domain.rs`, `struct Homeroom` — add after `academic_year_id`:

```rust
    pub grade_level_id: Option<Uuid>,
    /// `known_grade_level.ordinal` of the linked level; None when unlinked or
    /// the link dangles. Read-only (never written).
    pub ordinal: Option<i32>,
```

`src/repo.rs`:

`ListHomeroomsParams` gains `pub academic_year_id: Option<Uuid>,` and `new` takes it as the last argument:

```rust
    pub fn new(
        tenant_id: Uuid,
        search: Option<String>,
        page: Option<u32>,
        page_size: Option<u32>,
        sort: Option<HomeroomSort>,
        academic_year_id: Option<Uuid>,
    ) -> Self {
        Self {
            tenant_id,
            search: search.and_then(non_empty),
            page: page.unwrap_or(1).max(1),
            page_size: page_size
                .unwrap_or(Self::DEFAULT_PAGE_SIZE)
                .clamp(1, Self::MAX_PAGE_SIZE),
            sort: sort.unwrap_or_default(),
            academic_year_id,
        }
    }
```

`push_homeroom_filters` — the list query aliases `homeroom h` and the count query does not, so qualify nothing and add the year filter after the search block:

```rust
    if let Some(year) = params.academic_year_id {
        query.push(" AND academic_year_id = ");
        query.push_bind(year);
    }
```

In `list`, the outer table is aliased `h` and now also joins `known_grade_level`, so an unqualified `academic_year_id` would be ambiguous. Change `list` to:

```rust
    pub async fn list(&self, params: &ListHomeroomsParams) -> sqlx::Result<Vec<Homeroom>> {
        let mut query = QueryBuilder::<Postgres>::new(
            "SELECT * FROM (SELECT h.homeroom_id, h.tenant_id, h.name, h.grade_level, h.capacity, \
             h.academic_year_id, h.homeroom_teacher_id, h.grade_level_id, kgl.ordinal, \
             h.created_at, h.updated_at, \
             COUNT(e.enrollment_id) AS enrolled_count \
             FROM homeroom h \
             LEFT JOIN enrollment e ON e.homeroom_id = h.homeroom_id AND e.status = 'active' \
             LEFT JOIN known_grade_level kgl \
               ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id \
             WHERE h.tenant_id=",
        );
        query.push_bind(params.tenant_id);
        query.push(
            " GROUP BY h.homeroom_id, kgl.ordinal) AS homeroom_row WHERE TRUE",
        );
        push_homeroom_filters(&mut query, params);
        query.push(" ORDER BY ");
        query.push(params.sort.sql());
        query.push(" LIMIT ").push_bind(params.page_size as i64);
        query.push(" OFFSET ").push_bind(params.offset());
        let rows = query.build().fetch_all(&self.0).await?;
        Ok(rows.into_iter().map(map_homeroom_with_count).collect())
    }
```

(The subquery exposes plain column names, so `push_homeroom_filters` and `HomeroomSort::sql()` — `name ASC, grade_level ASC` — keep working unqualified. The derived table keeps `tenant_id` filtered inside.)

`insert` writes the link:

```rust
    pub async fn insert<'e, E: PgExecutor<'e>>(&self, ex: E, h: &Homeroom) -> sqlx::Result<()> {
        sqlx::query("INSERT INTO homeroom (homeroom_id, tenant_id, name, grade_level, capacity, academic_year_id, grade_level_id, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)")
            .bind(h.homeroom_id).bind(h.tenant_id).bind(&h.name).bind(&h.grade_level).bind(h.capacity).bind(h.academic_year_id).bind(h.grade_level_id).bind(h.created_at).bind(h.updated_at)
            .execute(ex).await?;
        Ok(())
    }
```

`find` selects the link and its ordinal:

```rust
    pub async fn find(&self, tenant_id: Uuid, id: Uuid) -> sqlx::Result<Option<Homeroom>> {
        let row = sqlx::query(
            "SELECT h.homeroom_id, h.tenant_id, h.name, h.grade_level, h.capacity, h.academic_year_id, \
                    h.homeroom_teacher_id, h.grade_level_id, kgl.ordinal, h.created_at, h.updated_at \
             FROM homeroom h \
             LEFT JOIN known_grade_level kgl \
               ON kgl.tenant_id = h.tenant_id AND kgl.grade_level_id = h.grade_level_id \
             WHERE h.tenant_id=$1 AND h.homeroom_id=$2",
        )
        .bind(tenant_id)
        .bind(id)
        .fetch_optional(&self.0)
        .await?;
        Ok(row.map(map_homeroom))
    }
```

`UpdateHomeroomParams` gains `pub grade_level_id: Option<Option<Uuid>>,` (None = leave, Some(None) = clear, Some(Some(id)) = set). In `update`, destructure it and push after the teacher block:

```rust
        if let Some(level) = grade_level_id {
            query.push(", grade_level_id=");
            query.push_bind(level);
        }
```

and make the `RETURNING` read the ordinal through a scalar subquery (an UPDATE cannot JOIN):

```rust
        query.push(
            " RETURNING homeroom_id, tenant_id, name, grade_level, capacity, academic_year_id, \
             homeroom_teacher_id, grade_level_id, \
             (SELECT kgl.ordinal FROM known_grade_level kgl \
               WHERE kgl.tenant_id = homeroom.tenant_id \
                 AND kgl.grade_level_id = homeroom.grade_level_id) AS ordinal, \
             created_at, updated_at",
        );
```

`map_homeroom` and `map_homeroom_with_count` add:

```rust
        grade_level_id: row.get("grade_level_id"),
        ordinal: row.get("ordinal"),
```

Every other `Homeroom { .. }` literal (`commands.rs::create_homeroom`) gets the two fields (see Step 4). Run `grep -rn "Homeroom {" src` to find them all; there are three today (two mappers, one command).

`KnownGradeLevelRepo` gains:

```rust
    /// `(code, ordinal)` of a grade level of this tenant and year; None when
    /// it belongs to another tenant, another year, or does not exist.
    pub async fn find_in_year(
        &self,
        tenant_id: Uuid,
        academic_year_id: Uuid,
        grade_level_id: Uuid,
    ) -> sqlx::Result<Option<(String, i32)>> {
        sqlx::query_as(
            "SELECT code, ordinal FROM known_grade_level \
             WHERE tenant_id = $1 AND academic_year_id = $2 AND grade_level_id = $3",
        )
        .bind(tenant_id)
        .bind(academic_year_id)
        .bind(grade_level_id)
        .fetch_optional(&self.0)
        .await
    }
```

- [ ] **Step 4: Commands**

`CreateHomeroom`: `grade_level: String` stays, add `pub grade_level_id: Option<Uuid>,`.
`UpdateHomeroom`: add `pub grade_level_id: Option<Option<Uuid>>,`.

Add a helper next to `validate_name`:

```rust
const GRADE_LEVEL_NOT_IN_YEAR: &str = "grade level not found in this academic year";

/// Resolves a requested grade level to its code, or a field error when it is
/// not a grade level of this tenant and year (Plan 3d spec §3.0).
async fn grade_level_code(
    state: &AppState,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    grade_level_id: Uuid,
) -> Result<(String, i32), AppError> {
    state
        .known_grade_levels
        .find_in_year(tenant_id, academic_year_id, grade_level_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| validation("grade_level_id", GRADE_LEVEL_NOT_IN_YEAR))
}
```

`create_homeroom`: replace `validate_name("grade_level", &input.grade_level)?;` with resolution done **after** the year check (the year must be known before validating the level against it):

```rust
    ensure_active_subscription(state, input.tenant_id).await?;
    validate_name("name", &input.name)?;
    if input.grade_level_id.is_none() {
        validate_name("grade_level", &input.grade_level)?;
    }
    if input.capacity <= 0 {
        return Err(validation("capacity", "must be greater than 0"));
    }
    // ... existing is_active year check unchanged ...
    let (grade_level, ordinal) = match input.grade_level_id {
        Some(level) => {
            let (code, ordinal) =
                grade_level_code(state, input.tenant_id, input.academic_year_id, level).await?;
            (code, Some(ordinal))
        }
        None => (input.grade_level, None),
    };
    let now = Utc::now();
    let homeroom = Homeroom {
        homeroom_id: Uuid::new_v4(),
        tenant_id: input.tenant_id,
        name: input.name,
        grade_level,
        capacity: input.capacity,
        academic_year_id: input.academic_year_id,
        homeroom_teacher_id: None,
        grade_level_id: input.grade_level_id,
        ordinal,
        enrolled_count: 0,
        created_at: now,
        updated_at: now,
    };
```

`update_homeroom`: the year comes from the existing row. Replace the start of the function (everything before the existing homeroom-teacher validation) with:

```rust
    ensure_active_subscription(state, input.tenant_id).await?;
    validate_name("name", &input.name)?;
    if input.capacity <= 0 {
        return Err(validation("capacity", "must be greater than 0"));
    }

    let linking = matches!(input.grade_level_id, Some(Some(_)));
    if !linking {
        validate_name("grade_level", &input.grade_level)?;
    }
    let grade_level = match input.grade_level_id {
        Some(Some(level)) => {
            let existing = state
                .homerooms
                .find(input.tenant_id, input.homeroom_id)
                .await
                .map_err(AppError::internal)?
                .ok_or_else(|| AppError::not_found("homeroom"))?;
            grade_level_code(state, input.tenant_id, existing.academic_year_id, level)
                .await?
                .0
        }
        _ => input.grade_level.clone(),
    };
```

then pass `grade_level` (instead of `input.grade_level`) and `grade_level_id: input.grade_level_id` into `UpdateHomeroomParams`. Keep the existing teacher validation as it is.

- [ ] **Step 5: HTTP**

```rust
#[derive(Debug, Deserialize)]
struct CreateHomeroomBody {
    name: String,
    #[serde(default)]
    grade_level: String,
    #[serde(default)]
    grade_level_id: Option<Uuid>,
    capacity: i32,
    academic_year_id: Uuid,
}
```

Handler passes `grade_level_id: body.grade_level_id`.

```rust
#[derive(Debug, Deserialize)]
struct HomeroomsQuery {
    search: Option<String>,
    page: Option<u32>,
    page_size: Option<u32>,
    sort: Option<String>,
    academic_year_id: Option<Uuid>,
}
```

`into_params` passes `self.academic_year_id` as the new last argument.

```rust
/// Distinguishes an absent key (None) from an explicit `null` (Some(None)).
/// `#[serde(default)]` alone cannot: serde decodes `null` for
/// `Option<Option<T>>` as the outer `None`, the same as an absent key.
fn double_option<'de, D, T>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

#[derive(Debug, Deserialize)]
struct UpdateHomeroomBody {
    name: String,
    #[serde(default)]
    grade_level: String,
    capacity: i32,
    #[serde(default, deserialize_with = "double_option")]
    homeroom_teacher_id: Option<Option<Uuid>>,
    #[serde(default, deserialize_with = "double_option")]
    grade_level_id: Option<Option<Uuid>>,
}
```

Handler passes `grade_level_id: body.grade_level_id`.

This also fixes an existing bug found while planning: `homeroom_teacher_id: null` (the web's "Kosongkan wali kelas") decoded as "leave unchanged", so a homeroom teacher could never be cleared. `homeroom_patch_null_clears_teacher` below pins it.

Add this test with the others in Step 1 (it fails today: the teacher stays set):

```rust
#[tokio::test]
async fn homeroom_patch_null_clears_teacher() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_id).await;
    let year_id = seed_year(&pool, tenant_id, "Active").await;
    let token = jwt_for(tenant_id);
    let app = academic_ops_service::http::router(state);
    let teacher = create_teacher(app.clone(), &token, "NIP-CLEAR").await;
    let homeroom = create_homeroom_named(app.clone(), &token, year_id, "7A", "7").await;
    let uri = format!("/api/v1/academic-ops/homerooms/{homeroom}");

    let (status, body) = patch_json(
        app.clone(),
        &token,
        &uri,
        json!({"name": "7A", "grade_level": "7", "capacity": 32, "homeroom_teacher_id": teacher}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["homeroom_teacher_id"], teacher.to_string());

    let (status, body) = patch_json(
        app,
        &token,
        &uri,
        json!({"name": "7A", "grade_level": "7", "capacity": 32, "homeroom_teacher_id": null}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["data"]["homeroom_teacher_id"].is_null(), "body: {body}");
}
```

Add `homeroom_patch_null_clears_teacher` to the Step 2 and Step 6 commands.

- [ ] **Step 6: Run the tests to verify they pass**

Run the Step 2 command again (with `homeroom_patch_null_clears_teacher`). Expected: 5 passed.
Regression: `cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact homeroom_list_patch_and_delete_guard`. Expected: PASS (sort and search still work over the derived table).
Then `cargo check --workspace`. Expected: clean (pre-existing warnings only).

- [ ] **Step 7: Commit**

```bash
git add services/academic-ops-service/src services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): link homerooms to grade levels and filter them by year"
```

---

### Task 2: Decision rows carry student and class facts (backend)

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/promotion/repo.rs` (`DecisionListRow` ~705, `DecisionListTuple`/`decision_list_row` ~718–757, `list_decisions_for_run` ~760)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/commands.rs` (`DecisionView` ~563, end of `override_decision` ~630)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/queries.rs` (`impl From<repo::DecisionListRow> for DecisionView` ~182)
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs` (append)

**Interfaces:**
- Consumes: Plan 3c helpers `ready_to_execute(&pool, &state) -> (ExecutionFixture, Router)`, `execute_req`, `get_json`, `override_decision_req`, `decision_id_of`, `jwt_for`.
- Produces (JSON decision shape, list and override response): adds `full_name: string|null`, `nis: string|null`, `homeroom_name: string|null`, `source_ordinal: integer|null`.
- Produces (Rust): `pub async fn find_decision_view(conn: &mut sqlx::PgConnection, tenant_id: Uuid, run_id: Uuid, decision_id: Uuid) -> sqlx::Result<Option<DecisionListRow>>`.

The four fields come from LEFT JOINs (`student`, `homeroom`, `known_grade_level`) so a decision is never hidden by a missing row. Every join matches `tenant_id`.

- [ ] **Step 1: Write the failing tests**

```rust
// ---------------------------------------------------------------------------
// Plan 3d Task 2: decision rows carry student and class facts
// ---------------------------------------------------------------------------

#[tokio::test]
async fn decisions_keep_student_and_class_after_execution() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = ready_to_execute(&pool, &state).await;
    let uri = format!("/api/v1/academic-ops/promotion-runs/{}/decisions", ex.run_id);

    let (status, before) = get_json(app.clone(), &ex.admin_token, &uri).await;
    assert_eq!(status, StatusCode::OK);
    let row = before["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["student_id"] == ex.promote_student.to_string())
        .unwrap()
        .clone();
    assert_eq!(row["full_name"], "Promo Student");
    assert_eq!(row["nis"], format!("P-{}", ex.promote_student));
    assert_eq!(row["homeroom_name"], "Mid-A");
    assert_eq!(row["source_ordinal"], 1);

    let (status, body) = execute_req(app.clone(), &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");

    let (status, after) = get_json(app, &ex.admin_token, &uri).await;
    assert_eq!(status, StatusCode::OK);
    let rows = after["data"].as_array().unwrap();
    assert_eq!(rows.len(), 3);
    for row in rows {
        assert_eq!(row["full_name"], "Promo Student", "row: {row}");
        assert!(row["nis"].as_str().unwrap().starts_with("P-"), "row: {row}");
        assert!(row["homeroom_name"].is_string(), "row: {row}");
        assert!(row["source_ordinal"].is_i64(), "row: {row}");
    }
}

#[tokio::test]
async fn decision_source_ordinal_is_null_for_unlinked_homeroom_and_never_crosses_tenants() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let fx = seed_promotion_fixture(&pool, &state).await;
    let student = seed_promoted_student(&pool, &fx, fx.mid_homeroom, &[90.0]).await;
    let token = jwt_for(fx.tenant_id);
    let app = academic_ops_service::http::router(state);
    let (status, body) = create_run(app.clone(), &token, json!({ "academic_year_id": fx.year_id })).await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    let run_id: uuid::Uuid = body["data"]["run_id"].as_str().unwrap().parse().unwrap();

    // Another tenant owns a grade level with the same id the homeroom points
    // at after we re-point it: the join must not pick it up.
    let foreign_level = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO known_grade_level \
         (tenant_id, grade_level_id, academic_year_id, code, label, ordinal, is_final) \
         VALUES ($1, $2, $3, 'Z', 'Z', 9, FALSE)",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(foreign_level)
    .bind(fx.year_id)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("UPDATE homeroom SET grade_level_id = $1 WHERE homeroom_id = $2")
        .bind(foreign_level)
        .bind(fx.mid_homeroom)
        .execute(&pool)
        .await
        .unwrap();

    let (status, body) = get_json(
        app,
        &token,
        &format!("/api/v1/academic-ops/promotion-runs/{run_id}/decisions"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let row = body["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["student_id"] == student.to_string())
        .unwrap()
        .clone();
    assert!(row["source_ordinal"].is_null(), "row: {row}");
    assert_eq!(row["homeroom_name"], "Mid-A");
}

#[tokio::test]
async fn override_response_carries_student_and_class_facts() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let fx = seed_promotion_fixture(&pool, &state).await;
    let student = seed_promoted_student(&pool, &fx, fx.mid_homeroom, &[90.0]).await;
    let token = jwt_for(fx.tenant_id);
    let app = academic_ops_service::http::router(state);
    let (status, body) = create_run(app.clone(), &token, json!({ "academic_year_id": fx.year_id })).await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    let run_id: uuid::Uuid = body["data"]["run_id"].as_str().unwrap().parse().unwrap();
    let decision = decision_id_of(&pool, run_id, student).await;

    let (status, body) = override_decision_req(
        app,
        &token,
        run_id,
        decision,
        json!({ "result": "retain", "reason": "Long absence, staff meeting agreed" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["full_name"], "Promo Student");
    assert_eq!(body["data"]["homeroom_name"], "Mid-A");
    assert_eq!(body["data"]["source_ordinal"], 1);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact decisions_keep_student_and_class_after_execution decision_source_ordinal_is_null_for_unlinked_homeroom_and_never_crosses_tenants override_response_carries_student_and_class_facts`

Expected: all three FAIL — `row["full_name"]` is `null` (the field does not exist yet), so the `assert_eq!` against `"Promo Student"` fails; the second test fails on `homeroom_name`. Record the assertions.

- [ ] **Step 3: Repo**

Replace `DecisionListRow`, `DecisionListTuple`, `decision_list_row` and `list_decisions_for_run` with a `FromRow` struct (the tuple would reach 14 columns) and one shared SELECT:

```rust
#[derive(sqlx::FromRow)]
pub struct DecisionListRow {
    pub decision_id: Uuid,
    pub student_id: Uuid,
    pub homeroom_id: Uuid,
    pub recommended: String,
    pub result: String,
    pub overridden: bool,
    pub reason: Option<String>,
    pub computed_metrics: serde_json::Value,
    pub target_homeroom_id: Option<Uuid>,
    pub target_enrollment_id: Option<Uuid>,
    pub full_name: Option<String>,
    pub nis: Option<String>,
    pub homeroom_name: Option<String>,
    pub source_ordinal: Option<i32>,
}

/// Decision columns plus student and source-class facts. LEFT JOINs so a
/// decision is never hidden; every join is tenant-scoped. Reads `student` and
/// `homeroom`, not enrollments, so the facts survive execution.
const DECISION_VIEW_SELECT: &str = "\
    SELECT d.decision_id, d.student_id, d.homeroom_id, d.recommended, d.result, d.overridden, \
           d.reason, d.computed_metrics, d.target_homeroom_id, d.target_enrollment_id, \
           s.full_name, s.nis, h.name AS homeroom_name, kgl.ordinal AS source_ordinal \
    FROM promotion_decision d \
    LEFT JOIN student s ON s.tenant_id = d.tenant_id AND s.student_id = d.student_id \
    LEFT JOIN homeroom h ON h.tenant_id = d.tenant_id AND h.homeroom_id = d.homeroom_id \
    LEFT JOIN known_grade_level kgl \
      ON kgl.tenant_id = d.tenant_id AND kgl.grade_level_id = h.grade_level_id";

pub async fn list_decisions_for_run(
    pool: &PgPool,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Option<Uuid>,
) -> sqlx::Result<Vec<DecisionListRow>> {
    match homeroom_id {
        Some(homeroom_id) => {
            sqlx::query_as(&format!(
                "{DECISION_VIEW_SELECT} \
                 WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.homeroom_id = $3 \
                 ORDER BY d.homeroom_id, d.student_id"
            ))
            .bind(tenant_id)
            .bind(run_id)
            .bind(homeroom_id)
            .fetch_all(pool)
            .await
        }
        None => {
            sqlx::query_as(&format!(
                "{DECISION_VIEW_SELECT} \
                 WHERE d.tenant_id = $1 AND d.run_id = $2 \
                 ORDER BY d.homeroom_id, d.student_id"
            ))
            .bind(tenant_id)
            .bind(run_id)
            .fetch_all(pool)
            .await
        }
    }
}

/// One decision with the same facts as the list, read on the caller's
/// transaction (override returns it after its write).
pub async fn find_decision_view(
    conn: &mut sqlx::PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    decision_id: Uuid,
) -> sqlx::Result<Option<DecisionListRow>> {
    sqlx::query_as(&format!(
        "{DECISION_VIEW_SELECT} WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.decision_id = $3"
    ))
    .bind(tenant_id)
    .bind(run_id)
    .bind(decision_id)
    .fetch_optional(&mut *conn)
    .await
}
```

Delete `DecisionListTuple` and `decision_list_row` (now unused; `cargo check` will tell you if anything else used them).

- [ ] **Step 4: View and override**

`commands.rs`, `DecisionView` gains:

```rust
    pub full_name: Option<String>,
    pub nis: Option<String>,
    pub homeroom_name: Option<String>,
    pub source_ordinal: Option<i32>,
```

`queries.rs`, the `From<repo::DecisionListRow>` impl maps the four new fields one-to-one.

`override_decision`: replace the hand-built `DecisionView { .. }` at the end with a read of the joined row **before** commit, on the same transaction:

```rust
    let view = repo::find_decision_view(&mut tx, input.tenant_id, input.run_id, input.decision_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion decision"))?;

    tx.commit().await.map_err(AppError::internal)?;

    Ok(DecisionView::from(view))
```

(`DecisionView::from` lives in `queries.rs`; `use crate::promotion::queries` is not needed because the `From` impl is in scope crate-wide. If the compiler cannot find it, call `crate::promotion::queries::DecisionView`'s impl through `view.into()`.) The variables `decision`, `parsed_result`, `overridden`, `reason` stay — they are still used to compute and write the override.

- [ ] **Step 5: Run the tests to verify they pass**

Step 2 command again → 3 passed. Regression: `--exact override_requires_real_reason assign_targets_writes_promote_and_retain_targets execute_moves_every_student_and_publishes_events` → all pass. `cargo check --workspace` → clean.

- [ ] **Step 6: Commit**

```bash
git add services/academic-ops-service/src/promotion services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): include student and source class facts in promotion decisions"
```

---

### Task 3: Homeroom form picks a grade level (web)

**Files:**
- Modify: `apps/web/src/lib/schemas/academic-ops.ts` (`homeroomSchema` ~136)
- Modify: `apps/web/src/lib/query/queries/use-academic-ops.ts` (`Homeroom` type ~133; new `useHomeroomsForYear`)
- Modify: `apps/web/src/lib/query/mutations/use-academic-ops.ts` (`useCreateHomeroom` ~104, `UpdateHomeroomInput` ~109)
- Modify: `apps/web/src/components/features/academic-ops/homerooms-screen.tsx` (grade-level column ~264, `HomeroomDialog` ~657–816)
- Modify: `apps/web/playwright/academic-ops.spec.ts:82` (fills "Tingkat" as text)
- Create: `apps/web/src/lib/schemas/academic-ops.test.ts`
- Create: `apps/web/src/components/features/academic-ops/homeroom-dialog.test.tsx`

**Interfaces:**
- Consumes: Task 1 JSON fields `grade_level_id`, `ordinal`; `GET /homerooms?academic_year_id=`.
- Consumes: `useGradeLevels(academicYearId?: string)` and `type GradeLevel` from `@/lib/query/queries/use-academic-config` (existing).
- Produces: `type Homeroom` gains `grade_level_id: string | null; ordinal: number | null`.
- Produces: `useHomeroomsForYear(academicYearId?: string)` → `UseQueryResult<Homeroom[]>`, key `[...HOMEROOMS_QUERY_KEY, "year", academicYearId]`, path `/api/v1/academic-ops/homerooms?academic_year_id=<id>&page=1&page_size=100`. Used by Task 8.
- Produces: `homeroomSchema` = `{ name: string, grade_level_id: uuid, capacity: number, academic_year_id: uuid }`; `type HomeroomForm`.
- Produces: `HomeroomDialog` exported (was module-private) for the test.

Behaviour (spec §3.0):
- The "Tingkat" text input becomes a `Select` of the scope year's grade levels (for an existing homeroom, of *its* year), each item `label (code)`, value `grade_level_id`. Required.
- Editing an unlinked homeroom: the select starts empty with the current text shown as a hint "Saat ini: <grade_level> (belum tertaut)"; saving requires a choice.
- The year has no grade levels: the select is disabled, with text "Tahun ajaran ini belum punya tingkat kelas." and a `Link` to `/settings/academic/grade-levels`.
- Table column "Tingkat": shows `grade_level`; when `grade_level_id` is null, add `<Badge variant="outline">Belum tertaut</Badge>`.
- Requests send `grade_level_id` and no `grade_level` text (the backend derives it).

- [ ] **Step 1: Write the failing tests**

`src/lib/schemas/academic-ops.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import { homeroomSchema } from "@/lib/schemas/academic-ops";

const YEAR = "11111111-1111-4111-8111-111111111111";
const LEVEL = "22222222-2222-4222-8222-222222222222";

describe("homeroomSchema", () => {
  it("accepts a homeroom linked to a grade level", () => {
    const parsed = homeroomSchema.parse({
      name: "X-1",
      grade_level_id: LEVEL,
      capacity: "32",
      academic_year_id: YEAR,
    });
    expect(parsed).toEqual({ name: "X-1", grade_level_id: LEVEL, capacity: 32, academic_year_id: YEAR });
  });

  it("rejects a homeroom without a grade level", () => {
    const result = homeroomSchema.safeParse({ name: "X-1", grade_level_id: "", capacity: 32, academic_year_id: YEAR });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.flatten().fieldErrors.grade_level_id?.[0]).toBe("Pilih tingkat kelas");
    }
  });
});
```

`src/components/features/academic-ops/homeroom-dialog.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const levels = vi.hoisted(() => ({ data: [] as unknown[] }));

vi.mock("@/hooks/use-academic-scope", () => ({
  useAcademicScope: () => ({ yearId: "11111111-1111-4111-8111-111111111111" }),
}));
vi.mock("@/lib/query/queries/use-academic-config", () => ({
  useGradeLevels: () => ({ data: levels.data, isLoading: false }),
}));
vi.mock("@/lib/query/queries/use-academic-ops", () => ({
  useTeachers: () => ({ data: [], isLoading: false }),
}));
vi.mock("@/lib/query/mutations/use-academic-ops", () => {
  const m = () => ({ mutateAsync: vi.fn(), isPending: false });
  return { useCreateHomeroom: m, useUpdateHomeroom: m };
});

import { HomeroomDialog } from "@/components/features/academic-ops/homerooms-screen";

describe("HomeroomDialog grade level", () => {
  it("points to grade level settings when the year has none", () => {
    levels.data = [];
    render(<HomeroomDialog canManage upgradeMessage="" open onOpenChange={() => undefined} />);
    expect(screen.getByText("Tahun ajaran ini belum punya tingkat kelas.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Atur tingkat kelas" })).toHaveAttribute(
      "href",
      "/settings/academic/grade-levels",
    );
  });

  it("shows the current text of an unlinked homeroom", () => {
    levels.data = [
      { grade_level_id: "22222222-2222-4222-8222-222222222222", label: "Kelas X", code: "X", ordinal: 1 },
    ];
    render(
      <HomeroomDialog
        canManage
        upgradeMessage=""
        open
        onOpenChange={() => undefined}
        homeroom={{
          homeroom_id: "33333333-3333-4333-8333-333333333333",
          name: "X-1",
          grade_level: "10",
          grade_level_id: null,
          ordinal: null,
          capacity: 32,
          academic_year_id: "11111111-1111-4111-8111-111111111111",
          enrolled_count: 0,
          homeroom_teacher_id: null,
        }}
      />,
    );
    expect(screen.getByText("Saat ini: 10 (belum tertaut)")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `apps/web`): `pnpm vitest run src/lib/schemas/academic-ops.test.ts src/components/features/academic-ops/homeroom-dialog.test.tsx`

Expected: FAIL — the schema test fails on `toEqual` (the schema has `grade_level`, strips `grade_level_id`); the dialog test fails to import `HomeroomDialog` (not exported) — record that error, then after exporting it the text assertions fail. Record both.

- [ ] **Step 3: Schema, types, hooks**

`src/lib/schemas/academic-ops.ts`:

```ts
export const homeroomSchema = z.object({
  name: z.string().min(1),
  grade_level_id: z.string().uuid("Pilih tingkat kelas"),
  capacity: z.coerce.number().int().positive(),
  academic_year_id: uuid,
});
```

`src/lib/query/queries/use-academic-ops.ts` — `Homeroom`:

```ts
export type Homeroom = {
  homeroom_id: string;
  name: string;
  grade_level: string;
  grade_level_id: string | null;
  ordinal: number | null;
  capacity: number;
  academic_year_id: string;
  enrolled_count: number;
  homeroom_teacher_id?: string | null;
};
```

and after `useHomerooms`:

```ts
/** Homerooms of one academic year (at most 100 — a school year has far fewer). */
export function useHomeroomsForYear(academicYearId?: string) {
  return useQuery({
    queryKey: [...HOMEROOMS_QUERY_KEY, "year", academicYearId],
    queryFn: () =>
      apiFetch<Homeroom[]>({
        service: "academic-ops",
        path: `/api/v1/academic-ops/homerooms?academic_year_id=${academicYearId}&page=1&page_size=100`,
        authenticated: true,
      }),
    enabled: Boolean(academicYearId),
  });
}
```

`src/lib/query/mutations/use-academic-ops.ts`: `useCreateHomeroom` keeps `(input: HomeroomForm)`. Change the update input type to:

```ts
type UpdateHomeroomInput = {
  name?: string;
  grade_level_id?: string | null;
  capacity?: number;
  homeroom_teacher_id?: string | null;
};
```

- [ ] **Step 4: Dialog and table**

In `homerooms-screen.tsx`:

Imports — add:

```ts
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useGradeLevels } from "@/lib/query/queries/use-academic-config";
```

Grade-level column cell:

```tsx
      cell: ({ row }) => (
        <span className="flex items-center gap-2">
          <span className="tabular-nums">{row.original.grade_level}</span>
          {row.original.grade_level_id ? null : <Badge variant="outline">Belum tertaut</Badge>}
        </span>
      ),
```

`HomeroomDialog` — change `function HomeroomDialog(` to `export function HomeroomDialog(`. Inside:

```tsx
  const dialogYearId = homeroom?.academic_year_id ?? yearId ?? undefined;
  const gradeLevels = useGradeLevels(dialogYearId);
  const levels = gradeLevels.data ?? [];

  const defaultValues = React.useMemo<HomeroomForm>(
    () => ({
      name: homeroom?.name ?? "",
      grade_level_id: homeroom?.grade_level_id ?? "",
      capacity: homeroom?.capacity ?? 32,
      academic_year_id: homeroom?.academic_year_id ?? yearId ?? "",
    }),
    [homeroom, yearId],
  );
```

`onSubmit`, update branch:

```ts
        await update.mutateAsync({
          name: values.name,
          grade_level_id: values.grade_level_id,
          capacity: values.capacity,
          homeroom_teacher_id: resolvedTeacherId,
        });
```

create branch reset: `form.reset({ name: "", grade_level_id: "", capacity: 32, academic_year_id: yearId ?? "" });`

Replace the `grade_level` `FormField` with:

```tsx
            <FormField
              control={form.control}
              name="grade_level_id"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Tingkat</FormLabel>
                  {levels.length === 0 && !gradeLevels.isLoading ? (
                    <p className="text-sm text-muted-foreground">
                      Tahun ajaran ini belum punya tingkat kelas.{" "}
                      <Link href="/settings/academic/grade-levels" className="underline">
                        Atur tingkat kelas
                      </Link>
                    </p>
                  ) : (
                    <Select value={field.value} onValueChange={field.onChange} disabled={gradeLevels.isLoading}>
                      <FormControl>
                        <SelectTrigger aria-label="Tingkat">
                          <SelectValue placeholder="Pilih tingkat kelas" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {levels.map((level) => (
                          <SelectItem key={level.grade_level_id} value={level.grade_level_id}>
                            {level.label} ({level.code})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                  {homeroom && !homeroom.grade_level_id ? (
                    <p className="text-xs text-muted-foreground">
                      Saat ini: {homeroom.grade_level} (belum tertaut)
                    </p>
                  ) : null}
                  <FormMessage />
                </FormItem>
              )}
            />
```

`playwright/academic-ops.spec.ts:82`: replace `await page.getByLabel("Tingkat").fill("7");` with

```ts
  await page.getByLabel("Tingkat").click();
  await page.getByRole("option").first().click();
```

(e2e is not run in this plan — spec §7.3 — but the spec must not be left describing a field that no longer exists.)

- [ ] **Step 5: Run the tests to verify they pass**

`pnpm vitest run src/lib/schemas/academic-ops.test.ts src/components/features/academic-ops/homeroom-dialog.test.tsx` → 4 passed.
`pnpm typecheck` → no errors. `pnpm lint` → no new errors in touched files.

- [ ] **Step 6: Commit**

```bash
git add src/lib/schemas/academic-ops.ts src/lib/schemas/academic-ops.test.ts src/lib/query/queries/use-academic-ops.ts src/lib/query/mutations/use-academic-ops.ts src/components/features/academic-ops/homerooms-screen.tsx src/components/features/academic-ops/homeroom-dialog.test.tsx playwright/academic-ops.spec.ts
git commit -m "feat(web): pick a grade level for each homeroom"
```

---

### Task 4: Promotion data layer (web)

**Files:**
- Create: `apps/web/src/lib/query/queries/use-promotion.ts`
- Create: `apps/web/src/lib/query/mutations/use-promotion.ts`
- Create: `apps/web/src/lib/schemas/promotion.ts`
- Create: `apps/web/src/lib/schemas/promotion.test.ts`
- Modify: `apps/web/src/lib/errors/messages.ts`
- Create: `apps/web/src/lib/errors/promotion-messages.test.ts`

**Interfaces:**
- Consumes: Task 2 decision fields; API contract `docs/internal/11_integration_contracts/apis/promotion-service-api.md`.
- Produces (types, `use-promotion.ts` queries): `PromotionStatus`, `PromotionResult`, `PromotionRun`, `PromotionCriteria`, `PromotionCounts`, `PlacementEntry`, `PromotionRunDetail`, `PromotionDecision`, `PromotionRunOutcome`, `PROMOTION_QUERY_KEY`.
- Produces (hooks): `usePromotionRuns(academicYearId?)`, `usePromotionRun(runId?)`, `usePromotionDecisions(runId?)`, `usePromotionAccess()` → `{ isLoading, moduleEnabled, canRead, canManage, canApprove, userId }`.
- Produces (mutations, `use-promotion.ts` mutations): `useCreatePromotionRun()`, `useReevaluatePromotionRun(runId)`, `useOverrideDecision(runId)`, `useTransitionPromotionRun(runId)` (variable: `"submit" | "approve" | "return"`), `useSetPromotionTarget(runId)`, `useAssignPromotionTargets(runId)`, `useExecutePromotionRun(runId)`. All invalidate `PROMOTION_QUERY_KEY` **on settled** (success or error), so a `409` refetches the run without extra code.
- Produces (schemas): `criteriaFormSchema`, `type CriteriaForm`, `toCriteriaPayload`, `criteriaToForm`, `PROMOTION_RESULTS`, `overrideSchema(recommended)`, `type OverrideForm`, `targetYearSchema`, `type TargetYearForm`.
- Produces (messages): copy for `PROMOTION_RUN_EXISTS`, `PROMOTION_RUN_INVALID_STATUS`, `PROMOTION_SELF_APPROVAL`; `promotionFieldGroups(error: unknown): { field: string; label: string; messages: string[] }[]`.

- [ ] **Step 1: Write the failing tests**

`src/lib/schemas/promotion.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import {
  criteriaFormSchema,
  criteriaToForm,
  overrideSchema,
  targetYearSchema,
  toCriteriaPayload,
} from "@/lib/schemas/promotion";

describe("criteriaFormSchema", () => {
  it("accepts blanks and in-range numbers", () => {
    expect(criteriaFormSchema.safeParse({ min_average: "", max_subjects_below_kkm: "" }).success).toBe(true);
    expect(criteriaFormSchema.safeParse({ min_average: "70.5", max_subjects_below_kkm: "2" }).success).toBe(true);
  });

  it("rejects out-of-range and non-integer values", () => {
    const result = criteriaFormSchema.safeParse({ min_average: "101", max_subjects_below_kkm: "1.5" });
    expect(result.success).toBe(false);
    if (!result.success) {
      const fields = result.error.flatten().fieldErrors;
      expect(fields.min_average?.[0]).toBe("Isi 0–100 atau kosongkan");
      expect(fields.max_subjects_below_kkm?.[0]).toBe("Isi bilangan bulat 0 atau lebih, atau kosongkan");
    }
  });

  it("converts to the API payload and back", () => {
    expect(toCriteriaPayload({ min_average: " 70 ", max_subjects_below_kkm: "" })).toEqual({
      min_average: 70,
      max_subjects_below_kkm: null,
      min_attendance_percent: null,
    });
    expect(criteriaToForm({ min_average: null, max_subjects_below_kkm: 2, min_attendance_percent: null })).toEqual({
      min_average: "",
      max_subjects_below_kkm: "2",
    });
  });
});

describe("overrideSchema", () => {
  it("needs a 10-character reason when the result differs from the recommendation", () => {
    const schema = overrideSchema("promote");
    const short = schema.safeParse({ result: "retain", reason: "  terlalu " });
    expect(short.success).toBe(false);
    if (!short.success) {
      expect(short.error.flatten().fieldErrors.reason?.[0]).toBe("Alasan minimal 10 karakter");
    }
    expect(schema.safeParse({ result: "retain", reason: "Sering tidak hadir semester 2" }).success).toBe(true);
  });

  it("needs no reason when the result goes back to the recommendation", () => {
    expect(overrideSchema("promote").safeParse({ result: "promote", reason: "" }).success).toBe(true);
  });
});

describe("targetYearSchema", () => {
  it("requires a year", () => {
    expect(targetYearSchema.safeParse({ target_academic_year_id: "" }).success).toBe(false);
    expect(
      targetYearSchema.safeParse({ target_academic_year_id: "11111111-1111-4111-8111-111111111111" }).success,
    ).toBe(true);
  });
});
```

`src/lib/errors/promotion-messages.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import { ApiHttpError } from "@/lib/api/types";
import { getErrorMessage, promotionFieldGroups } from "@/lib/errors/messages";

describe("promotion error copy", () => {
  it("has Indonesian copy for the promotion codes", () => {
    for (const code of ["PROMOTION_RUN_EXISTS", "PROMOTION_RUN_INVALID_STATUS", "PROMOTION_SELF_APPROVAL"]) {
      const message = getErrorMessage(new ApiHttpError(409, { code, message: "english" }));
      expect(message).not.toBe("english");
    }
  });

  it("groups field errors under Indonesian headings in a stable order", () => {
    const error = new ApiHttpError(400, {
      code: "VALIDATION_ERROR",
      message: "invalid",
      fields: {
        enrollments: ["student a is already enrolled in the target academic year"],
        targets: ["student b has no target homeroom"],
        unknown_key: ["something"],
      },
    });
    expect(promotionFieldGroups(error)).toEqual([
      { field: "targets", label: "Tujuan belum lengkap", messages: ["student b has no target homeroom"] },
      {
        field: "enrollments",
        label: "Bentrok enrollment",
        messages: ["student a is already enrolled in the target academic year"],
      },
      { field: "unknown_key", label: "unknown_key", messages: ["something"] },
    ]);
  });

  it("returns no groups for a non-validation error", () => {
    expect(promotionFieldGroups(new Error("boom"))).toEqual([]);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

`pnpm vitest run src/lib/schemas/promotion.test.ts src/lib/errors/promotion-messages.test.ts`

Expected: FAIL — `Failed to resolve import "@/lib/schemas/promotion"` and `promotionFieldGroups` is not exported (`is not a function`). Record both.

- [ ] **Step 3: Schemas**

`src/lib/schemas/promotion.ts`:

```ts
import { z } from "zod";

export const PROMOTION_RESULTS = ["promote", "retain", "graduate"] as const;
export type PromotionResultValue = (typeof PROMOTION_RESULTS)[number];

function isAverage(value: string) {
  if (value === "") return true;
  const n = Number(value);
  return !Number.isNaN(n) && n >= 0 && n <= 100;
}

function isCount(value: string) {
  if (value === "") return true;
  const n = Number(value);
  return Number.isInteger(n) && n >= 0;
}

/** Criteria as typed (strings); keys match the backend so server field errors map. */
export const criteriaFormSchema = z.object({
  min_average: z.string().trim().refine(isAverage, "Isi 0–100 atau kosongkan"),
  max_subjects_below_kkm: z
    .string()
    .trim()
    .refine(isCount, "Isi bilangan bulat 0 atau lebih, atau kosongkan"),
});
export type CriteriaForm = z.infer<typeof criteriaFormSchema>;

export type CriteriaPayload = {
  min_average: number | null;
  max_subjects_below_kkm: number | null;
  min_attendance_percent: null;
};

export function toCriteriaPayload(values: CriteriaForm): CriteriaPayload {
  const average = values.min_average.trim();
  const count = values.max_subjects_below_kkm.trim();
  return {
    min_average: average === "" ? null : Number(average),
    max_subjects_below_kkm: count === "" ? null : Number(count),
    min_attendance_percent: null,
  };
}

export function criteriaToForm(criteria: {
  min_average: number | null;
  max_subjects_below_kkm: number | null;
  min_attendance_percent: number | null;
}): CriteriaForm {
  return {
    min_average: criteria.min_average === null ? "" : String(criteria.min_average),
    max_subjects_below_kkm:
      criteria.max_subjects_below_kkm === null ? "" : String(criteria.max_subjects_below_kkm),
  };
}

/** A reason is required (≥ 10 chars trimmed) unless the result returns to the recommendation. */
export function overrideSchema(recommended: PromotionResultValue) {
  return z
    .object({
      result: z.enum(PROMOTION_RESULTS),
      reason: z.string(),
    })
    .superRefine((value, ctx) => {
      if (value.result !== recommended && value.reason.trim().length < 10) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["reason"], message: "Alasan minimal 10 karakter" });
      }
    });
}
export type OverrideForm = { result: PromotionResultValue; reason: string };

export const targetYearSchema = z.object({
  target_academic_year_id: z.string().uuid("Pilih tahun tujuan"),
});
export type TargetYearForm = z.infer<typeof targetYearSchema>;
```

- [ ] **Step 4: Error copy**

`src/lib/errors/messages.ts` — add to `ERROR_MESSAGES` (alphabetical position near the `P…` keys):

```ts
  PROMOTION_RUN_EXISTS:
    'Sudah ada evaluasi kenaikan kelas yang masih terbuka untuk tahun ajaran ini. Lanjutkan evaluasi tersebut.',
  PROMOTION_RUN_INVALID_STATUS:
    'Status evaluasi sudah berubah, mungkin dari tab atau pengguna lain. Data sudah dimuat ulang; periksa lalu coba lagi.',
  PROMOTION_SELF_APPROVAL:
    'Evaluasi harus disetujui oleh orang lain, bukan oleh pembuatnya.',
```

and after `isApiError`:

```ts
/** Headings for promotion `VALIDATION_ERROR` field keys, in display order. */
const PROMOTION_FIELD_LABELS: [string, string][] = [
  ['academic_year', 'Tahun ajaran'],
  ['grade_levels', 'Tingkat kelas'],
  ['report_type', 'Tipe rapor sumber kenaikan'],
  ['homerooms', 'Kelas belum tertaut ke tingkat'],
  ['grading_policy', 'Kebijakan nilai (KKM)'],
  ['target_academic_year', 'Tahun tujuan'],
  ['target_academic_year_id', 'Tahun tujuan'],
  ['targets', 'Tujuan belum lengkap'],
  ['enrollments', 'Bentrok enrollment'],
  ['target_homerooms', 'Kelas tujuan tidak valid lagi'],
  ['assignments', 'Penempatan'],
];

/**
 * Field errors of a promotion `VALIDATION_ERROR`, grouped under Indonesian
 * headings. Known keys come first in a fixed order; unknown keys follow under
 * their own name so nothing is dropped. Messages are the backend's.
 */
export function promotionFieldGroups(
  error: unknown,
): { field: string; label: string; messages: string[] }[] {
  if (!(error instanceof ApiHttpError) || !error.fields) return [];
  const fields = error.fields;
  const known = PROMOTION_FIELD_LABELS.filter(([field]) => fields[field]?.length).map(
    ([field, label]) => ({ field, label, messages: fields[field] }),
  );
  const knownKeys = new Set(PROMOTION_FIELD_LABELS.map(([field]) => field));
  const unknown = Object.entries(fields)
    .filter(([field, messages]) => !knownKeys.has(field) && messages?.length)
    .map(([field, messages]) => ({ field, label: field, messages }));
  return [...known, ...unknown];
}
```

- [ ] **Step 5: Query hooks**

`src/lib/query/queries/use-promotion.ts`:

```ts
"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";

import { apiFetch } from "@/lib/api/client";
import { useMe } from "@/lib/query/queries/use-me";
import { useTenantMe } from "@/lib/query/queries/use-tenant-me";
import { useTenantPermissions } from "@/lib/query/queries/use-tenant-roles";

export const PROMOTION_QUERY_KEY = ["academic-ops", "promotion"] as const;

export type PromotionStatus = "draft" | "submitted" | "approved" | "executed";
export type PromotionResult = "promote" | "retain" | "graduate";

export type PromotionRun = {
  run_id: string;
  academic_year_id: string;
  report_type_id: string;
  rule_id: string;
  status: PromotionStatus;
  created_by: string;
  approved_by: string | null;
  target_academic_year_id: string | null;
  executed_by: string | null;
  executed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PromotionCriteria = {
  min_average: number | null;
  max_subjects_below_kkm: number | null;
  min_attendance_percent: number | null;
};

export type PromotionCounts = { promote: number; retain: number; graduate: number };

export type PlacementEntry = {
  homeroom_id: string;
  name: string;
  capacity: number;
  existing_active: number;
  assigned: number;
  total: number;
  over_capacity: boolean;
};

export type PromotionRunDetail = {
  run: PromotionRun;
  criteria: PromotionCriteria;
  kkm: number;
  counts: PromotionCounts;
  overridden: number;
  cannot_evaluate: string[];
  placement: PlacementEntry[];
  unassigned: number;
};

export type DecisionMetrics = {
  subjects_counted: number;
  subjects_below_kkm: number;
  average: number | null;
  kkm_used: number;
  criteria: PromotionCriteria;
};

export type PromotionDecision = {
  decision_id: string;
  student_id: string;
  homeroom_id: string;
  recommended: PromotionResult;
  result: PromotionResult;
  overridden: boolean;
  reason: string | null;
  computed_metrics: DecisionMetrics;
  target_homeroom_id: string | null;
  target_enrollment_id: string | null;
  full_name: string | null;
  nis: string | null;
  homeroom_name: string | null;
  source_ordinal: number | null;
};

/** Response of create and re-evaluate. */
export type PromotionRunOutcome = {
  run_id: string;
  status: PromotionStatus;
  report_type_id: string;
  rule_id: string;
  counts: PromotionCounts;
  cannot_evaluate: string[];
  discarded_overrides: number;
};

const BASE = "/api/v1/academic-ops/promotion-runs";

export function usePromotionRuns(academicYearId?: string) {
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "runs", academicYearId],
    queryFn: () =>
      apiFetch<PromotionRun[]>({
        service: "academic-ops",
        path: `${BASE}?academic_year_id=${academicYearId}`,
        authenticated: true,
      }),
    enabled: Boolean(academicYearId),
  });
}

export function usePromotionRun(runId?: string) {
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "run", runId],
    queryFn: () =>
      apiFetch<PromotionRunDetail>({ service: "academic-ops", path: `${BASE}/${runId}`, authenticated: true }),
    enabled: Boolean(runId),
  });
}

export function usePromotionDecisions(runId?: string) {
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "decisions", runId],
    queryFn: () =>
      apiFetch<PromotionDecision[]>({
        service: "academic-ops",
        path: `${BASE}/${runId}/decisions`,
        authenticated: true,
      }),
    enabled: Boolean(runId),
  });
}

/** Who may see and act on promotion runs (spec §4.2). */
export function usePromotionAccess() {
  const tenant = useTenantMe();
  const permissions = useTenantPermissions();
  const me = useMe();
  return React.useMemo(() => {
    const held = new Set((permissions.data ?? []).filter((p) => p.held).map((p) => p.code));
    const ops = tenant.data?.modules.find((m) => m.feature_code === "academic_ops");
    const canManage = held.has("promotion.manage");
    const canApprove = held.has("promotion.approve");
    return {
      isLoading: tenant.isLoading || permissions.isLoading || me.isLoading,
      moduleEnabled: Boolean(ops?.plan_entitled && ops.enabled),
      canRead: canManage || canApprove,
      canManage,
      canApprove,
      userId: me.data?.user_id ?? null,
    };
  }, [tenant.data, tenant.isLoading, permissions.data, permissions.isLoading, me.data, me.isLoading]);
}
```

- [ ] **Step 6: Mutation hooks**

`src/lib/query/mutations/use-promotion.ts`:

```ts
"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";

import { apiFetch } from "@/lib/api/client";
import { HOMEROOMS_QUERY_KEY } from "@/lib/query/queries/use-academic-ops";
import {
  PROMOTION_QUERY_KEY,
  type PromotionDecision,
  type PromotionRun,
  type PromotionRunOutcome,
} from "@/lib/query/queries/use-promotion";
import type { CriteriaPayload, PromotionResultValue } from "@/lib/schemas/promotion";

const BASE = "/api/v1/academic-ops/promotion-runs";

/** Every promotion write refetches promotion data on success *and* error, so a 409 shows fresh state. */
function useSettle() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: PROMOTION_QUERY_KEY });
}

export function useCreatePromotionRun() {
  const settle = useSettle();
  return useMutation({
    mutationFn: (input: CriteriaPayload & { academic_year_id: string }) =>
      apiFetch<PromotionRunOutcome>({ service: "academic-ops", path: BASE, method: "POST", authenticated: true, body: input }),
    onSettled: settle,
  });
}

export function useReevaluatePromotionRun(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: (input: CriteriaPayload) =>
      apiFetch<PromotionRunOutcome>({
        service: "academic-ops",
        path: `${BASE}/${runId}/evaluate`,
        method: "POST",
        authenticated: true,
        body: input,
      }),
    onSettled: settle,
  });
}

export function useOverrideDecision(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: ({ decisionId, result, reason }: { decisionId: string; result: PromotionResultValue; reason: string }) =>
      apiFetch<PromotionDecision>({
        service: "academic-ops",
        path: `${BASE}/${runId}/decisions/${decisionId}`,
        method: "PATCH",
        authenticated: true,
        body: { result, reason: reason.trim() === "" ? null : reason.trim() },
      }),
    onSettled: settle,
  });
}

export type PromotionTransition = "submit" | "approve" | "return";

export function useTransitionPromotionRun(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: (action: PromotionTransition) =>
      apiFetch<PromotionRun>({ service: "academic-ops", path: `${BASE}/${runId}/${action}`, method: "POST", authenticated: true, body: {} }),
    onSettled: settle,
  });
}

export function useSetPromotionTarget(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: (targetAcademicYearId: string) =>
      apiFetch<PromotionRun & { cleared_targets: number }>({
        service: "academic-ops",
        path: `${BASE}/${runId}/target`,
        method: "PUT",
        authenticated: true,
        body: { target_academic_year_id: targetAcademicYearId },
      }),
    onSettled: settle,
  });
}

export type TargetAssignment = { decision_id: string; homeroom_id: string | null };

export function useAssignPromotionTargets(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: (assignments: TargetAssignment[]) =>
      apiFetch<{ updated: number }>({
        service: "academic-ops",
        path: `${BASE}/${runId}/targets`,
        method: "PATCH",
        authenticated: true,
        body: { assignments },
      }),
    onSettled: settle,
  });
}

export type ExecutionCounts = { promoted: number; retained: number; graduated: number };

export function useExecutePromotionRun(runId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () =>
      apiFetch<PromotionRun & { counts: ExecutionCounts }>({
        service: "academic-ops",
        path: `${BASE}/${runId}/execute`,
        method: "POST",
        authenticated: true,
        body: {},
      }),
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: PROMOTION_QUERY_KEY });
      // Enrolled counts of source and target homerooms change.
      void qc.invalidateQueries({ queryKey: HOMEROOMS_QUERY_KEY });
    },
  });
}
```

- [ ] **Step 7: Run the tests to verify they pass**

`pnpm vitest run src/lib/schemas/promotion.test.ts src/lib/errors/promotion-messages.test.ts` → all pass.
`pnpm typecheck` → clean.

- [ ] **Step 8: Commit**

```bash
git add src/lib/query/queries/use-promotion.ts src/lib/query/mutations/use-promotion.ts src/lib/schemas/promotion.ts src/lib/schemas/promotion.test.ts src/lib/errors/messages.ts src/lib/errors/promotion-messages.test.ts
git commit -m "feat(web): add promotion queries, mutations, schemas and error copy"
```

---

### Task 5: Placement logic (web, pure)

**Files:**
- Create: `apps/web/src/lib/promotion/placement.ts`
- Create: `apps/web/src/lib/promotion/placement.test.ts`

**Interfaces:**
- Consumes: `PromotionDecision`, `PromotionResult` (Task 4); `Homeroom` (Task 3).
- Produces:
  - `expectedOrdinal(result: PromotionResult, sourceOrdinal: number | null): number | null`
  - `eligibleHomerooms(decision: Pick<PromotionDecision, "result" | "source_ordinal">, homerooms: Homeroom[], targetYearId: string): Homeroom[]` (sorted by name)
  - `type PlacementDraft = { values: Record<string, string | null>; corrected: ReadonlySet<string> }`, `EMPTY_DRAFT`
  - `effectiveTarget(decision: Pick<PromotionDecision, "decision_id" | "target_homeroom_id">, draft: PlacementDraft): string | null`
  - `setStudentTarget(draft, decisionId: string, homeroomId: string | null): PlacementDraft` (marks corrected)
  - `applyClassDefault(draft, decisions: PromotionDecision[], sourceHomeroomId: string, result: "promote" | "retain", homeroomId: string): PlacementDraft` (skips corrected; does not mark)
  - `draftChanges(draft, decisions: PromotionDecision[]): { decision_id: string; homeroom_id: string | null }[]` (only values that differ from the server)
  - `mapAssignmentErrors(messages: string[], knownIds: ReadonlySet<string>): { byDecision: Record<string, string[]>; unmatched: string[] }`
  - `withStudentNames(message: string, names: ReadonlyMap<string, string>): string`
  - `groupBySourceHomeroom(decisions: PromotionDecision[]): { homeroom_id: string; homeroom_name: string; source_ordinal: number | null; decisions: PromotionDecision[] }[]` (ordinal ascending, unknown ordinal last, then name; decisions by name then NIS)

- [ ] **Step 1: Write the failing tests**

`src/lib/promotion/placement.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import type { Homeroom } from "@/lib/query/queries/use-academic-ops";
import type { PromotionDecision } from "@/lib/query/queries/use-promotion";
import {
  EMPTY_DRAFT,
  applyClassDefault,
  draftChanges,
  effectiveTarget,
  eligibleHomerooms,
  expectedOrdinal,
  groupBySourceHomeroom,
  mapAssignmentErrors,
  setStudentTarget,
  withStudentNames,
} from "@/lib/promotion/placement";

const TARGET_YEAR = "year-t";
const D1 = "11111111-1111-4111-8111-111111111111";
const D2 = "22222222-2222-4222-8222-222222222222";
const D3 = "33333333-3333-4333-8333-333333333333";

function homeroom(id: string, name: string, ordinal: number | null, year = TARGET_YEAR): Homeroom {
  return {
    homeroom_id: id,
    name,
    grade_level: "x",
    grade_level_id: ordinal === null ? null : `gl-${ordinal}`,
    ordinal,
    capacity: 30,
    academic_year_id: year,
    enrolled_count: 0,
    homeroom_teacher_id: null,
  };
}

function decision(partial: Partial<PromotionDecision> & { decision_id: string }): PromotionDecision {
  return {
    student_id: `s-${partial.decision_id}`,
    homeroom_id: "src-a",
    recommended: "promote",
    result: "promote",
    overridden: false,
    reason: null,
    computed_metrics: {
      subjects_counted: 1,
      subjects_below_kkm: 0,
      average: 80,
      kkm_used: 75,
      criteria: { min_average: null, max_subjects_below_kkm: null, min_attendance_percent: null },
    },
    target_homeroom_id: null,
    target_enrollment_id: null,
    full_name: "Siswa",
    nis: "1",
    homeroom_name: "X-1",
    source_ordinal: 1,
    ...partial,
  };
}

describe("expectedOrdinal", () => {
  it("is source + 1 to promote, the same to retain, none to graduate", () => {
    expect(expectedOrdinal("promote", 1)).toBe(2);
    expect(expectedOrdinal("retain", 1)).toBe(1);
    expect(expectedOrdinal("graduate", 3)).toBeNull();
    expect(expectedOrdinal("promote", null)).toBeNull();
  });
});

describe("eligibleHomerooms", () => {
  const rooms = [
    homeroom("t-xi-b", "XI-B", 2),
    homeroom("t-xi-a", "XI-A", 2),
    homeroom("t-x-a", "X-A", 1),
    homeroom("t-none", "Unlinked", null),
    homeroom("old-xi", "XI-Old", 2, "year-s"),
  ];

  it("keeps target-year homerooms with the expected ordinal, sorted by name", () => {
    const ids = eligibleHomerooms({ result: "promote", source_ordinal: 1 }, rooms, TARGET_YEAR).map((h) => h.homeroom_id);
    expect(ids).toEqual(["t-xi-a", "t-xi-b"]);
    expect(eligibleHomerooms({ result: "retain", source_ordinal: 1 }, rooms, TARGET_YEAR).map((h) => h.homeroom_id)).toEqual([
      "t-x-a",
    ]);
  });

  it("offers nothing when the source ordinal is unknown or the student graduates", () => {
    expect(eligibleHomerooms({ result: "promote", source_ordinal: null }, rooms, TARGET_YEAR)).toEqual([]);
    expect(eligibleHomerooms({ result: "graduate", source_ordinal: 3 }, rooms, TARGET_YEAR)).toEqual([]);
  });
});

describe("draft", () => {
  const decisions = [
    decision({ decision_id: D1, result: "promote" }),
    decision({ decision_id: D2, result: "promote", target_homeroom_id: "t-xi-b" }),
    decision({ decision_id: D3, result: "retain" }),
  ];

  it("applyClassDefault fills students of that result and skips corrected decisions", () => {
    let draft = setStudentTarget(EMPTY_DRAFT, D2, "t-xi-c");
    draft = applyClassDefault(draft, decisions, "src-a", "promote", "t-xi-a");
    expect(effectiveTarget(decisions[0], draft)).toBe("t-xi-a");
    expect(effectiveTarget(decisions[1], draft)).toBe("t-xi-c");
    expect(effectiveTarget(decisions[2], draft)).toBeNull();
  });

  it("applyClassDefault only touches the given source homeroom", () => {
    const other = decision({ decision_id: "d-other", homeroom_id: "src-b" });
    const draft = applyClassDefault(EMPTY_DRAFT, [...decisions, other], "src-a", "promote", "t-xi-a");
    expect(effectiveTarget(other, draft)).toBeNull();
  });

  it("draftChanges sends only values that differ from the server, null clears", () => {
    let draft = setStudentTarget(EMPTY_DRAFT, D1, "t-xi-a");
    draft = setStudentTarget(draft, D2, "t-xi-b"); // same as server
    draft = setStudentTarget(draft, D3, null); // same as server (null)
    expect(draftChanges(draft, decisions)).toEqual([{ decision_id: D1, homeroom_id: "t-xi-a" }]);
    const cleared = setStudentTarget(EMPTY_DRAFT, D2, null);
    expect(draftChanges(cleared, decisions)).toEqual([{ decision_id: D2, homeroom_id: null }]);
  });
});

describe("mapAssignmentErrors", () => {
  it("puts each decision message on its row and keeps the rest", () => {
    const result = mapAssignmentErrors(
      [
        `decision ${D1}: homeroom XI-A is ordinal 2, expected 1`,
        `decision ${D2}: assigned more than once`,
        `decision ${D3}: not in this run`,
        "at most 2000 assignments per request",
      ],
      new Set([D1, D2]),
    );
    expect(result.byDecision).toEqual({
      [D1]: ["homeroom XI-A is ordinal 2, expected 1"],
      [D2]: ["assigned more than once"],
    });
    expect(result.unmatched).toEqual([
      `decision ${D3}: not in this run`,
      "at most 2000 assignments per request",
    ]);
  });
});

describe("withStudentNames", () => {
  it("replaces known student ids and leaves unknown ones", () => {
    const names = new Map([[D1, "Ani"]]);
    expect(withStudentNames(`student ${D1} has no target homeroom`, names)).toBe("Ani has no target homeroom");
    expect(withStudentNames(`student ${D1}'s enrollment is no longer active`, names)).toBe(
      "Ani's enrollment is no longer active",
    );
    expect(withStudentNames(`student ${D2} has no target homeroom`, names)).toBe(`student ${D2} has no target homeroom`);
  });
});

describe("groupBySourceHomeroom", () => {
  it("orders by ordinal (unknown last), then name; students by name then NIS", () => {
    const groups = groupBySourceHomeroom([
      decision({ decision_id: "a", homeroom_id: "h2", homeroom_name: "XI-A", source_ordinal: 2, full_name: "Budi", nis: "2" }),
      decision({ decision_id: "b", homeroom_id: "h1", homeroom_name: "X-B", source_ordinal: 1, full_name: "Ani", nis: "1" }),
      decision({ decision_id: "c", homeroom_id: "h0", homeroom_name: "Lama", source_ordinal: null, full_name: "Cici", nis: "3" }),
      decision({ decision_id: "d", homeroom_id: "h1b", homeroom_name: "X-A", source_ordinal: 1, full_name: "Dodi", nis: "4" }),
      decision({ decision_id: "e", homeroom_id: "h1", homeroom_name: "X-B", source_ordinal: 1, full_name: "Ani", nis: "0" }),
    ]);
    expect(groups.map((g) => g.homeroom_name)).toEqual(["X-A", "X-B", "XI-A", "Lama"]);
    expect(groups[1].decisions.map((d) => d.decision_id)).toEqual(["e", "b"]);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

`pnpm vitest run src/lib/promotion/placement.test.ts`
Expected: FAIL — `Failed to resolve import "@/lib/promotion/placement"`.

- [ ] **Step 3: Implement**

`src/lib/promotion/placement.ts`:

```ts
import type { Homeroom } from "@/lib/query/queries/use-academic-ops";
import type { PromotionDecision, PromotionResult } from "@/lib/query/queries/use-promotion";

/** Grade levels match across years by ordinal (Plan 3c spec §2.8). */
export function expectedOrdinal(result: PromotionResult, sourceOrdinal: number | null): number | null {
  if (sourceOrdinal === null || result === "graduate") return null;
  return result === "promote" ? sourceOrdinal + 1 : sourceOrdinal;
}

export function eligibleHomerooms(
  decision: Pick<PromotionDecision, "result" | "source_ordinal">,
  homerooms: Homeroom[],
  targetYearId: string,
): Homeroom[] {
  const ordinal = expectedOrdinal(decision.result, decision.source_ordinal);
  if (ordinal === null) return [];
  return homerooms
    .filter((h) => h.academic_year_id === targetYearId && h.ordinal === ordinal)
    .sort((a, b) => a.name.localeCompare(b.name, "id"));
}

/** Unsaved targets. `corrected` = decisions the admin set one by one. */
export type PlacementDraft = {
  values: Record<string, string | null>;
  corrected: ReadonlySet<string>;
};

export const EMPTY_DRAFT: PlacementDraft = { values: {}, corrected: new Set() };

export function effectiveTarget(
  decision: Pick<PromotionDecision, "decision_id" | "target_homeroom_id">,
  draft: PlacementDraft,
): string | null {
  return decision.decision_id in draft.values
    ? draft.values[decision.decision_id]
    : decision.target_homeroom_id;
}

export function setStudentTarget(draft: PlacementDraft, decisionId: string, homeroomId: string | null): PlacementDraft {
  const corrected = new Set(draft.corrected);
  corrected.add(decisionId);
  return { values: { ...draft.values, [decisionId]: homeroomId }, corrected };
}

export function applyClassDefault(
  draft: PlacementDraft,
  decisions: PromotionDecision[],
  sourceHomeroomId: string,
  result: "promote" | "retain",
  homeroomId: string,
): PlacementDraft {
  const values = { ...draft.values };
  for (const d of decisions) {
    if (d.homeroom_id !== sourceHomeroomId || d.result !== result) continue;
    if (draft.corrected.has(d.decision_id)) continue;
    values[d.decision_id] = homeroomId;
  }
  return { values, corrected: draft.corrected };
}

export function draftChanges(
  draft: PlacementDraft,
  decisions: PromotionDecision[],
): { decision_id: string; homeroom_id: string | null }[] {
  const changes: { decision_id: string; homeroom_id: string | null }[] = [];
  for (const d of decisions) {
    if (!(d.decision_id in draft.values)) continue;
    const value = draft.values[d.decision_id];
    if (value !== d.target_homeroom_id) changes.push({ decision_id: d.decision_id, homeroom_id: value });
  }
  return changes;
}

const DECISION_PREFIX = /^decision ([0-9a-f-]{36}): (.*)$/i;

export function mapAssignmentErrors(
  messages: string[],
  knownIds: ReadonlySet<string>,
): { byDecision: Record<string, string[]>; unmatched: string[] } {
  const byDecision: Record<string, string[]> = {};
  const unmatched: string[] = [];
  for (const message of messages) {
    const match = DECISION_PREFIX.exec(message);
    if (match && knownIds.has(match[1])) {
      (byDecision[match[1]] ??= []).push(match[2]);
    } else {
      unmatched.push(message);
    }
  }
  return { byDecision, unmatched };
}

const STUDENT_ID = /student ([0-9a-f-]{36})/gi;

/** Replaces `student <id>` with the student's name when known. */
export function withStudentNames(message: string, names: ReadonlyMap<string, string>): string {
  return message.replace(STUDENT_ID, (whole, id: string) => names.get(id) ?? whole);
}

export function groupBySourceHomeroom(decisions: PromotionDecision[]): {
  homeroom_id: string;
  homeroom_name: string;
  source_ordinal: number | null;
  decisions: PromotionDecision[];
}[] {
  const groups = new Map<string, { homeroom_id: string; homeroom_name: string; source_ordinal: number | null; decisions: PromotionDecision[] }>();
  for (const d of decisions) {
    const group = groups.get(d.homeroom_id) ?? {
      homeroom_id: d.homeroom_id,
      homeroom_name: d.homeroom_name ?? "—",
      source_ordinal: d.source_ordinal,
      decisions: [],
    };
    group.decisions.push(d);
    groups.set(d.homeroom_id, group);
  }
  const byStudent = (a: PromotionDecision, b: PromotionDecision) =>
    (a.full_name ?? "").localeCompare(b.full_name ?? "", "id") || (a.nis ?? "").localeCompare(b.nis ?? "", "id");
  return [...groups.values()]
    .map((g) => ({ ...g, decisions: [...g.decisions].sort(byStudent) }))
    .sort((a, b) => {
      const ao = a.source_ordinal ?? Number.POSITIVE_INFINITY;
      const bo = b.source_ordinal ?? Number.POSITIVE_INFINITY;
      return ao - bo || a.homeroom_name.localeCompare(b.homeroom_name, "id");
    });
}
```

- [ ] **Step 4: Run the tests to verify they pass**

`pnpm vitest run src/lib/promotion/placement.test.ts` → all pass. `pnpm typecheck` → clean.

- [ ] **Step 5: Commit**

```bash
git add src/lib/promotion
git commit -m "feat(web): add pure promotion placement logic"
```

---

### Task 6: Navigation, routes, runs list and criteria dialog (web)

**Files:**
- Modify: `apps/web/src/components/layout/sidebar-layout.tsx` (`VisibilityRule` ~40, `navEntries` "Akademik" group ~99–110, `checkVisibility` ~139; export `checkVisibility` for tests)
- Create: `apps/web/src/components/layout/sidebar-visibility.test.ts`
- Create: `apps/web/src/components/features/promotion/promotion-page.tsx` (auth + sidebar shell + access guard)
- Create: `apps/web/src/components/features/promotion/labels.ts` (status/result labels, badge variants)
- Create: `apps/web/src/components/features/promotion/criteria-dialog.tsx`
- Create: `apps/web/src/components/features/promotion/runs-screen.tsx`
- Create: `apps/web/src/components/features/promotion/runs-screen.test.tsx`
- Create: `apps/web/src/app/promotion/page.tsx`

**Interfaces:**
- Consumes: Task 4 hooks/types/schemas, `promotionFieldGroups`, `getErrorMessage`, `isApiError`.
- Produces: `VisibilityRule` variant `{ kind: "moduleAndAnyPermission"; featureCode: string; permissionCodes: string[] }`; `export function checkVisibility(rule, heldPermissions: Set<string>, enabledModules: Set<string>): boolean`.
- Produces: `PromotionPage({ title, description, children: (access) => ReactNode })` where `access` is the `usePromotionAccess()` result; redirects to `/dashboard` when the user holds neither permission; shows an Alert when the `academic_ops` module is off.
- Produces: `STATUS_LABEL: Record<PromotionStatus, string>`, `RESULT_LABEL: Record<PromotionResult, string>`, `statusBadgeVariant(status): "default" | "secondary" | "outline"`.
- Produces: `CriteriaDialog({ open, onOpenChange, mode: "create" | "reevaluate", academicYearId?, runId?, initial?: PromotionCriteria, overriddenCount?: number, onCreated?: (runId: string) => void })`.
- Produces: `RunsScreen({ canManage }: { canManage: boolean })`.

Labels (spec §4.3): status `draft` "Draft", `submitted` "Diajukan", `approved` "Disetujui", `executed` "Dieksekusi"; result `promote` "Naik", `retain` "Tinggal", `graduate` "Lulus".

- [ ] **Step 1: Write the failing tests**

`src/components/layout/sidebar-visibility.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import { checkVisibility } from "@/components/layout/sidebar-layout";

describe("checkVisibility moduleAndAnyPermission", () => {
  const rule = {
    kind: "moduleAndAnyPermission" as const,
    featureCode: "academic_ops",
    permissionCodes: ["promotion.manage", "promotion.approve"],
  };

  it("shows the entry to a holder of either permission when the module is on", () => {
    expect(checkVisibility(rule, new Set(["promotion.approve"]), new Set(["academic_ops"]))).toBe(true);
    expect(checkVisibility(rule, new Set(["promotion.manage"]), new Set(["academic_ops"]))).toBe(true);
  });

  it("hides it without a permission or without the module", () => {
    expect(checkVisibility(rule, new Set(["grade.read"]), new Set(["academic_ops"]))).toBe(false);
    expect(checkVisibility(rule, new Set(["promotion.manage"]), new Set())).toBe(false);
  });
});
```

`src/components/features/promotion/runs-screen.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const runs = vi.hoisted(() => ({ data: [] as unknown[] }));
const YEAR = "11111111-1111-4111-8111-111111111111";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock("@/hooks/use-academic-scope", () => ({ useAcademicScope: () => ({ yearId: YEAR }) }));
vi.mock("@/lib/query/queries/use-academic-config", () => ({
  useAcademicYears: () => ({ data: [{ academic_year_id: YEAR, name: "2025/2026", status: "Active" }], isLoading: false }),
}));
vi.mock("@/lib/query/queries/use-promotion", () => ({
  usePromotionRuns: () => ({ data: runs.data, isLoading: false, error: null }),
}));
vi.mock("@/lib/query/mutations/use-promotion", () => ({
  useCreatePromotionRun: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useReevaluatePromotionRun: () => ({ mutateAsync: vi.fn(), isPending: false }),
}));

import { RunsScreen } from "@/components/features/promotion/runs-screen";

function run(status: string, id: string) {
  return {
    run_id: id,
    academic_year_id: YEAR,
    status,
    created_at: "2026-06-01T00:00:00Z",
    created_by: "u",
    approved_by: null,
    executed_at: null,
  };
}

describe("RunsScreen", () => {
  it("offers to create a run when the year has no open run", () => {
    runs.data = [run("executed", "r-old")];
    render(<RunsScreen canManage />);
    expect(screen.getByRole("button", { name: "Buat evaluasi" })).toBeInTheDocument();
  });

  it("links to the open run instead of offering a second one", () => {
    runs.data = [run("submitted", "r-open")];
    render(<RunsScreen canManage />);
    expect(screen.queryByRole("button", { name: "Buat evaluasi" })).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Buka evaluasi berjalan" })).toHaveAttribute("href", "/promotion/r-open");
  });

  it("never offers create without promotion.manage", () => {
    runs.data = [];
    render(<RunsScreen canManage={false} />);
    expect(screen.queryByRole("button", { name: "Buat evaluasi" })).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

`pnpm vitest run src/components/layout/sidebar-visibility.test.ts src/components/features/promotion/runs-screen.test.tsx`
Expected: FAIL — `checkVisibility` is not exported (`is not a function`); `runs-screen` import does not resolve. Record both.

- [ ] **Step 3: Sidebar**

`sidebar-layout.tsx`:

```ts
type VisibilityRule =
  | { kind: "always"; }
  | { kind: "permission"; code: string; }
  | { kind: "module"; featureCode: string; }
  | { kind: "moduleAndPermission"; featureCode: string; permissionCode: string; }
  | { kind: "moduleAndAnyPermission"; featureCode: string; permissionCodes: string[]; };
```

`checkVisibility` becomes `export function checkVisibility(...)` and gains:

```ts
    case "moduleAndAnyPermission":
      return (
        enabledModules.has(rule.featureCode) &&
        rule.permissionCodes.some((code) => heldPermissions.has(code))
      );
```

Add `TrendingUp` to the `lucide-react` import and a third child to the "Akademik" group:

```ts
        { href: "/promotion", label: "Kenaikan Kelas", icon: TrendingUp, activePrefixes: ["/promotion"], visibility: { kind: "moduleAndAnyPermission", featureCode: "academic_ops", permissionCodes: ["promotion.manage", "promotion.approve"] } },
```

- [ ] **Step 4: Labels and page shell**

`src/components/features/promotion/labels.ts`:

```ts
import type { PromotionResult, PromotionStatus } from "@/lib/query/queries/use-promotion";

export const STATUS_LABEL: Record<PromotionStatus, string> = {
  draft: "Draft",
  submitted: "Diajukan",
  approved: "Disetujui",
  executed: "Dieksekusi",
};

export const STATUS_ORDER: PromotionStatus[] = ["draft", "submitted", "approved", "executed"];

export const RESULT_LABEL: Record<PromotionResult, string> = {
  promote: "Naik",
  retain: "Tinggal",
  graduate: "Lulus",
};

export function statusBadgeVariant(status: PromotionStatus): "default" | "secondary" | "outline" {
  if (status === "executed") return "secondary";
  if (status === "approved") return "default";
  return "outline";
}
```

`src/components/features/promotion/promotion-page.tsx` (mirrors `AcademicOpsPage`'s shell, but guards on *either* permission):

```tsx
"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

import { AuthGuard } from "@/components/features/auth-guard";
import { SidebarLayout } from "@/components/layout/sidebar-layout";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { DataTableCard } from "@/components/ui/data-table-card";
import { Skeleton } from "@/components/ui/skeleton";
import { useLogout } from "@/lib/query/mutations/use-logout";
import { useMe } from "@/lib/query/queries/use-me";
import { usePromotionAccess } from "@/lib/query/queries/use-promotion";
import { useTenantMe } from "@/lib/query/queries/use-tenant-me";

export type PromotionAccess = ReturnType<typeof usePromotionAccess>;

function PageSkeleton({ title, description }: { title: string; description: string }) {
  return (
    <DataTableCard title={title} description={description}>
      <div className="space-y-2 px-4 pb-4">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </div>
    </DataTableCard>
  );
}

export function PromotionPage({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: (access: PromotionAccess) => React.ReactNode;
}) {
  return (
    <AuthGuard
      fallback={
        <SidebarLayout className="mx-auto w-full">
          <PageSkeleton title={title} description={description} />
        </SidebarLayout>
      }
    >
      <PromotionShell title={title} description={description}>
        {children}
      </PromotionShell>
    </AuthGuard>
  );
}

function PromotionShell({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: (access: PromotionAccess) => React.ReactNode;
}) {
  const tenant = useTenantMe();
  const me = useMe();
  const logout = useLogout();
  const router = useRouter();
  const access = usePromotionAccess();

  React.useEffect(() => {
    if (!access.isLoading && !access.canRead) router.replace("/dashboard");
  }, [access.isLoading, access.canRead, router]);

  return (
    <SidebarLayout
      schoolName={tenant.data?.school_name}
      userName={me.data?.full_name}
      userEmail={me.data?.email}
      isLoggingOut={logout.isPending}
      onLogout={async () => {
        await logout.mutateAsync();
        router.push("/login");
      }}
      className="mx-auto w-full"
    >
      {access.isLoading || !access.canRead ? (
        <PageSkeleton title={title} description={description} />
      ) : !access.moduleEnabled ? (
        <Alert>
          <AlertTitle>Modul belum aktif</AlertTitle>
          <AlertDescription>
            Kenaikan kelas memakai modul Operasional Akademik. Aktifkan modul atau cek paket langganan.
          </AlertDescription>
        </Alert>
      ) : (
        children(access)
      )}
    </SidebarLayout>
  );
}
```

- [ ] **Step 5: Criteria dialog**

`src/components/features/promotion/criteria-dialog.tsx`:

```tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Form, FormControl, FormDescription, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toaster";
import { getErrorMessage, isApiError, promotionFieldGroups } from "@/lib/errors/messages";
import { useCreatePromotionRun, useReevaluatePromotionRun } from "@/lib/query/mutations/use-promotion";
import type { PromotionCriteria } from "@/lib/query/queries/use-promotion";
import { criteriaFormSchema, criteriaToForm, toCriteriaPayload, type CriteriaForm } from "@/lib/schemas/promotion";

const CRITERIA_FIELDS = new Set(["min_average", "max_subjects_below_kkm", "min_attendance_percent"]);

export function CriteriaDialog({
  open,
  onOpenChange,
  mode,
  academicYearId,
  runId,
  initial,
  overriddenCount = 0,
  existingRunId,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode: "create" | "reevaluate";
  academicYearId?: string;
  runId?: string;
  initial?: PromotionCriteria;
  overriddenCount?: number;
  existingRunId?: string;
  onCreated?: (runId: string) => void;
}) {
  const create = useCreatePromotionRun();
  const reevaluate = useReevaluatePromotionRun(runId ?? "");
  const [failure, setFailure] = React.useState<unknown>(null);
  const form = useForm<CriteriaForm>({
    resolver: zodResolver(criteriaFormSchema),
    defaultValues: initial ? criteriaToForm(initial) : { min_average: "", max_subjects_below_kkm: "" },
  });

  React.useEffect(() => {
    if (open) {
      form.reset(initial ? criteriaToForm(initial) : { min_average: "", max_subjects_below_kkm: "" });
      setFailure(null);
    }
  }, [open, initial, form]);

  const pending = create.isPending || reevaluate.isPending;

  async function onSubmit(values: CriteriaForm) {
    setFailure(null);
    const payload = toCriteriaPayload(values);
    try {
      if (mode === "create") {
        const outcome = await create.mutateAsync({ ...payload, academic_year_id: academicYearId! });
        toast.success("Evaluasi dibuat.");
        onOpenChange(false);
        onCreated?.(outcome.run_id);
      } else {
        const outcome = await reevaluate.mutateAsync(payload);
        toast.success(
          outcome.discarded_overrides > 0
            ? `Evaluasi diulang. ${outcome.discarded_overrides} keputusan override hilang.`
            : "Evaluasi diulang.",
        );
        onOpenChange(false);
      }
    } catch (error) {
      const groups = promotionFieldGroups(error);
      for (const group of groups) {
        if (CRITERIA_FIELDS.has(group.field)) {
          form.setError(group.field as keyof CriteriaForm, { type: "server", message: group.messages[0] });
        }
      }
      setFailure(error);
    }
  }

  const preconditions = promotionFieldGroups(failure).filter((g) => !CRITERIA_FIELDS.has(g.field));
  const exists = isApiError(failure, "PROMOTION_RUN_EXISTS");

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{mode === "create" ? "Buat evaluasi kenaikan kelas" : "Evaluasi ulang"}</DialogTitle>
          <DialogDescription>
            Kriteria yang kosong dilewati. Semua kriteria yang diisi harus terpenuhi agar siswa naik kelas.
          </DialogDescription>
        </DialogHeader>
        {mode === "reevaluate" && overriddenCount > 0 ? (
          <Alert>
            <AlertTitle>Override akan hilang</AlertTitle>
            <AlertDescription>
              {overriddenCount} keputusan yang di-override akan hilang dan dihitung ulang dari nilai.
            </AlertDescription>
          </Alert>
        ) : null}
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
            <FormField
              control={form.control}
              name="min_average"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Rata-rata minimum</FormLabel>
                  <FormControl>
                    <Input inputMode="decimal" placeholder="mis. 70" {...field} />
                  </FormControl>
                  <FormDescription>Siswa tinggal kelas bila rata-rata nilai akhirnya di bawah angka ini.</FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="max_subjects_below_kkm"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Maksimum mapel di bawah KKM</FormLabel>
                  <FormControl>
                    <Input inputMode="numeric" placeholder="mis. 2" {...field} />
                  </FormControl>
                  <FormDescription>Siswa tinggal kelas bila jumlah mapel di bawah KKM lebih dari angka ini.</FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />
            <div className="space-y-1.5">
              <p className="text-sm font-medium leading-none text-muted-foreground">Kehadiran minimum</p>
              <Input disabled placeholder="Belum tersedia" aria-label="Kehadiran minimum" />
              <p className="text-xs text-muted-foreground">Menunggu modul absensi.</p>
            </div>
            {exists ? (
              <Alert variant="destructive">
                <AlertTitle>{getErrorMessage(failure)}</AlertTitle>
                {existingRunId ? (
                  <AlertDescription>
                    <Link href={`/promotion/${existingRunId}`} className="underline">
                      Buka evaluasi berjalan
                    </Link>
                  </AlertDescription>
                ) : null}
              </Alert>
            ) : preconditions.length > 0 ? (
              <Alert variant="destructive">
                <AlertTitle>Evaluasi belum bisa dijalankan</AlertTitle>
                <AlertDescription>
                  <ul className="list-disc space-y-1 pl-4">
                    {preconditions.map((group) => (
                      <li key={group.field}>
                        <span className="font-medium">{group.label}:</span> {group.messages.join("; ")}
                      </li>
                    ))}
                  </ul>
                </AlertDescription>
              </Alert>
            ) : failure && !isApiError(failure, "VALIDATION_ERROR") ? (
              <Alert variant="destructive">
                <AlertDescription>{getErrorMessage(failure, { fallback: "Evaluasi gagal." })}</AlertDescription>
              </Alert>
            ) : null}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Batal
              </Button>
              <Button type="submit" loading={pending}>
                {mode === "create" ? "Jalankan evaluasi" : "Evaluasi ulang"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 6: Runs screen and route**

`src/components/features/promotion/runs-screen.tsx`:

```tsx
"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { CriteriaDialog } from "@/components/features/promotion/criteria-dialog";
import { STATUS_LABEL, statusBadgeVariant } from "@/components/features/promotion/labels";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTableCard } from "@/components/ui/data-table-card";
import { Combobox } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useAcademicScope } from "@/hooks/use-academic-scope";
import { formatDate } from "@/lib/date-utils";
import { getErrorMessage } from "@/lib/errors/messages";
import { useAcademicYears } from "@/lib/query/queries/use-academic-config";
import { usePromotionRuns } from "@/lib/query/queries/use-promotion";

export function RunsScreen({ canManage }: { canManage: boolean }) {
  const router = useRouter();
  const scope = useAcademicScope();
  const years = useAcademicYears();
  const [yearId, setYearId] = React.useState<string | undefined>(scope.yearId ?? undefined);
  React.useEffect(() => {
    if (!yearId && scope.yearId) setYearId(scope.yearId);
  }, [scope.yearId, yearId]);
  const runs = usePromotionRuns(yearId);
  const [creating, setCreating] = React.useState(false);

  const openRun = (runs.data ?? []).find((r) => r.status !== "executed");
  const yearOptions = (years.data ?? []).map((y) => ({ value: y.academic_year_id, label: y.name }));

  return (
    <DataTableCard
      title="Kenaikan Kelas"
      description="Evaluasi kenaikan kelas per tahun ajaran."
      primaryActions={
        canManage && yearId ? (
          openRun ? (
            <Button asChild variant="outline">
              <Link href={`/promotion/${openRun.run_id}`}>Buka evaluasi berjalan</Link>
            </Button>
          ) : (
            <Button onClick={() => setCreating(true)}>Buat evaluasi</Button>
          )
        ) : null
      }
      toolbar={{
        filters: (
          <Combobox
            items={yearOptions}
            value={yearId ?? ""}
            onValueChange={(value) => setYearId(value || undefined)}
            placeholder="Pilih tahun ajaran"
            isLoading={years.isLoading}
            aria-label="Tahun ajaran"
            className="w-full sm:w-56"
          />
        ),
      }}
    >
      <div className="px-4 pb-4">
        {runs.isLoading ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        ) : runs.error ? (
          <Alert variant="destructive">
            <AlertDescription>{getErrorMessage(runs.error, { fallback: "Tidak bisa memuat evaluasi." })}</AlertDescription>
          </Alert>
        ) : (runs.data ?? []).length === 0 ? (
          <p className="py-8 text-center text-sm text-muted-foreground">Belum ada evaluasi untuk tahun ajaran ini.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Dibuat</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Dieksekusi</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {(runs.data ?? []).map((run) => (
                <TableRow key={run.run_id}>
                  <TableCell>{formatDate(run.created_at)}</TableCell>
                  <TableCell>
                    <Badge variant={statusBadgeVariant(run.status)}>{STATUS_LABEL[run.status]}</Badge>
                  </TableCell>
                  <TableCell>{run.executed_at ? formatDate(run.executed_at) : "—"}</TableCell>
                  <TableCell className="text-right">
                    <Button asChild variant="ghost" size="sm">
                      <Link href={`/promotion/${run.run_id}`}>Lihat</Link>
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>
      <CriteriaDialog
        open={creating}
        onOpenChange={setCreating}
        mode="create"
        academicYearId={yearId}
        existingRunId={openRun?.run_id}
        onCreated={(runId) => router.push(`/promotion/${runId}`)}
      />
    </DataTableCard>
  );
}
```

(Decision counts per run are not in the list response; the list shows status and dates and the detail shows counts. Spec §4.1 "decision counts" is satisfied on the detail page — noted in the self-review.)

`src/app/promotion/page.tsx`:

```tsx
"use client";

import { PromotionPage } from "@/components/features/promotion/promotion-page";
import { RunsScreen } from "@/components/features/promotion/runs-screen";

export default function PromotionRunsPage() {
  return (
    <PromotionPage title="Kenaikan Kelas" description="Evaluasi kenaikan kelas per tahun ajaran.">
      {(access) => <RunsScreen canManage={access.canManage} />}
    </PromotionPage>
  );
}
```

- [ ] **Step 7: Run the tests to verify they pass**

`pnpm vitest run src/components/layout/sidebar-visibility.test.ts src/components/features/promotion/runs-screen.test.tsx` → all pass. `pnpm typecheck` and `pnpm lint` → clean for touched files.

- [ ] **Step 8: Commit**

```bash
git add src/components/layout src/components/features/promotion src/app/promotion
git commit -m "feat(web): add the promotion runs page and sidebar entry"
```

---

### Task 7: Run detail — frame, action bar, decisions, override, cannot-evaluate (web)

**Files:**
- Create: `apps/web/src/components/features/promotion/action-bar.tsx`
- Create: `apps/web/src/components/features/promotion/action-bar.test.tsx`
- Create: `apps/web/src/components/features/promotion/override-dialog.tsx`
- Create: `apps/web/src/components/features/promotion/decisions-tab.tsx`
- Create: `apps/web/src/components/features/promotion/decisions-tab.test.tsx`
- Create: `apps/web/src/components/features/promotion/cannot-evaluate-tab.tsx`
- Create: `apps/web/src/components/features/promotion/run-detail.tsx`
- Create: `apps/web/src/app/promotion/[runId]/page.tsx`

**Interfaces:**
- Consumes: Task 4 hooks/types/mutations; Task 5 `groupBySourceHomeroom`; Task 6 `PromotionPage`, `PromotionAccess`, labels, `CriteriaDialog`.
- Produces: `availableActions(status: PromotionStatus, access: { canManage: boolean; canApprove: boolean }): PromotionAction[]` where `PromotionAction = "reevaluate" | "submit" | "approve" | "return" | "execute"`; `ActionBar({ detail, access, onReevaluate, onExecute })`.
- Produces: `DecisionsTab({ decisions, editable, homeroomNames }: { decisions: PromotionDecision[]; editable: boolean; homeroomNames: ReadonlyMap<string, string> })` (the map names target homerooms after execution).
- Produces: `OverrideDialog({ runId, decision, open, onOpenChange })`.
- Produces: `RunDetail({ runId, access })`. Task 8 adds a `PlacementTab` and Task 9 an `ExecuteDialog` into it at the marked places.

Action matrix (spec §4.3):

| Status | manage | approve |
|---|---|---|
| draft | reevaluate, submit | — |
| submitted | — | approve, return |
| approved | execute | — |
| executed | — | — |

- [ ] **Step 1: Write the failing tests**

`src/components/features/promotion/action-bar.test.tsx`:

```tsx
import { describe, expect, it } from "vitest";

import { availableActions } from "@/components/features/promotion/action-bar";

describe("availableActions", () => {
  const manage = { canManage: true, canApprove: false };
  const approve = { canManage: false, canApprove: true };
  const both = { canManage: true, canApprove: true };

  it("follows the status × permission matrix", () => {
    expect(availableActions("draft", manage)).toEqual(["reevaluate", "submit"]);
    expect(availableActions("draft", approve)).toEqual([]);
    expect(availableActions("submitted", approve)).toEqual(["approve", "return"]);
    expect(availableActions("submitted", manage)).toEqual([]);
    expect(availableActions("approved", manage)).toEqual(["execute"]);
    expect(availableActions("approved", approve)).toEqual([]);
    expect(availableActions("executed", both)).toEqual([]);
  });
});
```

`src/components/features/promotion/decisions-tab.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

const mutateAsync = vi.hoisted(() => vi.fn());
vi.mock("@/lib/query/mutations/use-promotion", () => ({
  useOverrideDecision: () => ({ mutateAsync, isPending: false }),
}));

import { DecisionsTab } from "@/components/features/promotion/decisions-tab";
import type { PromotionDecision } from "@/lib/query/queries/use-promotion";

function decision(partial: Partial<PromotionDecision> & { decision_id: string }): PromotionDecision {
  return {
    student_id: `s-${partial.decision_id}`,
    homeroom_id: "h1",
    recommended: "promote",
    result: "promote",
    overridden: false,
    reason: null,
    computed_metrics: {
      subjects_counted: 10,
      subjects_below_kkm: 0,
      average: 82.4,
      kkm_used: 75,
      criteria: { min_average: 70, max_subjects_below_kkm: 2, min_attendance_percent: null },
    },
    target_homeroom_id: null,
    target_enrollment_id: null,
    full_name: "Ani",
    nis: "1001",
    homeroom_name: "X-1",
    source_ordinal: 1,
    ...partial,
  };
}

const rows = [
  decision({ decision_id: "d1" }),
  decision({
    decision_id: "d2",
    full_name: "Budi",
    nis: "1002",
    result: "retain",
    overridden: true,
    reason: "Sering tidak hadir semester dua",
  }),
];

describe("DecisionsTab", () => {
  it("lists students with metrics and marks overrides", () => {
    render(<DecisionsTab decisions={rows} editable={false} homeroomNames={new Map()} />);
    expect(screen.getByText("Ani")).toBeInTheDocument();
    expect(screen.getAllByText("82,4").length).toBeGreaterThan(0);
    expect(screen.getByText("Override")).toBeInTheDocument();
    expect(screen.getByText("Sering tidak hadir semester dua")).toBeInTheDocument();
  });

  it("offers Ubah only when editable", () => {
    const { rerender } = render(<DecisionsTab decisions={rows} editable={false} homeroomNames={new Map()} />);
    expect(screen.queryByRole("button", { name: "Ubah Ani" })).not.toBeInTheDocument();
    rerender(<DecisionsTab decisions={rows} editable homeroomNames={new Map()} />);
    expect(screen.getByRole("button", { name: "Ubah Ani" })).toBeInTheDocument();
  });

  it("filters to overridden decisions", () => {
    render(<DecisionsTab decisions={rows} editable={false} homeroomNames={new Map()} />);
    fireEvent.click(screen.getByLabelText("Hanya override"));
    expect(screen.queryByText("Ani")).not.toBeInTheDocument();
    expect(screen.getByText("Budi")).toBeInTheDocument();
  });

  it("override dialog requires a reason when the result differs", async () => {
    render(<DecisionsTab decisions={rows} editable homeroomNames={new Map()} />);
    fireEvent.click(screen.getByRole("button", { name: "Ubah Ani" }));
    // Dialog opens with result = current result (promote = recommended); pick retain.
    fireEvent.click(screen.getByRole("combobox", { name: "Hasil" }));
    fireEvent.click(await screen.findByRole("option", { name: "Tinggal" }));
    fireEvent.click(screen.getByRole("button", { name: "Simpan" }));
    expect(await screen.findByText("Alasan minimal 10 karakter")).toBeInTheDocument();
    expect(mutateAsync).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

`pnpm vitest run src/components/features/promotion/action-bar.test.tsx src/components/features/promotion/decisions-tab.test.tsx`
Expected: FAIL — imports do not resolve. Record.

- [ ] **Step 3: Action bar**

`src/components/features/promotion/action-bar.tsx`:

```tsx
"use client";

import * as React from "react";

import type { PromotionAccess } from "@/components/features/promotion/promotion-page";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { toast } from "@/components/ui/toaster";
import { getErrorMessage } from "@/lib/errors/messages";
import { useTransitionPromotionRun, type PromotionTransition } from "@/lib/query/mutations/use-promotion";
import type { PromotionRunDetail, PromotionStatus } from "@/lib/query/queries/use-promotion";

export type PromotionAction = "reevaluate" | "submit" | "approve" | "return" | "execute";

export function availableActions(
  status: PromotionStatus,
  access: { canManage: boolean; canApprove: boolean },
): PromotionAction[] {
  switch (status) {
    case "draft":
      return access.canManage ? ["reevaluate", "submit"] : [];
    case "submitted":
      return access.canApprove ? ["approve", "return"] : [];
    case "approved":
      return access.canManage ? ["execute"] : [];
    case "executed":
      return [];
  }
}

const TRANSITION_COPY: Record<PromotionTransition, { label: string; title: string; description: string; done: string }> = {
  submit: {
    label: "Ajukan",
    title: "Ajukan evaluasi?",
    description: "Setelah diajukan, keputusan tidak bisa diubah sampai kepala sekolah mengembalikannya.",
    done: "Evaluasi diajukan.",
  },
  approve: {
    label: "Setujui",
    title: "Setujui evaluasi?",
    description: "Setelah disetujui, admin dapat menentukan kelas tujuan dan mengeksekusi kenaikan kelas.",
    done: "Evaluasi disetujui.",
  },
  return: {
    label: "Kembalikan",
    title: "Kembalikan ke draft?",
    description: "Admin dapat mengubah keputusan lagi lalu mengajukan ulang.",
    done: "Evaluasi dikembalikan ke draft.",
  },
};

export function ActionBar({
  detail,
  access,
  onReevaluate,
  onExecute,
  executeDisabled = false,
}: {
  detail: PromotionRunDetail;
  access: PromotionAccess;
  onReevaluate: () => void;
  onExecute: () => void;
  executeDisabled?: boolean;
}) {
  const transition = useTransitionPromotionRun(detail.run.run_id);
  const [pending, setPending] = React.useState<PromotionTransition | null>(null);
  const actions = availableActions(detail.run.status, access);
  if (actions.length === 0) return null;

  async function confirm() {
    if (!pending) return;
    try {
      await transition.mutateAsync(pending);
      toast.success(TRANSITION_COPY[pending].done);
      setPending(null);
    } catch (error) {
      toast.error(getErrorMessage(error, { fallback: "Aksi gagal." }));
      setPending(null);
    }
  }

  return (
    <div className="flex flex-wrap gap-2">
      {actions.includes("reevaluate") ? (
        <Button variant="outline" onClick={onReevaluate}>
          Evaluasi ulang
        </Button>
      ) : null}
      {(["submit", "approve", "return"] as const)
        .filter((a) => actions.includes(a))
        .map((a) => (
          <Button key={a} variant={a === "return" ? "outline" : "default"} onClick={() => setPending(a)}>
            {TRANSITION_COPY[a].label}
          </Button>
        ))}
      {actions.includes("execute") ? (
        <Button onClick={onExecute} disabled={executeDisabled}>
          Eksekusi
        </Button>
      ) : null}
      <ConfirmDialog
        open={pending !== null}
        onOpenChange={(open) => (!open ? setPending(null) : undefined)}
        title={pending ? TRANSITION_COPY[pending].title : ""}
        description={pending ? TRANSITION_COPY[pending].description : ""}
        confirmLabel={pending ? TRANSITION_COPY[pending].label : "Konfirmasi"}
        loading={transition.isPending}
        onConfirm={confirm}
      />
    </div>
  );
}
```

- [ ] **Step 4: Override dialog**

`src/components/features/promotion/override-dialog.tsx`:

```tsx
"use client";

import * as React from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { RESULT_LABEL } from "@/components/features/promotion/labels";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/ui/toaster";
import { getErrorMessage, isApiError } from "@/lib/errors/messages";
import { applyServerFieldErrors } from "@/lib/forms/apply-server-field-errors";
import { useOverrideDecision } from "@/lib/query/mutations/use-promotion";
import type { PromotionDecision } from "@/lib/query/queries/use-promotion";
import { PROMOTION_RESULTS, overrideSchema, type OverrideForm } from "@/lib/schemas/promotion";

export function formatScore(value: number | null | undefined): string {
  if (value === null || value === undefined) return "—";
  return value.toLocaleString("id-ID", { maximumFractionDigits: 1 });
}

export function OverrideDialog({
  runId,
  decision,
  open,
  onOpenChange,
}: {
  runId: string;
  decision: PromotionDecision | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const override = useOverrideDecision(runId);
  const [failure, setFailure] = React.useState<unknown>(null);
  const schema = React.useMemo(() => overrideSchema(decision?.recommended ?? "promote"), [decision]);
  const form = useForm<OverrideForm>({
    resolver: zodResolver(schema),
    defaultValues: { result: decision?.result ?? "promote", reason: decision?.reason ?? "" },
  });

  React.useEffect(() => {
    if (open && decision) {
      form.reset({ result: decision.result, reason: decision.reason ?? "" });
      setFailure(null);
    }
  }, [open, decision, form]);

  if (!decision) return null;
  const result = form.watch("result");
  const needsReason = result !== decision.recommended;

  async function onSubmit(values: OverrideForm) {
    setFailure(null);
    try {
      await override.mutateAsync({ decisionId: decision!.decision_id, result: values.result, reason: values.reason });
      toast.success("Keputusan diperbarui.");
      onOpenChange(false);
    } catch (error) {
      if (applyServerFieldErrors(form, error).length === 0) setFailure(error);
    }
  }

  const m = decision.computed_metrics;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Ubah keputusan — {decision.full_name ?? "—"}</DialogTitle>
          <DialogDescription>
            Rekomendasi: {RESULT_LABEL[decision.recommended]}. Rata-rata {formatScore(m.average)}, {m.subjects_below_kkm} dari{" "}
            {m.subjects_counted} mapel di bawah KKM {formatScore(m.kkm_used)}.
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
            <FormField
              control={form.control}
              name="result"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Hasil</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger aria-label="Hasil">
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {PROMOTION_RESULTS.map((r) => (
                        <SelectItem key={r} value={r}>
                          {RESULT_LABEL[r]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="reason"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Alasan{needsReason ? " *" : ""}</FormLabel>
                  <FormControl>
                    <Textarea
                      rows={3}
                      placeholder={needsReason ? "Minimal 10 karakter" : "Tidak perlu: hasil sama dengan rekomendasi"}
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            {failure ? (
              <Alert variant="destructive">
                <AlertDescription>
                  {getErrorMessage(failure, { fallback: "Keputusan gagal disimpan." })}
                  {isApiError(failure, "PROMOTION_RUN_INVALID_STATUS") ? " Data evaluasi sudah dimuat ulang." : null}
                </AlertDescription>
              </Alert>
            ) : null}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Batal
              </Button>
              <Button type="submit" loading={override.isPending}>
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

- [ ] **Step 5: Decisions tab**

`src/components/features/promotion/decisions-tab.tsx`:

```tsx
"use client";

import * as React from "react";

import { RESULT_LABEL } from "@/components/features/promotion/labels";
import { OverrideDialog, formatScore } from "@/components/features/promotion/override-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { SearchInput } from "@/components/ui/search-input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { groupBySourceHomeroom } from "@/lib/promotion/placement";
import type { PromotionDecision, PromotionResult } from "@/lib/query/queries/use-promotion";

type ResultFilter = "all" | PromotionResult;

export function DecisionsTab({
  runId = "",
  decisions,
  editable,
  homeroomNames,
}: {
  runId?: string;
  decisions: PromotionDecision[];
  editable: boolean;
  homeroomNames: ReadonlyMap<string, string>;
}) {
  const groups = React.useMemo(() => groupBySourceHomeroom(decisions), [decisions]);
  const [homeroomId, setHomeroomId] = React.useState<string | undefined>(undefined);
  const [resultFilter, setResultFilter] = React.useState<ResultFilter>("all");
  const [overriddenOnly, setOverriddenOnly] = React.useState(false);
  const [search, setSearch] = React.useState("");
  const [editing, setEditing] = React.useState<PromotionDecision | null>(null);

  const active = groups.find((g) => g.homeroom_id === homeroomId) ?? groups[0];
  const showTarget = decisions.some((d) => d.target_enrollment_id !== null);
  const needle = search.trim().toLowerCase();
  const rows = (active?.decisions ?? []).filter(
    (d) =>
      (resultFilter === "all" || d.result === resultFilter) &&
      (!overriddenOnly || d.overridden) &&
      (needle === "" ||
        (d.full_name ?? "").toLowerCase().includes(needle) ||
        (d.nis ?? "").toLowerCase().includes(needle)),
  );

  if (groups.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">Belum ada keputusan.</p>;
  }

  return (
    <div className="space-y-4">
      <Tabs value={active?.homeroom_id} onValueChange={setHomeroomId} variant="underline">
        <TabsList scrollable>
          {groups.map((g) => (
            <TabsTrigger key={g.homeroom_id} value={g.homeroom_id}>
              {g.homeroom_name} ({g.decisions.length})
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <SearchInput value={search} onChange={setSearch} placeholder="Cari nama atau NIS" aria-label="Cari siswa" className="sm:w-64" />
        <Select value={resultFilter} onValueChange={(v) => setResultFilter(v as ResultFilter)}>
          <SelectTrigger aria-label="Filter hasil" className="sm:w-40">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Semua hasil</SelectItem>
            <SelectItem value="promote">Naik</SelectItem>
            <SelectItem value="retain">Tinggal</SelectItem>
            <SelectItem value="graduate">Lulus</SelectItem>
          </SelectContent>
        </Select>
        <div className="flex items-center gap-2">
          <Checkbox id="overridden-only" checked={overriddenOnly} onCheckedChange={(c) => setOverriddenOnly(c === true)} />
          <Label htmlFor="overridden-only">Hanya override</Label>
        </div>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>NIS</TableHead>
            <TableHead>Nama</TableHead>
            <TableHead className="text-right">Rata-rata</TableHead>
            <TableHead className="text-right">Di bawah KKM</TableHead>
            <TableHead>Rekomendasi</TableHead>
            <TableHead>Hasil</TableHead>
            <TableHead>Alasan</TableHead>
            {showTarget ? <TableHead>Kelas tujuan</TableHead> : null}
            {editable ? <TableHead /> : null}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((d) => (
            <TableRow key={d.decision_id}>
              <TableCell className="tabular-nums">{d.nis ?? "—"}</TableCell>
              <TableCell className="font-medium">{d.full_name ?? "—"}</TableCell>
              <TableCell className="text-right tabular-nums">{formatScore(d.computed_metrics.average)}</TableCell>
              <TableCell className="text-right tabular-nums">{d.computed_metrics.subjects_below_kkm}</TableCell>
              <TableCell>{RESULT_LABEL[d.recommended]}</TableCell>
              <TableCell>
                <span className="flex items-center gap-2">
                  {RESULT_LABEL[d.result]}
                  {d.overridden ? <Badge variant="outline">Override</Badge> : null}
                </span>
              </TableCell>
              <TableCell className="max-w-xs text-sm text-muted-foreground">{d.reason ?? ""}</TableCell>
              {showTarget ? (
                <TableCell>{d.target_homeroom_id ? homeroomNames.get(d.target_homeroom_id) ?? "—" : "—"}</TableCell>
              ) : null}
              {editable ? (
                <TableCell className="text-right">
                  <Button variant="ghost" size="sm" aria-label={`Ubah ${d.full_name ?? d.nis ?? ""}`} onClick={() => setEditing(d)}>
                    Ubah
                  </Button>
                </TableCell>
              ) : null}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      {rows.length === 0 ? <p className="text-center text-sm text-muted-foreground">Tidak ada siswa yang cocok.</p> : null}
      <OverrideDialog
        runId={runId}
        decision={editing}
        open={editing !== null}
        onOpenChange={(open) => (!open ? setEditing(null) : undefined)}
      />
    </div>
  );
}
```

- [ ] **Step 6: Cannot-evaluate tab**

`src/components/features/promotion/cannot-evaluate-tab.tsx` (spec §5.2, with the planning deviation: one `GET /students/:id` per id via `useQueries`, because the list endpoint caps at 100):

```tsx
"use client";

import { useQueries } from "@tanstack/react-query";

import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { apiFetch } from "@/lib/api/client";
import { STUDENTS_QUERY_KEY, type Student } from "@/lib/query/queries/use-academic-ops";

export function CannotEvaluateTab({ studentIds }: { studentIds: string[] }) {
  const students = useQueries({
    queries: studentIds.map((id) => ({
      queryKey: [...STUDENTS_QUERY_KEY, id],
      queryFn: () =>
        apiFetch<Student>({ service: "academic-ops", path: `/api/v1/academic-ops/students/${id}`, authenticated: true }),
    })),
  });

  if (studentIds.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">Semua siswa bisa dievaluasi.</p>;
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Siswa berikut belum punya rapor terbit pada tipe rapor sumber kenaikan, sehingga tidak dievaluasi dan tidak
        dianggap tinggal kelas. Terbitkan rapornya lalu evaluasi ulang.
      </p>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>NIS</TableHead>
            <TableHead>Nama</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {students.map((q, i) => (
            <TableRow key={studentIds[i]}>
              {q.isLoading ? (
                <TableCell colSpan={2}>
                  <Skeleton className="h-5 w-full" />
                </TableCell>
              ) : (
                <>
                  <TableCell className="tabular-nums">{q.data?.nis ?? "—"}</TableCell>
                  <TableCell>{q.data?.full_name ?? studentIds[i]}</TableCell>
                </>
              )}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
```

(The spec also listed the homeroom column; a student has no homeroom in this response and the cannot-evaluate list carries only ids. Showing NIS + name is enough to act on — noted in the self-review.)

`STUDENTS_QUERY_KEY` must be exported from `use-academic-ops.ts`; it already is.

- [ ] **Step 7: Run detail and route**

`src/components/features/promotion/run-detail.tsx`:

```tsx
"use client";

import * as React from "react";
import Link from "next/link";

import { ActionBar } from "@/components/features/promotion/action-bar";
import { CannotEvaluateTab } from "@/components/features/promotion/cannot-evaluate-tab";
import { CriteriaDialog } from "@/components/features/promotion/criteria-dialog";
import { DecisionsTab } from "@/components/features/promotion/decisions-tab";
import { STATUS_LABEL, STATUS_ORDER, statusBadgeVariant } from "@/components/features/promotion/labels";
import { formatScore } from "@/components/features/promotion/override-dialog";
import type { PromotionAccess } from "@/components/features/promotion/promotion-page";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ApiHttpError } from "@/lib/api/types";
import { formatDateTime } from "@/lib/date-utils";
import { getErrorMessage } from "@/lib/errors/messages";
import { useAcademicYears } from "@/lib/query/queries/use-academic-config";
import { useHomeroomsForYear } from "@/lib/query/queries/use-academic-ops";
import { usePromotionDecisions, usePromotionRun } from "@/lib/query/queries/use-promotion";

function Who({ id, userId }: { id: string | null; userId: string | null }) {
  if (!id) return null;
  return <>{id === userId ? " oleh Anda" : ""}</>;
}

export function RunDetail({ runId, access }: { runId: string; access: PromotionAccess }) {
  const detail = usePromotionRun(runId);
  const decisions = usePromotionDecisions(runId);
  const years = useAcademicYears();
  const targetHomerooms = useHomeroomsForYear(detail.data?.run.target_academic_year_id ?? undefined);
  const [reevaluating, setReevaluating] = React.useState(false);
  const [tab, setTab] = React.useState("decisions");

  if (detail.isLoading) {
    return (
      <div className="space-y-3 px-6">
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }
  if (detail.error instanceof ApiHttpError && detail.error.status === 404) {
    return (
      <Alert className="mx-6">
        <AlertTitle>Evaluasi tidak ditemukan</AlertTitle>
        <AlertDescription>
          <Link href="/promotion" className="underline">
            Kembali ke daftar evaluasi
          </Link>
        </AlertDescription>
      </Alert>
    );
  }
  if (detail.error || !detail.data) {
    return (
      <Alert variant="destructive" className="mx-6">
        <AlertDescription>{getErrorMessage(detail.error, { fallback: "Tidak bisa memuat evaluasi." })}</AlertDescription>
      </Alert>
    );
  }

  const d = detail.data;
  const run = d.run;
  const yearName = (id: string | null) => years.data?.find((y) => y.academic_year_id === id)?.name ?? "—";
  const stage = STATUS_ORDER.indexOf(run.status);
  const homeroomNames = new Map((targetHomerooms.data ?? []).map((h) => [h.homeroom_id, h.name]));
  const showPlacement = run.status === "approved" || run.status === "executed";

  return (
    <div className="space-y-4 px-6">
      <Card>
        <CardHeader className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
          <div className="space-y-2">
            <CardTitle className="flex items-center gap-3 text-lg">
              Kenaikan Kelas {yearName(run.academic_year_id)}
              <Badge variant={statusBadgeVariant(run.status)}>{STATUS_LABEL[run.status]}</Badge>
            </CardTitle>
            <ol className="flex flex-wrap gap-2 text-xs" aria-label="Tahap">
              {STATUS_ORDER.map((s, i) => (
                <li key={s} className={i <= stage ? "font-semibold text-foreground" : "text-muted-foreground"}>
                  {i > 0 ? "→ " : ""}
                  {STATUS_LABEL[s]}
                </li>
              ))}
            </ol>
            <p className="text-xs text-muted-foreground">
              Dibuat {formatDateTime(run.created_at)}
              <Who id={run.created_by} userId={access.userId} />
              {run.approved_by ? (
                <>
                  {" · "}Disetujui
                  <Who id={run.approved_by} userId={access.userId} />
                </>
              ) : null}
              {run.executed_at ? (
                <>
                  {" · "}Dieksekusi {formatDateTime(run.executed_at)}
                  <Who id={run.executed_by} userId={access.userId} />
                </>
              ) : null}
            </p>
          </div>
          <ActionBar
            detail={d}
            access={access}
            onReevaluate={() => setReevaluating(true)}
            onExecute={() => setTab("placement")}
          />
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-4 text-sm md:grid-cols-6">
          <div>
            <p className="text-muted-foreground">Naik</p>
            <p className="text-lg font-semibold tabular-nums">{d.counts.promote}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Tinggal</p>
            <p className="text-lg font-semibold tabular-nums">{d.counts.retain}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Lulus</p>
            <p className="text-lg font-semibold tabular-nums">{d.counts.graduate}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Override</p>
            <p className="text-lg font-semibold tabular-nums">{d.overridden}</p>
          </div>
          <div>
            <p className="text-muted-foreground">KKM</p>
            <p className="text-lg font-semibold tabular-nums">{formatScore(d.kkm)}</p>
          </div>
          <div>
            <p className="text-muted-foreground">Kriteria</p>
            <p>
              Rata-rata ≥ {d.criteria.min_average === null ? "—" : formatScore(d.criteria.min_average)}; mapel di bawah KKM ≤{" "}
              {d.criteria.max_subjects_below_kkm ?? "—"}
            </p>
          </div>
        </CardContent>
      </Card>

      <Tabs value={tab} onValueChange={setTab} variant="underline">
        <TabsList>
          <TabsTrigger value="decisions">Keputusan</TabsTrigger>
          {showPlacement ? <TabsTrigger value="placement">Penempatan</TabsTrigger> : null}
          <TabsTrigger value="cannot">Tidak bisa dievaluasi ({d.cannot_evaluate.length})</TabsTrigger>
        </TabsList>
        <TabsContent value="decisions">
          {decisions.isLoading ? (
            <Skeleton className="h-64 w-full" />
          ) : (
            <DecisionsTab
              runId={runId}
              decisions={decisions.data ?? []}
              editable={run.status === "draft" && access.canManage}
              homeroomNames={homeroomNames}
            />
          )}
        </TabsContent>
        {showPlacement ? (
          <TabsContent value="placement">
            {/* PLACEMENT_TAB — replaced in Task 8 */}
            <p className="text-sm text-muted-foreground">Penempatan belum tersedia.</p>
          </TabsContent>
        ) : null}
        <TabsContent value="cannot">
          <CannotEvaluateTab studentIds={d.cannot_evaluate} />
        </TabsContent>
      </Tabs>

      <CriteriaDialog
        open={reevaluating}
        onOpenChange={setReevaluating}
        mode="reevaluate"
        runId={runId}
        initial={d.criteria}
        overriddenCount={d.overridden}
      />
      {/* EXECUTE_DIALOG — added in Task 9 */}
    </div>
  );
}
```

`onExecute` temporarily switches to the Penempatan tab; Task 9 makes it open the execute dialog. The two `{/* … */}` markers are the exact places Tasks 8 and 9 edit.

`src/app/promotion/[runId]/page.tsx`:

```tsx
"use client";

import { useParams } from "next/navigation";

import { PromotionPage } from "@/components/features/promotion/promotion-page";
import { RunDetail } from "@/components/features/promotion/run-detail";

export default function PromotionRunPage() {
  const params = useParams<{ runId: string }>();
  return (
    <PromotionPage title="Kenaikan Kelas" description="Detail evaluasi kenaikan kelas.">
      {(access) => <RunDetail runId={params.runId} access={access} />}
    </PromotionPage>
  );
}
```

- [ ] **Step 8: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion` → all pass. `pnpm typecheck` and `pnpm lint` → clean for touched files.

If the override test's Radix `Select` cannot be opened in jsdom (Radix needs pointer capture), add to `vitest.setup.ts`:

```ts
// Radix Select uses pointer capture and scrollIntoView, which jsdom lacks.
if (!Element.prototype.hasPointerCapture) {
  Element.prototype.hasPointerCapture = () => false;
  Element.prototype.releasePointerCapture = () => undefined;
}
if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => undefined;
}
```

and stage `vitest.setup.ts` in the commit.

- [ ] **Step 9: Commit**

```bash
git add src/components/features/promotion src/app/promotion vitest.setup.ts
git commit -m "feat(web): add the promotion run detail with decisions and overrides"
```

---

### Task 8: Placement tab (web)

**Files:**
- Create: `apps/web/src/components/features/promotion/placement-tab.tsx`
- Create: `apps/web/src/components/features/promotion/placement-tab.test.tsx`
- Modify: `apps/web/src/components/features/promotion/run-detail.tsx` (the `PLACEMENT_TAB` marker; dirty state)

**Interfaces:**
- Consumes: Task 3 `useHomeroomsForYear`, `Homeroom`; Task 4 `useSetPromotionTarget`, `useAssignPromotionTargets`, `promotionFieldGroups`, `getErrorMessage`; Task 5 placement functions; `useAcademicYears`.
- Produces: `PlacementTab({ detail, decisions, editable, onDirtyChange }: { detail: PromotionRunDetail; decisions: PromotionDecision[]; editable: boolean; onDirtyChange: (dirty: boolean) => void })`.
- Produces in `RunDetail`: `const [unsavedPlacement, setUnsavedPlacement] = React.useState(false)`, passed to `ActionBar` as `executeDisabled={unsavedPlacement}`.

Behaviour (spec §5.3):
- Step 1 (target year): `Select` of the tenant's years excluding `run.academic_year_id` and `Closed`/`Archived`. "Simpan tahun tujuan" calls `PUT .../target`. When the year changes and any decision has `target_homeroom_id`, a `ConfirmDialog` first says "N tujuan yang sudah diisi akan dikosongkan." On success toast "Tahun tujuan disimpan." plus " N tujuan dikosongkan." when `cleared_targets > 0`. A `400` lists `target_academic_year_id` messages under the select.
- Step 2 is shown only when `run.target_academic_year_id` is set. One `Card` per source homeroom (`groupBySourceHomeroom`): header with "Naik ke" and "Tinggal di" selects (hidden when the class has no student with that result; a warning instead of selects when `source_ordinal` is null), a toggle "Lihat siswa" expanding a table with a per-student select (graduates: "Lulus — tanpa kelas tujuan"), and per-row error text from the last failed save.
- Draft: local `PlacementDraft`. A bar with "N perubahan belum disimpan", "Simpan" and "Batalkan" appears when `draftChanges(...)` is non-empty. Save sends the changes in one `PATCH .../targets`; on `400` each `decision <id>: …` goes on its row (`mapAssignmentErrors`), unmatched messages go in an Alert, and the draft is kept; on success the draft is cleared and toast "N tujuan disimpan.".
- `onDirtyChange(changes.length > 0)` runs whenever that count flips. While dirty, a `beforeunload` listener warns on reload/close.
- Placement report (server data): one row per `detail.placement` entry — name, capacity, existing, assigned, total, and `<Badge variant="outline">Melebihi kapasitas</Badge>` (yellow text) when `over_capacity`; plus "N siswa belum punya tujuan" from `detail.unassigned`.
- `editable=false` (status `executed`, or no `promotion.manage`): selects and buttons disabled; the report still shows.

- [ ] **Step 1: Write the failing test**

`src/components/features/promotion/placement-tab.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiHttpError } from "@/lib/api/types";
import type { PromotionDecision, PromotionRunDetail } from "@/lib/query/queries/use-promotion";

const assign = vi.hoisted(() => vi.fn());
const SRC_YEAR = "year-s";
const TGT_YEAR = "year-t";
const D1 = "11111111-1111-4111-8111-111111111111";
const D2 = "22222222-2222-4222-8222-222222222222";

vi.mock("@/lib/query/queries/use-academic-config", () => ({
  useAcademicYears: () => ({
    data: [
      { academic_year_id: SRC_YEAR, name: "2025/2026", status: "Active" },
      { academic_year_id: TGT_YEAR, name: "2026/2027", status: "Draft" },
    ],
    isLoading: false,
  }),
}));
vi.mock("@/lib/query/queries/use-academic-ops", () => ({
  useHomeroomsForYear: () => ({
    data: [
      { homeroom_id: "t-xi-a", name: "XI-A", grade_level: "XI", grade_level_id: "g2", ordinal: 2, capacity: 30, academic_year_id: TGT_YEAR, enrolled_count: 0 },
      { homeroom_id: "t-x-a", name: "X-A", grade_level: "X", grade_level_id: "g1", ordinal: 1, capacity: 30, academic_year_id: TGT_YEAR, enrolled_count: 0 },
    ],
    isLoading: false,
  }),
}));
vi.mock("@/lib/query/mutations/use-promotion", () => ({
  useSetPromotionTarget: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useAssignPromotionTargets: () => ({ mutateAsync: assign, isPending: false }),
}));

import { PlacementTab } from "@/components/features/promotion/placement-tab";

function decision(id: string, result: "promote" | "retain", name: string): PromotionDecision {
  return {
    decision_id: id,
    student_id: `s-${id}`,
    homeroom_id: "src-x1",
    recommended: result,
    result,
    overridden: false,
    reason: null,
    computed_metrics: {
      subjects_counted: 1,
      subjects_below_kkm: 0,
      average: 80,
      kkm_used: 75,
      criteria: { min_average: null, max_subjects_below_kkm: null, min_attendance_percent: null },
    },
    target_homeroom_id: null,
    target_enrollment_id: null,
    full_name: name,
    nis: id.slice(0, 4),
    homeroom_name: "X-1",
    source_ordinal: 1,
  };
}

const detail = {
  run: {
    run_id: "run-1",
    academic_year_id: SRC_YEAR,
    status: "approved",
    target_academic_year_id: TGT_YEAR,
  },
  placement: [
    { homeroom_id: "t-xi-a", name: "XI-A", capacity: 30, existing_active: 2, assigned: 29, total: 31, over_capacity: true },
  ],
  unassigned: 2,
} as unknown as PromotionRunDetail;

describe("PlacementTab", () => {
  beforeEach(() => assign.mockReset());

  it("fills a class default, saves the changes in one request, and reports dirtiness", async () => {
    const onDirtyChange = vi.fn();
    assign.mockResolvedValueOnce({ updated: 1 });
    render(
      <PlacementTab
        detail={detail}
        decisions={[decision(D1, "promote", "Ani"), decision(D2, "retain", "Budi")]}
        editable
        onDirtyChange={onDirtyChange}
      />,
    );
    expect(screen.getByText("Melebihi kapasitas")).toBeInTheDocument();
    expect(screen.getByText("2 siswa belum punya tujuan")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("combobox", { name: "Naik ke untuk X-1" }));
    fireEvent.click(await screen.findByRole("option", { name: "XI-A" }));
    expect(screen.getByText("1 perubahan belum disimpan")).toBeInTheDocument();
    expect(onDirtyChange).toHaveBeenLastCalledWith(true);

    fireEvent.click(screen.getByRole("button", { name: "Simpan" }));
    expect(assign).toHaveBeenCalledWith([{ decision_id: D1, homeroom_id: "t-xi-a" }]);
  });

  it("keeps the draft and shows each rejected decision on its row", async () => {
    assign.mockRejectedValueOnce(
      new ApiHttpError(400, {
        code: "VALIDATION_ERROR",
        message: "invalid",
        fields: { assignments: [`decision ${D1}: homeroom XI-A is ordinal 2, expected 1`] },
      }),
    );
    render(
      <PlacementTab
        detail={detail}
        decisions={[decision(D1, "promote", "Ani"), decision(D2, "retain", "Budi")]}
        editable
        onDirtyChange={() => undefined}
      />,
    );
    fireEvent.click(screen.getByRole("combobox", { name: "Naik ke untuk X-1" }));
    fireEvent.click(await screen.findByRole("option", { name: "XI-A" }));
    fireEvent.click(screen.getByRole("button", { name: "Simpan" }));
    expect(await screen.findByText("homeroom XI-A is ordinal 2, expected 1")).toBeInTheDocument();
    expect(screen.getByText("1 perubahan belum disimpan")).toBeInTheDocument();
  });

  it("is read-only when not editable", () => {
    render(
      <PlacementTab
        detail={detail}
        decisions={[decision(D1, "promote", "Ani")]}
        editable={false}
        onDirtyChange={() => undefined}
      />,
    );
    expect(screen.getByRole("combobox", { name: "Naik ke untuk X-1" })).toBeDisabled();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/components/features/promotion/placement-tab.test.tsx`
Expected: FAIL — import does not resolve.

- [ ] **Step 3: Implement**

`src/components/features/promotion/placement-tab.tsx`:

```tsx
"use client";

import * as React from "react";

import { RESULT_LABEL } from "@/components/features/promotion/labels";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toaster";
import { getErrorMessage, promotionFieldGroups } from "@/lib/errors/messages";
import {
  EMPTY_DRAFT,
  applyClassDefault,
  draftChanges,
  effectiveTarget,
  eligibleHomerooms,
  groupBySourceHomeroom,
  mapAssignmentErrors,
  setStudentTarget,
  type PlacementDraft,
} from "@/lib/promotion/placement";
import { useAssignPromotionTargets, useSetPromotionTarget } from "@/lib/query/mutations/use-promotion";
import { useAcademicYears } from "@/lib/query/queries/use-academic-config";
import { useHomeroomsForYear, type Homeroom } from "@/lib/query/queries/use-academic-ops";
import type { PromotionDecision, PromotionRunDetail } from "@/lib/query/queries/use-promotion";

const NONE = "__none__";

function HomeroomSelect({
  label,
  options,
  value,
  onChange,
  disabled,
}: {
  label: string;
  options: Homeroom[];
  value: string | null;
  onChange: (value: string | null) => void;
  disabled: boolean;
}) {
  return (
    <Select value={value ?? NONE} onValueChange={(v) => onChange(v === NONE ? null : v)} disabled={disabled}>
      <SelectTrigger aria-label={label} className="w-full sm:w-48">
        <SelectValue placeholder="Pilih kelas" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={NONE}>Belum dipilih</SelectItem>
        {options.map((h) => (
          <SelectItem key={h.homeroom_id} value={h.homeroom_id}>
            {h.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** The value a class-default select shows: the shared target when every student of that result has the same one. */
function sharedTarget(decisions: PromotionDecision[], draft: PlacementDraft): string | null {
  const targets = new Set(decisions.map((d) => effectiveTarget(d, draft)));
  return targets.size === 1 ? [...targets][0] : null;
}

export function PlacementTab({
  detail,
  decisions,
  editable,
  onDirtyChange,
}: {
  detail: PromotionRunDetail;
  decisions: PromotionDecision[];
  editable: boolean;
  onDirtyChange: (dirty: boolean) => void;
}) {
  const run = detail.run;
  const years = useAcademicYears();
  const homerooms = useHomeroomsForYear(run.target_academic_year_id ?? undefined);
  const setTarget = useSetPromotionTarget(run.run_id);
  const assign = useAssignPromotionTargets(run.run_id);

  const [yearChoice, setYearChoice] = React.useState<string>(run.target_academic_year_id ?? "");
  const [confirmYear, setConfirmYear] = React.useState(false);
  const [yearErrors, setYearErrors] = React.useState<string[]>([]);
  const [draft, setDraft] = React.useState<PlacementDraft>(EMPTY_DRAFT);
  const [rowErrors, setRowErrors] = React.useState<Record<string, string[]>>({});
  const [saveError, setSaveError] = React.useState<string[]>([]);
  const [expanded, setExpanded] = React.useState<Set<string>>(new Set());

  React.useEffect(() => setYearChoice(run.target_academic_year_id ?? ""), [run.target_academic_year_id]);

  const changes = React.useMemo(() => draftChanges(draft, decisions), [draft, decisions]);
  const dirty = changes.length > 0;
  React.useEffect(() => onDirtyChange(dirty), [dirty, onDirtyChange]);
  React.useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  const groups = React.useMemo(() => groupBySourceHomeroom(decisions), [decisions]);
  const rooms = homerooms.data ?? [];
  const targetYearId = run.target_academic_year_id;
  const yearOptions = (years.data ?? []).filter(
    (y) => y.academic_year_id !== run.academic_year_id && y.status !== "Closed" && y.status !== "Archived",
  );
  const assignedCount = decisions.filter((d) => d.target_homeroom_id !== null).length;

  async function saveYear() {
    setConfirmYear(false);
    setYearErrors([]);
    try {
      const outcome = await setTarget.mutateAsync(yearChoice);
      setDraft(EMPTY_DRAFT);
      toast.success(
        outcome.cleared_targets > 0
          ? `Tahun tujuan disimpan. ${outcome.cleared_targets} tujuan dikosongkan.`
          : "Tahun tujuan disimpan.",
      );
    } catch (error) {
      const groupsErr = promotionFieldGroups(error);
      if (groupsErr.length > 0) setYearErrors(groupsErr.flatMap((g) => g.messages));
      else toast.error(getErrorMessage(error, { fallback: "Tahun tujuan gagal disimpan." }));
    }
  }

  function requestYearSave() {
    if (yearChoice !== run.target_academic_year_id && assignedCount > 0) setConfirmYear(true);
    else void saveYear();
  }

  async function saveTargets() {
    setRowErrors({});
    setSaveError([]);
    try {
      const outcome = await assign.mutateAsync(changes);
      setDraft(EMPTY_DRAFT);
      toast.success(`${outcome.updated} tujuan disimpan.`);
    } catch (error) {
      const messages = promotionFieldGroups(error).flatMap((g) => g.messages);
      if (messages.length === 0) {
        setSaveError([getErrorMessage(error, { fallback: "Tujuan gagal disimpan." })]);
        return;
      }
      const mapped = mapAssignmentErrors(messages, new Set(decisions.map((d) => d.decision_id)));
      setRowErrors(mapped.byDecision);
      setSaveError(mapped.unmatched);
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">1. Tahun tujuan</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="flex flex-col gap-2 sm:flex-row">
            <Select value={yearChoice} onValueChange={setYearChoice} disabled={!editable}>
              <SelectTrigger aria-label="Tahun tujuan" className="sm:w-56">
                <SelectValue placeholder="Pilih tahun tujuan" />
              </SelectTrigger>
              <SelectContent>
                {yearOptions.map((y) => (
                  <SelectItem key={y.academic_year_id} value={y.academic_year_id}>
                    {y.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button
              variant="outline"
              onClick={requestYearSave}
              disabled={!editable || yearChoice === "" || yearChoice === run.target_academic_year_id}
              loading={setTarget.isPending}
            >
              Simpan tahun tujuan
            </Button>
          </div>
          {yearErrors.length > 0 ? (
            <ul className="list-disc pl-4 text-sm text-destructive">
              {yearErrors.map((m) => (
                <li key={m}>{m}</li>
              ))}
            </ul>
          ) : null}
        </CardContent>
      </Card>

      {targetYearId ? (
        <Card>
          <CardHeader className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <CardTitle className="text-base">2. Kelas tujuan</CardTitle>
            {dirty ? (
              <div className="flex items-center gap-2">
                <Badge variant="outline">{changes.length} perubahan belum disimpan</Badge>
                <Button variant="outline" onClick={() => setDraft(EMPTY_DRAFT)} disabled={assign.isPending}>
                  Batalkan
                </Button>
                <Button onClick={saveTargets} loading={assign.isPending}>
                  Simpan
                </Button>
              </div>
            ) : null}
          </CardHeader>
          <CardContent className="space-y-4">
            {saveError.length > 0 ? (
              <Alert variant="destructive">
                <AlertTitle>Penempatan ditolak</AlertTitle>
                <AlertDescription>
                  <ul className="list-disc pl-4">
                    {saveError.map((m) => (
                      <li key={m}>{m}</li>
                    ))}
                  </ul>
                </AlertDescription>
              </Alert>
            ) : null}
            {groups.map((group) => {
              const promote = group.decisions.filter((d) => d.result === "promote");
              const retain = group.decisions.filter((d) => d.result === "retain");
              const isOpen = expanded.has(group.homeroom_id);
              return (
                <div key={group.homeroom_id} className="space-y-2 rounded-md border p-3">
                  <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                    <p className="font-medium">
                      {group.homeroom_name}{" "}
                      <span className="text-sm text-muted-foreground">({group.decisions.length} siswa)</span>
                    </p>
                    {group.source_ordinal === null ? (
                      <p className="text-sm text-destructive">
                        Kelas ini belum tertaut ke tingkat kelas, jadi tujuannya tidak bisa ditentukan.
                      </p>
                    ) : (
                      <div className="flex flex-col gap-2 sm:flex-row">
                        {promote.length > 0 ? (
                          <HomeroomSelect
                            label={`Naik ke untuk ${group.homeroom_name}`}
                            options={eligibleHomerooms(promote[0], rooms, targetYearId)}
                            value={sharedTarget(promote, draft)}
                            onChange={(v) => {
                              if (v) setDraft((prev) => applyClassDefault(prev, decisions, group.homeroom_id, "promote", v));
                            }}
                            disabled={!editable}
                          />
                        ) : null}
                        {retain.length > 0 ? (
                          <HomeroomSelect
                            label={`Tinggal di untuk ${group.homeroom_name}`}
                            options={eligibleHomerooms(retain[0], rooms, targetYearId)}
                            value={sharedTarget(retain, draft)}
                            onChange={(v) => {
                              if (v) setDraft((prev) => applyClassDefault(prev, decisions, group.homeroom_id, "retain", v));
                            }}
                            disabled={!editable}
                          />
                        ) : null}
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() =>
                            setExpanded((prev) => {
                              const next = new Set(prev);
                              if (next.has(group.homeroom_id)) next.delete(group.homeroom_id);
                              else next.add(group.homeroom_id);
                              return next;
                            })
                          }
                        >
                          {isOpen ? "Sembunyikan siswa" : "Lihat siswa"}
                        </Button>
                      </div>
                    )}
                  </div>
                  {isOpen || group.decisions.some((d) => rowErrors[d.decision_id]) ? (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Nama</TableHead>
                          <TableHead>Hasil</TableHead>
                          <TableHead>Kelas tujuan</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {group.decisions.map((d) => (
                          <TableRow key={d.decision_id}>
                            <TableCell>{d.full_name ?? "—"}</TableCell>
                            <TableCell>{RESULT_LABEL[d.result]}</TableCell>
                            <TableCell className="space-y-1">
                              {d.result === "graduate" ? (
                                <span className="text-sm text-muted-foreground">Lulus — tanpa kelas tujuan</span>
                              ) : (
                                <HomeroomSelect
                                  label={`Kelas tujuan ${d.full_name ?? d.nis ?? ""}`}
                                  options={eligibleHomerooms(d, rooms, targetYearId)}
                                  value={effectiveTarget(d, draft)}
                                  onChange={(v) => setDraft((prev) => setStudentTarget(prev, d.decision_id, v))}
                                  disabled={!editable}
                                />
                              )}
                              {(rowErrors[d.decision_id] ?? []).map((m) => (
                                <p key={m} className="text-xs text-destructive">
                                  {m}
                                </p>
                              ))}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  ) : null}
                </div>
              );
            })}
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Laporan penempatan</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <p className="text-sm">{detail.unassigned} siswa belum punya tujuan</p>
          {detail.placement.length === 0 ? (
            <p className="text-sm text-muted-foreground">Belum ada kelas tujuan yang dipakai.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Kelas</TableHead>
                  <TableHead className="text-right">Kapasitas</TableHead>
                  <TableHead className="text-right">Sudah ada</TableHead>
                  <TableHead className="text-right">Ditempatkan</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {detail.placement.map((p) => (
                  <TableRow key={p.homeroom_id}>
                    <TableCell>{p.name}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.capacity}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.existing_active}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.assigned}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.total}</TableCell>
                    <TableCell>
                      {p.over_capacity ? (
                        <Badge variant="outline" className="border-yellow-500 text-yellow-700 dark:text-yellow-400">
                          Melebihi kapasitas
                        </Badge>
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
          <p className="text-xs text-muted-foreground">Angka ini dari data tersimpan; simpan perubahan untuk memperbaruinya.</p>
        </CardContent>
      </Card>

      <ConfirmDialog
        open={confirmYear}
        onOpenChange={setConfirmYear}
        title="Ganti tahun tujuan?"
        description={`${assignedCount} tujuan yang sudah diisi akan dikosongkan.`}
        confirmLabel="Ganti"
        destructive
        loading={setTarget.isPending}
        onConfirm={saveYear}
      />
    </div>
  );
}
```

- [ ] **Step 4: Wire into RunDetail**

In `run-detail.tsx`, add state next to `tab`:

```tsx
  const [unsavedPlacement, setUnsavedPlacement] = React.useState(false);
```

pass `executeDisabled={unsavedPlacement}` to `ActionBar`, import `PlacementTab`, and replace the `PLACEMENT_TAB` marker and its `<p>` with:

```tsx
            <PlacementTab
              detail={d}
              decisions={decisions.data ?? []}
              editable={run.status === "approved" && access.canManage}
              onDirtyChange={setUnsavedPlacement}
            />
```

- [ ] **Step 5: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion` → all pass. `pnpm typecheck`, `pnpm lint` → clean for touched files.

- [ ] **Step 6: Commit**

```bash
git add src/components/features/promotion
git commit -m "feat(web): place promoted and retained students into target homerooms"
```

---

### Task 9: Execute dialog (web)

**Files:**
- Create: `apps/web/src/components/features/promotion/execute-dialog.tsx`
- Create: `apps/web/src/components/features/promotion/execute-dialog.test.tsx`
- Modify: `apps/web/src/components/features/promotion/run-detail.tsx` (`onExecute`, the `EXECUTE_DIALOG` marker)

**Interfaces:**
- Consumes: Task 4 `useExecutePromotionRun`, `promotionFieldGroups`, `getErrorMessage`, `isApiError`; Task 5 `withStudentNames`.
- Produces: `canConfirmExecution(typed: string, targetYearName: string, unassigned: number): boolean` — true only when `unassigned === 0` and `typed.trim() === targetYearName` (exact case).
- Produces: `ExecuteDialog({ open, onOpenChange, detail, decisions, targetYearName })`.

Behaviour (spec §5.4): summary (counts, target year, over-capacity homerooms by name); `unassigned > 0` → message "Lengkapi tujuan N siswa dulu." and the button stays disabled; otherwise an `Input` labelled "Ketik nama tahun tujuan untuk konfirmasi" must equal the target year name. A `400` shows `promotionFieldGroups` grouped, each message passed through `withStudentNames` using `student_id → full_name` from the decisions. `409` shows its copy (the hook refetched already). Success → toast "Kenaikan kelas dieksekusi: N naik, N tinggal, N lulus." and close.

- [ ] **Step 1: Write the failing test**

`src/components/features/promotion/execute-dialog.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiHttpError } from "@/lib/api/types";
import type { PromotionRunDetail } from "@/lib/query/queries/use-promotion";

const execute = vi.hoisted(() => vi.fn());
vi.mock("@/lib/query/mutations/use-promotion", () => ({
  useExecutePromotionRun: () => ({ mutateAsync: execute, isPending: false }),
}));

import { ExecuteDialog, canConfirmExecution } from "@/components/features/promotion/execute-dialog";

const STUDENT = "44444444-4444-4444-8444-444444444444";

function detail(unassigned: number): PromotionRunDetail {
  return {
    run: { run_id: "run-1", status: "approved", target_academic_year_id: "year-t" },
    counts: { promote: 10, retain: 1, graduate: 0 },
    placement: [
      { homeroom_id: "h", name: "XI-A", capacity: 30, existing_active: 0, assigned: 31, total: 31, over_capacity: true },
    ],
    unassigned,
  } as unknown as PromotionRunDetail;
}

describe("canConfirmExecution", () => {
  it("needs every student placed and the exact year name", () => {
    expect(canConfirmExecution("2026/2027", "2026/2027", 0)).toBe(true);
    expect(canConfirmExecution("  2026/2027 ", "2026/2027", 0)).toBe(true);
    expect(canConfirmExecution("2026/2028", "2026/2027", 0)).toBe(false);
    expect(canConfirmExecution("", "2026/2027", 0)).toBe(false);
    expect(canConfirmExecution("2026/2027", "2026/2027", 1)).toBe(false);
  });
});

describe("ExecuteDialog", () => {
  beforeEach(() => execute.mockReset());

  it("blocks execution while students lack a target", () => {
    render(<ExecuteDialog open onOpenChange={() => undefined} detail={detail(2)} decisions={[]} targetYearName="2026/2027" />);
    expect(screen.getByText("Lengkapi tujuan 2 siswa dulu.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Eksekusi" })).toBeDisabled();
  });

  it("enables after the exact year name is typed and warns about capacity", () => {
    render(<ExecuteDialog open onOpenChange={() => undefined} detail={detail(0)} decisions={[]} targetYearName="2026/2027" />);
    expect(screen.getByText(/XI-A/)).toBeInTheDocument();
    const button = screen.getByRole("button", { name: "Eksekusi" });
    expect(button).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Ketik nama tahun tujuan untuk konfirmasi"), { target: { value: "2026/2027" } });
    expect(button).toBeEnabled();
  });

  it("shows grouped backend errors with student names", async () => {
    execute.mockRejectedValueOnce(
      new ApiHttpError(400, {
        code: "VALIDATION_ERROR",
        message: "invalid",
        fields: { enrollments: [`student ${STUDENT} is already enrolled in the target academic year`] },
      }),
    );
    render(
      <ExecuteDialog
        open
        onOpenChange={() => undefined}
        detail={detail(0)}
        decisions={[{ student_id: STUDENT, full_name: "Ani" } as never]}
        targetYearName="2026/2027"
      />,
    );
    fireEvent.change(screen.getByLabelText("Ketik nama tahun tujuan untuk konfirmasi"), { target: { value: "2026/2027" } });
    fireEvent.click(screen.getByRole("button", { name: "Eksekusi" }));
    expect(await screen.findByText("Bentrok enrollment")).toBeInTheDocument();
    expect(screen.getByText("Ani is already enrolled in the target academic year")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/components/features/promotion/execute-dialog.test.tsx`
Expected: FAIL — import does not resolve.

- [ ] **Step 3: Implement**

`src/components/features/promotion/execute-dialog.tsx`:

```tsx
"use client";

import * as React from "react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/components/ui/toaster";
import { getErrorMessage, promotionFieldGroups } from "@/lib/errors/messages";
import { withStudentNames } from "@/lib/promotion/placement";
import { useExecutePromotionRun } from "@/lib/query/mutations/use-promotion";
import type { PromotionDecision, PromotionRunDetail } from "@/lib/query/queries/use-promotion";

export function canConfirmExecution(typed: string, targetYearName: string, unassigned: number): boolean {
  return unassigned === 0 && targetYearName !== "" && typed.trim() === targetYearName;
}

export function ExecuteDialog({
  open,
  onOpenChange,
  detail,
  decisions,
  targetYearName,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  detail: PromotionRunDetail;
  decisions: Pick<PromotionDecision, "student_id" | "full_name">[];
  targetYearName: string;
}) {
  const execute = useExecutePromotionRun(detail.run.run_id);
  const [typed, setTyped] = React.useState("");
  const [failure, setFailure] = React.useState<unknown>(null);

  React.useEffect(() => {
    if (open) {
      setTyped("");
      setFailure(null);
    }
  }, [open]);

  const names = React.useMemo(
    () => new Map(decisions.filter((d) => d.full_name).map((d) => [d.student_id, d.full_name as string])),
    [decisions],
  );
  const over = detail.placement.filter((p) => p.over_capacity);
  const groups = promotionFieldGroups(failure);
  const ready = canConfirmExecution(typed, targetYearName, detail.unassigned);

  async function run() {
    setFailure(null);
    try {
      const outcome = await execute.mutateAsync();
      toast.success(
        `Kenaikan kelas dieksekusi: ${outcome.counts.promoted} naik, ${outcome.counts.retained} tinggal, ${outcome.counts.graduated} lulus.`,
      );
      onOpenChange(false);
    } catch (error) {
      setFailure(error);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Eksekusi kenaikan kelas</DialogTitle>
          <DialogDescription>
            Semua siswa dipindahkan ke tahun {targetYearName || "tujuan"} dalam satu kali proses. Tindakan ini tidak bisa
            dibatalkan.
          </DialogDescription>
        </DialogHeader>
        <ul className="space-y-1 text-sm">
          <li>Naik: {detail.counts.promote}</li>
          <li>Tinggal kelas: {detail.counts.retain}</li>
          <li>Lulus: {detail.counts.graduate}</li>
        </ul>
        {over.length > 0 ? (
          <Alert>
            <AlertTitle>Kelas melebihi kapasitas</AlertTitle>
            <AlertDescription>{over.map((p) => `${p.name} (${p.total}/${p.capacity})`).join(", ")}</AlertDescription>
          </Alert>
        ) : null}
        {detail.unassigned > 0 ? (
          <Alert variant="destructive">
            <AlertDescription>Lengkapi tujuan {detail.unassigned} siswa dulu.</AlertDescription>
          </Alert>
        ) : (
          <div className="space-y-1.5">
            <Label htmlFor="confirm-year">Ketik nama tahun tujuan untuk konfirmasi</Label>
            <Input id="confirm-year" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder={targetYearName} />
          </div>
        )}
        {groups.length > 0 ? (
          <Alert variant="destructive">
            <AlertTitle>Eksekusi ditolak</AlertTitle>
            <AlertDescription className="space-y-2">
              {groups.map((g) => (
                <div key={g.field}>
                  <p className="font-medium">{g.label}</p>
                  <ul className="list-disc pl-4">
                    {g.messages.map((m) => (
                      <li key={m}>{withStudentNames(m, names)}</li>
                    ))}
                  </ul>
                </div>
              ))}
            </AlertDescription>
          </Alert>
        ) : failure ? (
          <Alert variant="destructive">
            <AlertDescription>{getErrorMessage(failure, { fallback: "Eksekusi gagal." })}</AlertDescription>
          </Alert>
        ) : null}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={execute.isPending}>
            Batal
          </Button>
          <Button variant="destructive" onClick={run} disabled={!ready} loading={execute.isPending}>
            Eksekusi
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Wire into RunDetail**

In `run-detail.tsx`: add `const [executing, setExecuting] = React.useState(false);`, change `onExecute={() => setTab("placement")}` to `onExecute={() => setExecuting(true)}`, import `ExecuteDialog`, and replace the `EXECUTE_DIALOG` marker with:

```tsx
      <ExecuteDialog
        open={executing}
        onOpenChange={setExecuting}
        detail={d}
        decisions={decisions.data ?? []}
        targetYearName={run.target_academic_year_id ? yearName(run.target_academic_year_id) : ""}
      />
```

An unset target year passes `""`, so `canConfirmExecution` is always false (it requires a non-empty name); the server would reject it anyway (`target_academic_year`).

- [ ] **Step 5: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion` → all pass. `pnpm typecheck`, `pnpm lint` → clean.

- [ ] **Step 6: Commit**

```bash
git add src/components/features/promotion
git commit -m "feat(web): confirm and execute a promotion run"
```

---

### Task 10: Final gate, contract docs, branches (controller)

**Files:**
- Modify (parent): `docs/internal/11_integration_contracts/apis/academic-operations-api.md` (`POST /homerooms` ~284, `GET /homerooms` ~300, `PATCH /homerooms/:id`)
- Modify (parent): `docs/internal/11_integration_contracts/apis/promotion-service-api.md` (decision shape)
- Modify (parent): `apps/backend`, `apps/web` submodule pointers

**Interfaces:** none new. This task proves the branch and records the contract.

- [ ] **Step 1: Whole-branch review** — one reviewer over backend `develop..feat/promotion-ui` and web `570640a..feat/promotion-ui` against the spec and this plan; one fix wave if needed, then a scoped re-review.

- [ ] **Step 2: Backend full suites, once, one service at a time** (`apps/backend/CONVENTIONS.md` §7.1):

```bash
cargo test -p academic-ops-service --lib
cargo test -p academic-ops-service --test integration -- --test-threads=2
cargo clippy --workspace --all-targets
```

Only academic-ops changed; other services are not re-run. Known pre-existing failures: `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url`. Any `WaitContainer(StartupTimeout)` counts only after the test passes re-run alone (`--exact --test-threads=1`).

- [ ] **Step 3: Web full checks, once**

```bash
pnpm typecheck
pnpm lint
pnpm test
pnpm build
```

Expected: all pass. e2e is out of scope (spec §7.3).

- [ ] **Step 4: Contract docs** — document, from the code:
  - `academic-operations-api.md`: homeroom bodies accept `grade_level_id` (create: optional uuid; patch: optional uuid or `null`), the `grade_level_id` validation message, `grade_level` derived from the level's code, `null` on PATCH clears (and `homeroom_teacher_id: null` now clears the teacher); homeroom responses carry `grade_level_id` and `ordinal`; `GET /homerooms?academic_year_id=`.
  - `promotion-service-api.md`: decision shape gains `full_name`, `nis`, `homeroom_name`, `source_ordinal` (all nullable; still filled after execution).

- [ ] **Step 5: Submodule bump and branches**
  - Web: `apps/web` is pinned at `570640a` on the unpushed branch `feat/grade-levels` (3 commits ahead of web `develop` `643a3b6`). Before pushing `feat/promotion-ui` to web `develop`, ask the user how to land `feat/grade-levels` (fast-forward both into `develop` together, or push `feat/grade-levels` first).
  - Parent: commit the docs, then bump both submodule pointers in one commit: `chore: bump backend and web to promotion UI`.
  - Never push without the user's go-ahead; `main` is not touched.

---

## Self-Review

**Spec coverage**

| Spec | Task |
|---|---|
| §3.0 homeroom ↔ grade level link, backend | 1 |
| §3.0 homeroom form select, "Belum tertaut" badge | 3 |
| §3.0.1 tests | 1 (four tests + teacher-clear regression) |
| §3a.1 decision fields | 2 |
| §3a.2 homeroom `grade_level_id`, `ordinal`; `academic_year_id` filter | 1, 3 |
| §3.3 tests incl. after-execution and tenant-safe joins | 2 |
| §4.1 `/promotion` list, year picker, create / open-run link | 6 |
| §4.2 sidebar `moduleAndAnyPermission`, guard | 6 |
| §4.3 header, stage, summary, action bar, self-approval copy | 7 (+ 4 copy) |
| §4.4 criteria dialog create / re-evaluate, preconditions grouped, discarded overrides | 6 |
| §5.1 decisions tabs, columns, filters, override | 7 |
| §5.2 cannot evaluate | 7 |
| §5.3 placement: year, defaults, per-student, draft, errors per row, report | 8 |
| §5.4 execute dialog | 9 |
| §6 errors | 4, 6–9 |
| §7.2 web tests (schemas, placement module, components) | 3–9 |
| contract docs | 10 |

Gaps accepted and recorded: run list shows status and dates but not per-run counts (the list endpoint returns runs only; counts are on the detail) — §4.1 "decision counts" is met on the detail page. Cannot-evaluate rows show NIS and name, not homeroom (the API returns ids only). Both are in the deviation table's spirit; noted for the user.

**Placeholder scan:** no TBD/TODO. The two `{/* … */}` markers in Task 7 are deliberate edit anchors replaced by Tasks 8 and 9.

**Type consistency:** `Homeroom.grade_level_id/ordinal` (Task 3) used by `eligibleHomerooms` (Task 5) and `PlacementTab` (Task 8). `PromotionDecision` fields (Task 4) match Task 2's JSON. `PromotionAccess` = `ReturnType<typeof usePromotionAccess>` (Task 6) consumed by Tasks 7–9. `useAssignPromotionTargets` takes `TargetAssignment[]`, and `draftChanges` returns the same shape. `promotionFieldGroups` (Task 4) used in Tasks 6, 8, 9. `formatScore` exported from `override-dialog.tsx` (Task 7) and reused in `run-detail.tsx`.

**Review Focus:** each of the five lines has a named test in its owning task.
