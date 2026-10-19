# Promotion Letters Implementation Plan (Plan 3e)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a promotion run is executed, the school issues and prints an SK Kenaikan Kelas per source class and a Surat Keterangan Lulus per graduate, with stored numbers and a principal snapshot.

**Architecture:** Billing gains two principal fields and publishes `tenant.school_profile_updated` through its outbox; academic-ops projects it into `known_school_profile` (plus `known_academic_year.name`), stores issued letters in `promotion_class_letter` and an extended `graduation_record`, and serves everything a print page needs. The web adds a "Surat" tab on the run detail and two A4 print pages that call academic-ops only.

**Tech Stack:** Rust (Axum 0.7, SQLx 0.8, refinery, lapin), PostgreSQL 18, RabbitMQ; Next.js 16 / React 19, TanStack Query 5, React Hook Form 7 + Zod 3, shadcn/ui, Vitest 2.

**Spec:** `docs/superpowers/specs/2026-10-18-promotion-letters-design.md`

## Global Constraints

- Backend rules: `apps/backend/CONVENTIONS.md`. Every new or changed query filters by `tenant_id`, including every JOIN. Never edit an applied migration.
- Backend test cadence (§7.1): per task, `cargo check --workspace` plus that task's new tests by exact name. Full suites run once, in Task 10, one service at a time.
- RED must be a real failing assertion, a 404/405 from a missing route, or the compile error the task names. "0 tests matched" is not RED.
- Web rules: `apps/web/CONVENTIONS.md`. shadcn/ui only; data only through TanStack hooks in `src/lib/query/**`; forms use Zod + React Hook Form with field keys equal to backend keys; user-facing error copy through `getErrorMessage` and `src/lib/errors/messages.ts`.
- User-facing copy is Bahasa Indonesia; code, comments and commit messages are English. Commit messages carry no trailers.
- No new error codes. Codes used: `VALIDATION_ERROR`, `PROMOTION_RUN_INVALID_STATUS`, `FORBIDDEN`, `FEATURE_NOT_AVAILABLE`, 404.
- Feature gate `academic_ops`. Issue/correct/refresh: `promotion.manage`. Read/print: `promotion.manage` or `promotion.approve`.
- Every letter endpoint requires the run to be `executed`; otherwise `409 PROMOTION_RUN_INVALID_STATUS` "promotion run must be in executed status".
- 23505 maps to 400 only for `promotion_class_letter_number_uidx` and `graduation_record_certificate_number_uidx`; any other database error stays 500.
- Snapshot on a letter: `school_name`, `principal_name`, `principal_nip` only. Letterhead (logo, address, contact) and student facts are read live.
- Print pages make academic-ops calls only (spec §2.4): the principal holds neither `billing.manage` nor `academic.config.read`.
- Migrations: billing `V5__tenant_principal.sql`, academic-ops `V20__promotion_letters.sql`.

## Review Focus

1. Correcting an issued letter (class letter or certificate) never changes its snapshot, even after the school profile's principal changed (Task 3 test `class_letter_correction_keeps_snapshot`, Task 4 test `certificate_correction_keeps_snapshot`).
2. Two graduates swapping certificate numbers in one request succeeds instead of tripping the unique index (Task 4 test `certificates_can_swap_numbers_in_one_request`).
3. A late, older `tenant.school_profile_updated` never overwrites a newer projection row (Task 2 test `older_school_profile_event_is_ignored`).
4. A principal (approve-only) reads letters and print data but cannot issue, correct or refresh (Task 3 test `principal_reads_letters_but_cannot_issue`, Task 4 test `principal_cannot_issue_certificates_or_refresh`).
5. "Isi nomor dari pola" never overwrites a number the admin typed unless "Timpa nomor yang sudah ada" is ticked (Task 6 test "keeps typed numbers unless overwrite").

## Deviations from the spec decided while planning

| Spec | Plan | Why |
|---|---|---|
| §3.3 `certificate_number` "is required" / "at most 64 characters" as a field | reported under `items` as `student <id>: certificate number is required` / `... must be at most 64 characters` | Numbers arrive as array items; the per-student prefix lets the web map the error to the row. |
| §3.3 number held by another letter | holders inside the same request are not conflicts; the batch first clears its own rows' numbers, then writes | Lets two graduates swap numbers in one request (Review Focus 2). |
| §5 "school-profile form sends the principal fields" (component test) | schema test only | The form lives in `app/settings/school-profile/page.tsx`; a page file cannot export the component for a test (Next.js rejects extra page exports). |
| §2.3 bootstrap `logo_url` | converted in SQL from `media://<owner>/<id>.<ext>` to `/api/v1/billing/media/school/<id>` | Matches `resolve_media_uri_for_owner` with an empty `MEDIA_PUBLIC_BASE_URL`; later profile edits re-publish the exact value. |

---

### Task 1: Billing — principal fields and `tenant.school_profile_updated`

**Files:**
- Create: `apps/backend/services/billing-service/migrations/V5__tenant_principal.sql`
- Modify: `apps/backend/services/billing-service/src/domain.rs` (`SchoolProfile` ~198, `SchoolProfileUpdate` ~218)
- Modify: `apps/backend/services/billing-service/src/repo.rs` (`SchoolProfileRepo` ~619–800)
- Modify: `apps/backend/services/billing-service/src/http.rs` (`SchoolProfilePatchBody` ~195, `From` impl ~212)
- Modify: `apps/backend/services/billing-service/src/commands.rs` (`update_school_profile` ~431, `upload_logo` ~466, `clear_logo` ~520, `validate_school_profile_update` ~653)
- Test: `apps/backend/services/billing-service/tests/integration.rs` (after `school_profile_requires_billing_manage_permission`, ~1240)

**Interfaces:**
- Produces: `SchoolProfile` JSON gains `principal_name: string|null`, `principal_nip: string|null` (GET and PATCH responses). PATCH accepts both (absent = unchanged, `null` or blank = cleared, trimmed).
- Produces: outbox event `tenant.school_profile_updated`, payload exactly:
  `{tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village, subdistrict, city_regency, province, postal_code, phone_number, email, logo_url, updated_at}` — `logo_url` is the resolved serve path (`/api/v1/billing/media/school/<id>`, prefixed by `MEDIA_PUBLIC_BASE_URL`) or `null`; `updated_at` is `tenant.updated_at` (RFC3339). Enqueued in the same transaction as every successful PATCH, logo upload and logo clear. Task 2 consumes it.

- [ ] **Step 1: Write the failing tests**

Add to `tests/integration.rs` after `school_profile_requires_billing_manage_permission`:

```rust
async fn patch_profile(state: &AppState, token: &str, body: Value) -> (StatusCode, Value) {
    let resp = billing_service::http::router(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/api/v1/billing/tenants/me/school-profile")
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    (status, body_to_json(resp).await)
}

async fn profile_events(pool: &PgPool, tenant_id: uuid::Uuid) -> Vec<Value> {
    sqlx::query_scalar(
        "SELECT payload FROM outbox WHERE event_type = 'tenant.school_profile_updated' \
         AND payload->>'tenant_id' = $1 ORDER BY seq",
    )
    .bind(tenant_id.to_string())
    .fetch_all(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn patch_school_profile_sets_and_clears_principal() {
    let (pool, state, _mock, _c) = boot().await;
    let tenant_id = seed_tenant(&pool).await;
    let token = jwt_for(tenant_id);

    let (status, body) = patch_profile(
        &state,
        &token,
        json!({ "principal_name": "  Dra. Siti Rahayu, M.Pd.  ", "principal_nip": "196805121993032004" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["principal_name"], "Dra. Siti Rahayu, M.Pd.");
    assert_eq!(body["data"]["principal_nip"], "196805121993032004");

    // null clears only the key sent; the other stays.
    let (_, body) = patch_profile(&state, &token, json!({ "principal_nip": null })).await;
    assert!(body["data"]["principal_nip"].is_null());
    assert_eq!(body["data"]["principal_name"], "Dra. Siti Rahayu, M.Pd.");

    // Blank also clears.
    let (_, body) = patch_profile(&state, &token, json!({ "principal_name": "   " })).await;
    assert!(body["data"]["principal_name"].is_null());

    let (status, body) = get_profile(&state, &token).await;
    assert_eq!(status, StatusCode::OK);
    assert!(body["data"]["principal_name"].is_null());
}

#[tokio::test]
async fn patch_school_profile_rejects_too_long_principal() {
    let (pool, state, _mock, _c) = boot().await;
    let tenant_id = seed_tenant(&pool).await;
    let token = jwt_for(tenant_id);

    let (status, body) = patch_profile(
        &state,
        &token,
        json!({ "principal_name": "a".repeat(201), "principal_nip": "1".repeat(65) }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(body["error"]["fields"]["principal_name"][0], "principal_name must be at most 200 characters");
    assert_eq!(body["error"]["fields"]["principal_nip"][0], "principal_nip must be at most 64 characters");
    assert!(profile_events(&pool, tenant_id).await.is_empty(), "a rejected PATCH publishes nothing");
}

#[tokio::test]
async fn school_profile_patch_enqueues_profile_event() {
    let (pool, state, _mock, _c) = boot().await;
    let tenant_id = seed_tenant(&pool).await;
    let token = jwt_for(tenant_id);

    let (status, _) = patch_profile(
        &state,
        &token,
        json!({ "principal_name": "Pak Kepala", "city_regency": "Surabaya", "npsn": "20531234" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let events = profile_events(&pool, tenant_id).await;
    assert_eq!(events.len(), 1);
    let p = &events[0];
    assert_eq!(p["tenant_id"], tenant_id.to_string());
    assert_eq!(p["school_name"], "SMA Cendekia");
    assert_eq!(p["principal_name"], "Pak Kepala");
    assert!(p["principal_nip"].is_null());
    assert_eq!(p["city_regency"], "Surabaya");
    assert_eq!(p["npsn"], "20531234");
    assert!(p["logo_url"].is_null());
    assert!(p["updated_at"].is_string(), "payload: {p}");
    for key in ["address_line", "village", "subdistrict", "province", "postal_code", "phone_number", "email"] {
        assert!(p.get(key).is_some(), "payload must carry {key}: {p}");
    }
}

#[tokio::test]
async fn logo_upload_and_clear_enqueue_profile_event() {
    let (pool, state, _mock, _c) = boot().await;
    let tenant_id = seed_tenant(&pool).await;
    let token = jwt_for(tenant_id);

    let (status, _) = upload_logo_media(billing_service::http::router(state.clone()), &token, &png_bytes()).await;
    assert_eq!(status, StatusCode::CREATED);
    let events = profile_events(&pool, tenant_id).await;
    assert_eq!(events.len(), 1);
    let logo = events[0]["logo_url"].as_str().expect("logo_url set after upload");
    assert!(logo.contains("/api/v1/billing/media/school/"), "got {logo}");

    let resp = billing_service::http::router(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/api/v1/billing/tenants/me/school-profile/logo")
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);
    let events = profile_events(&pool, tenant_id).await;
    assert_eq!(events.len(), 2);
    assert!(events[1]["logo_url"].is_null());
}
```

`get_profile` is new too; add it next to `patch_profile`:

```rust
async fn get_profile(state: &AppState, token: &str) -> (StatusCode, Value) {
    let resp = billing_service::http::router(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/v1/billing/tenants/me/school-profile")
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    (status, body_to_json(resp).await)
}
```

`upload_logo_media` and `png_bytes` already exist further down the file (Rust allows calling them before their definition). If `AppState` is not imported in the test file, import it from `billing_service` where the other `billing_service::{...}` imports are.

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `apps/backend`):
`cargo test -p billing-service --test integration -- --test-threads=2 --exact patch_school_profile_sets_and_clears_principal patch_school_profile_rejects_too_long_principal school_profile_patch_enqueues_profile_event logo_upload_and_clear_enqueue_profile_event`

Expected: all four FAIL on assertions — `principal_name` is `null` (the key is ignored), the too-long PATCH returns 200, and `profile_events` is empty.

- [ ] **Step 3: Migration**

`migrations/V5__tenant_principal.sql`:

```sql
-- Billing: principal (kepala sekolah) on the school profile (Plan 3e §2.1).
--
-- Free text, not a teacher/user reference: the principal signs letters and
-- may not be a registered teacher. Letters snapshot these values when issued
-- (academic-ops), so editing them later never rewrites an issued letter.
-- Supersedes the "no head-teacher linkage" note in 02_Billing_Service_ERD.md.

ALTER TABLE tenant
  ADD COLUMN IF NOT EXISTS principal_name VARCHAR(200),
  ADD COLUMN IF NOT EXISTS principal_nip  VARCHAR(64);
```

- [ ] **Step 4: Domain**

In `src/domain.rs`, add to `SchoolProfile` (after `postal_code`):

```rust
    pub principal_name: Option<String>,
    pub principal_nip: Option<String>,
    /// `tenant.updated_at`; carried on `tenant.school_profile_updated` so
    /// consumers can drop out-of-order events. Not part of the HTTP shape.
    #[serde(skip)]
    pub updated_at: chrono::DateTime<chrono::Utc>,
```

and to `SchoolProfileUpdate` (after `postal_code`):

```rust
    pub principal_name: Option<Option<String>>,
    pub principal_nip: Option<Option<String>>,
```

- [ ] **Step 5: Repo**

In `src/repo.rs`, inside `impl SchoolProfileRepo`, replace `find` and the two `Ok(... SchoolProfile { ... })` row mappings with a shared column list and mapper, and extend `update`:

```rust
const SCHOOL_PROFILE_COLUMNS: &str = "tenant_id, school_name, phone_number, email, website, npsn, logo_url, \
     school_level, school_status, accreditation, address_line, village, subdistrict, city_regency, \
     province, postal_code, principal_name, principal_nip, updated_at";

fn map_school_profile(r: &sqlx::postgres::PgRow) -> SchoolProfile {
    SchoolProfile {
        tenant_id: r.get("tenant_id"),
        school_name: r.get("school_name"),
        phone_number: r.get("phone_number"),
        email: r.get("email"),
        website: r.get("website"),
        npsn: r.get("npsn"),
        logo_url: r.get("logo_url"),
        school_level: r.get("school_level"),
        school_status: r.get("school_status"),
        accreditation: r.get("accreditation"),
        address_line: r.get("address_line"),
        village: r.get("village"),
        subdistrict: r.get("subdistrict"),
        city_regency: r.get("city_regency"),
        province: r.get("province"),
        postal_code: r.get("postal_code"),
        principal_name: r.get("principal_name"),
        principal_nip: r.get("principal_nip"),
        updated_at: r.get("updated_at"),
    }
}
```

(Place the const and fn at module level, just above `pub struct SchoolProfileRepo`.)

```rust
    pub async fn find(&self, tenant_id: Uuid) -> sqlx::Result<Option<SchoolProfile>> {
        self.find_with(&self.pool, tenant_id).await
    }

    /// `find` on a caller-supplied executor (the logo commands read the
    /// committed-to-be row inside their transaction to build the event).
    pub async fn find_with<'e, E: PgExecutor<'e>>(
        &self,
        executor: E,
        tenant_id: Uuid,
    ) -> sqlx::Result<Option<SchoolProfile>> {
        let row = sqlx::query(&format!(
            "SELECT {SCHOOL_PROFILE_COLUMNS} FROM tenant WHERE tenant_id = $1"
        ))
        .bind(tenant_id)
        .fetch_optional(executor)
        .await?;
        Ok(row.as_ref().map(map_school_profile))
    }
```

In `update`, add two SET lines before `updated_at = NOW()`:

```sql
                   principal_name = CASE WHEN $29::boolean THEN $30 ELSE principal_name END,
                   principal_nip  = CASE WHEN $31::boolean THEN $32 ELSE principal_nip END,
```

replace the `RETURNING ...` column list with `RETURNING {SCHOOL_PROFILE_COLUMNS}` (turn the `r#"..."#` literal into `&format!(r#"..."#)` and escape nothing else — the SQL has no braces), add the binds after the `postal_code` pair:

```rust
        .bind(update.principal_name.is_some())
        .bind(update.principal_name.as_ref().and_then(|v| v.as_deref()))
        .bind(update.principal_nip.is_some())
        .bind(update.principal_nip.as_ref().and_then(|v| v.as_deref()))
```

and end with `Ok(updated.as_ref().map(map_school_profile))`.

- [ ] **Step 6: HTTP body**

In `src/http.rs`, add to `SchoolProfilePatchBody` (after `postal_code`):

```rust
    #[serde(default, deserialize_with = "double_option")]
    principal_name: Option<Option<String>>,
    #[serde(default, deserialize_with = "double_option")]
    principal_nip: Option<Option<String>>,
```

and to the `From` impl:

```rust
            principal_name: body.principal_name,
            principal_nip: body.principal_nip,
```

The existing `Option<Option<String>>` fields deserialize `null` as absent (serde's default), which is why the new two use `double_option`. Add the helper at module level in `src/http.rs`:

```rust
/// Distinguishes an absent key (None) from an explicit `null` (Some(None)).
fn double_option<'de, D, T>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}
```

(`Deserialize` is already imported; if the compiler asks, import `serde::Deserialize as _`.)

- [ ] **Step 7: Commands — normalise, validate, publish**

In `src/commands.rs`:

```rust
/// Trims a principal field; blank becomes an explicit clear.
fn normalize_principal(value: Option<Option<String>>) -> Option<Option<String>> {
    match value {
        Some(Some(s)) => {
            let t = s.trim();
            if t.is_empty() { Some(None) } else { Some(Some(t.to_string())) }
        }
        other => other,
    }
}

/// Full letterhead state for `tenant.school_profile_updated` (Plan 3e §2.2).
fn school_profile_event_payload(p: &crate::domain::SchoolProfile) -> serde_json::Value {
    json!({
        "tenant_id": p.tenant_id,
        "school_name": p.school_name,
        "npsn": p.npsn,
        "principal_name": p.principal_name,
        "principal_nip": p.principal_nip,
        "address_line": p.address_line,
        "village": p.village,
        "subdistrict": p.subdistrict,
        "city_regency": p.city_regency,
        "province": p.province,
        "postal_code": p.postal_code,
        "phone_number": p.phone_number,
        "email": p.email,
        "logo_url": p.logo_url.as_deref().map(|u| common_media::resolve_media_uri_for_owner(u, "billing", "school")),
        "updated_at": p.updated_at,
    })
}

/// Reads the tenant row on `tx` and enqueues the profile event there, so the
/// event commits with the change that caused it.
async fn enqueue_school_profile_event(
    state: &AppState,
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    tenant_id: Uuid,
) -> Result<(), AppError> {
    let profile = state
        .school_profile_repo
        .find_with(&mut **tx, tenant_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("tenant"))?;
    state
        .outbox_repo
        .enqueue(
            &mut **tx,
            Uuid::new_v4(),
            "tenant.school_profile_updated",
            &school_profile_event_payload(&profile),
        )
        .await
        .map_err(AppError::internal)
}
```

`update_school_profile` becomes:

```rust
pub async fn update_school_profile(
    state: &AppState,
    tenant_id: Uuid,
    mut update: SchoolProfileUpdate,
) -> Result<crate::domain::SchoolProfile, AppError> {
    update.principal_name = normalize_principal(update.principal_name);
    update.principal_nip = normalize_principal(update.principal_nip);
    validate_school_profile_update(&update)?;
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let updated = state
        .school_profile_repo
        .update(&mut *tx, tenant_id, &update)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("tenant"))?;
    state
        .outbox_repo
        .enqueue(
            &mut *tx,
            Uuid::new_v4(),
            "tenant.school_profile_updated",
            &school_profile_event_payload(&updated),
        )
        .await
        .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    // The DB stores a host-agnostic `media://` URI; resolve it to the public HTTP
    // serve path before returning so the frontend can render it directly.
    let mut updated = updated;
    if let Some(logo_url) = &updated.logo_url {
        updated.logo_url = Some(common_media::resolve_media_uri_for_owner(
            logo_url,
            "billing",
            "school",
        ));
    }
    Ok(updated)
}
```

In `upload_logo`, between `set_logo_url(...)` and `tx.commit()`:

```rust
    enqueue_school_profile_event(state, &mut tx, input.tenant_id).await?;
```

In `clear_logo`, replace the final `clear_logo_url(&state.pool, ...)` call with a transaction:

```rust
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    state
        .school_profile_repo
        .clear_logo_url(&mut *tx, tenant_id)
        .await
        .map_err(AppError::internal)?;
    enqueue_school_profile_event(state, &mut tx, tenant_id).await?;
    tx.commit().await.map_err(AppError::internal)?;
```

In `validate_school_profile_update`, before `if !fields.is_empty()`:

```rust
    if let Some(Some(ref name)) = update.principal_name {
        if name.chars().count() > 200 {
            fields
                .entry("principal_name".into())
                .or_default()
                .push("principal_name must be at most 200 characters".into());
        }
    }
    if let Some(Some(ref nip)) = update.principal_nip {
        if nip.chars().count() > 64 {
            fields
                .entry("principal_nip".into())
                .or_default()
                .push("principal_nip must be at most 64 characters".into());
        }
    }
```

If any other code constructs `SchoolProfileUpdate { .. }` or `SchoolProfile { .. }` literally (grep both names under `src/` and `tests/`), add the new fields (`None` / `None`, and `updated_at: chrono::Utc::now()` for a test literal).

- [ ] **Step 8: Run the tests to verify they pass**

Run the Step 2 command, then the existing profile and logo tests as regression:

`cargo test -p billing-service --test integration -- --test-threads=2 --exact get_school_profile_returns_current_tenant patch_school_profile_updates_fields patch_school_profile_rejects_invalid_enum school_profile_is_tenant_scoped upload_school_logo_sets_logo_url clear_logo_deletes_object_and_nulls_logo_url`

Then `cargo check --workspace`. Expected: all PASS, check clean.

- [ ] **Step 9: Commit (backend repo)**

```bash
git add services/billing-service/migrations/V5__tenant_principal.sql services/billing-service/src services/billing-service/tests/integration.rs
git commit -m "feat(billing): record the principal on the school profile and publish profile updates"
```

---

### Task 2: Academic-ops — V20, school-profile projection, year names, bootstrap

**Files:**
- Create: `apps/backend/services/academic-ops-service/migrations/V20__promotion_letters.sql`
- Modify: `apps/backend/services/academic-ops-service/src/repo.rs` (new `KnownSchoolProfileRepo` at the end; `KnownAcademicYearRepo` ~805 gains `upsert_created`)
- Modify: `apps/backend/services/academic-ops-service/src/state.rs` (field + constructor)
- Modify: `apps/backend/services/academic-ops-service/src/events.rs` (routing key, consumer field, match arms, payload structs)
- Modify: `apps/backend/services/academic-ops-service/src/main.rs` (~68, `ProjectionConsumer::new` call)
- Modify: `apps/backend/services/academic-ops-service/tests/integration.rs` (every `ProjectionConsumer::new(` call — lines ~788, ~2852, ~3496, ~4170, ~7145 — gains one argument; new tests after `grade_level_created_event_is_consumed_end_to_end` ~3583)
- Modify: `apps/backend/scripts/bootstrap-projections.sh` (`known_academic_year` step ~106; new step after `known_grade_level` ~140)

**Interfaces:**
- Consumes: Task 1's event payload (§2.2 of the spec).
- Produces: tables `known_school_profile`, `promotion_class_letter`; `graduation_record` letter columns; `known_academic_year.name`.
- Produces: `pub struct KnownSchoolProfile { tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village, subdistrict, city_regency, province, postal_code, phone_number, email, logo_url: Option<String>, updated_at: DateTime<Utc> }` (`#[derive(Debug, Clone, Serialize, sqlx::FromRow)]`, all text fields `Option<String>` except `school_name: String`).
- Produces: `KnownSchoolProfileRepo::upsert(&self, p: &KnownSchoolProfile) -> sqlx::Result<bool>` (true when the row was written) and `KnownSchoolProfileRepo::find<'e, E: PgExecutor<'e>>(executor: E, tenant_id: Uuid) -> sqlx::Result<Option<KnownSchoolProfile>>` (associated fn, takes an executor so Task 3 can read it inside a transaction); `AppState.known_school_profiles: KnownSchoolProfileRepo`.
- Produces: `KnownAcademicYearRepo::upsert_created(&self, tenant_id, year_id, status: &str, name: Option<&str>) -> sqlx::Result<()>`.
- `ProjectionConsumer::new` gains a last parameter `known_school_profiles: KnownSchoolProfileRepo`.

- [ ] **Step 1: Write the failing tests**

Add after `grade_level_created_event_is_consumed_end_to_end`:

```rust
fn school_profile(tenant_id: uuid::Uuid, principal: &str, updated_at: chrono::DateTime<chrono::Utc>)
    -> academic_ops_service::repo::KnownSchoolProfile
{
    academic_ops_service::repo::KnownSchoolProfile {
        tenant_id,
        school_name: "SMP Negeri 1".into(),
        npsn: Some("20531234".into()),
        principal_name: Some(principal.into()),
        principal_nip: Some("196805121993032004".into()),
        address_line: Some("Jl. Pemuda 1".into()),
        village: None,
        subdistrict: None,
        city_regency: Some("Surabaya".into()),
        province: Some("Jawa Timur".into()),
        postal_code: None,
        phone_number: None,
        email: None,
        logo_url: Some("/api/v1/billing/media/school/abc".into()),
        updated_at,
    }
}

#[tokio::test]
async fn school_profile_projection_upserts_per_tenant() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_a = uuid::Uuid::new_v4();
    let tenant_b = uuid::Uuid::new_v4();
    let t0 = chrono::Utc::now();

    assert!(state.known_school_profiles.upsert(&school_profile(tenant_a, "Bu A", t0)).await.unwrap());
    assert!(state.known_school_profiles.upsert(&school_profile(tenant_b, "Pak B", t0)).await.unwrap());
    let newer = t0 + chrono::Duration::seconds(5);
    assert!(state.known_school_profiles.upsert(&school_profile(tenant_a, "Bu A2", newer)).await.unwrap());

    let a = academic_ops_service::repo::KnownSchoolProfileRepo::find(&pool, tenant_a).await.unwrap().unwrap();
    let b = academic_ops_service::repo::KnownSchoolProfileRepo::find(&pool, tenant_b).await.unwrap().unwrap();
    assert_eq!(a.principal_name.as_deref(), Some("Bu A2"));
    assert_eq!(b.principal_name.as_deref(), Some("Pak B"));
    assert_eq!(a.logo_url.as_deref(), Some("/api/v1/billing/media/school/abc"));
    assert!(academic_ops_service::repo::KnownSchoolProfileRepo::find(&pool, uuid::Uuid::new_v4())
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn older_school_profile_event_is_ignored() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let t1 = chrono::Utc::now();
    let t0 = t1 - chrono::Duration::seconds(30);

    assert!(state.known_school_profiles.upsert(&school_profile(tenant_id, "Newer", t1)).await.unwrap());
    let written = state.known_school_profiles.upsert(&school_profile(tenant_id, "Older", t0)).await.unwrap();
    assert!(!written, "an older event must not be written");

    let row = academic_ops_service::repo::KnownSchoolProfileRepo::find(&pool, tenant_id).await.unwrap().unwrap();
    assert_eq!(row.principal_name.as_deref(), Some("Newer"));
}

#[tokio::test]
async fn academic_year_created_stores_name() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();
    let year_id = uuid::Uuid::new_v4();

    state.known_years.upsert_created(tenant_id, year_id, "Draft", Some("2026/2027")).await.unwrap();
    // A later status change keeps the name.
    state.known_years.apply_status_change(tenant_id, year_id, "Active").await.unwrap();

    let name: Option<String> =
        sqlx::query_scalar("SELECT name FROM known_academic_year WHERE tenant_id = $1 AND academic_year_id = $2")
            .bind(tenant_id)
            .bind(year_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(name.as_deref(), Some("2026/2027"));
}

#[tokio::test]
async fn school_profile_event_is_consumed_end_to_end() {
    let (pool, state, rabbitmq_url, _pg, _rabbit) = boot().await;
    let tenant_id = uuid::Uuid::new_v4();

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
        state.known_school_profiles.clone(),
    );
    let handle = tokio::spawn(async move { consumer.run().await });

    let conn = Connection::connect(&rabbitmq_url, ConnectionProperties::default()).await.unwrap();
    let channel = conn.create_channel().await.unwrap();
    channel
        .exchange_declare(
            EXCHANGE,
            ExchangeKind::Topic,
            ExchangeDeclareOptions { durable: true, ..Default::default() },
            FieldTable::default(),
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(3000)).await;

    let envelope = json!({
        "event_id": uuid::Uuid::new_v4(),
        "event_type": "tenant.school_profile_updated",
        "occurred_at": chrono::Utc::now(),
        "payload": {
            "tenant_id": tenant_id,
            "school_name": "SMP Negeri 1",
            "npsn": null,
            "principal_name": "Dra. Siti Rahayu",
            "principal_nip": null,
            "address_line": null, "village": null, "subdistrict": null,
            "city_regency": "Surabaya", "province": null, "postal_code": null,
            "phone_number": null, "email": null, "logo_url": null,
            "updated_at": chrono::Utc::now(),
        },
    });
    channel
        .basic_publish(
            EXCHANGE,
            "tenant.school_profile_updated",
            lapin::options::BasicPublishOptions::default(),
            &serde_json::to_vec(&envelope).unwrap(),
            lapin::BasicProperties::default().with_content_type("application/json".into()),
        )
        .await
        .unwrap()
        .await
        .unwrap();

    let mut found = None;
    for _ in 0..100 {
        found = academic_ops_service::repo::KnownSchoolProfileRepo::find(&pool, tenant_id).await.unwrap();
        if found.is_some() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    handle.abort();
    let row = found.expect("tenant.school_profile_updated must be routed and projected");
    assert_eq!(row.principal_name.as_deref(), Some("Dra. Siti Rahayu"));
    assert_eq!(row.city_regency.as_deref(), Some("Surabaya"));
}
```

Also add `state.known_school_profiles.clone(),` as the last argument of every other `ProjectionConsumer::new(` call in the test file.

- [ ] **Step 2: Run the tests to verify they fail**

`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact school_profile_projection_upserts_per_tenant older_school_profile_event_is_ignored academic_year_created_stores_name school_profile_event_is_consumed_end_to_end`

Expected: compile error — `KnownSchoolProfile`, `known_school_profiles`, `upsert_created` do not exist. This is the named RED for a new projection; record it. Then, so a behaviour RED is also on record, temporarily comment out the four new tests and the extra constructor argument, add only the migration (Step 3) and a stub `upsert_created` that calls `self.upsert(tenant_id, year_id, status)` and ignores `name`; re-enable `academic_year_created_stores_name` alone and run it: it must FAIL with `left: None, right: Some("2026/2027")`. Record that, then continue.

- [ ] **Step 3: Migration**

`migrations/V20__promotion_letters.sql`:

```sql
-- Promotion letters (Plan 3e): SK Kenaikan Kelas per source homeroom and
-- Surat Keterangan Lulus per graduate, plus the projections the letters and
-- their print pages read (spec §2.3, §3.1).
--
-- known_school_profile mirrors billing's school profile via
-- tenant.school_profile_updated; rows are replaced only by a newer updated_at.
-- known_academic_year.name comes from academic_year.created; renames are not
-- propagated (no rename event exists — see docs/superpowers/backlog.md).
--
-- A letter snapshots school_name / principal_name / principal_nip when first
-- issued; corrections change number, date and city only. A graduate counts as
-- issued once certificate_number is set.

CREATE TABLE IF NOT EXISTS known_school_profile (
  tenant_id      UUID PRIMARY KEY,
  school_name    VARCHAR(200) NOT NULL,
  npsn           VARCHAR(32),
  principal_name VARCHAR(200),
  principal_nip  VARCHAR(64),
  address_line   VARCHAR(500),
  village        VARCHAR(200),
  subdistrict    VARCHAR(200),
  city_regency   VARCHAR(200),
  province       VARCHAR(200),
  postal_code    VARCHAR(16),
  phone_number   VARCHAR(64),
  email          VARCHAR(320),
  logo_url       VARCHAR(500),
  updated_at     TIMESTAMPTZ NOT NULL
);

ALTER TABLE known_academic_year ADD COLUMN IF NOT EXISTS name VARCHAR(100);

CREATE TABLE IF NOT EXISTS promotion_class_letter (
  letter_id      UUID PRIMARY KEY,
  tenant_id      UUID NOT NULL,
  run_id         UUID NOT NULL REFERENCES promotion_run (run_id),
  homeroom_id    UUID NOT NULL,
  letter_number  VARCHAR(64) NOT NULL,
  letter_date    DATE NOT NULL,
  city           VARCHAR(200) NOT NULL,
  school_name    VARCHAR(200) NOT NULL,
  principal_name VARCHAR(200) NOT NULL,
  principal_nip  VARCHAR(64),
  issued_by      UUID NOT NULL,
  issued_at      TIMESTAMPTZ NOT NULL,
  updated_by     UUID NOT NULL,
  updated_at     TIMESTAMPTZ NOT NULL,
  CONSTRAINT promotion_class_letter_run_homeroom_unique UNIQUE (run_id, homeroom_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS promotion_class_letter_number_uidx
  ON promotion_class_letter (tenant_id, letter_number);

ALTER TABLE graduation_record
  ADD COLUMN IF NOT EXISTS letter_date    DATE,
  ADD COLUMN IF NOT EXISTS city           VARCHAR(200),
  ADD COLUMN IF NOT EXISTS school_name    VARCHAR(200),
  ADD COLUMN IF NOT EXISTS principal_name VARCHAR(200),
  ADD COLUMN IF NOT EXISTS principal_nip  VARCHAR(64),
  ADD COLUMN IF NOT EXISTS issued_by      UUID,
  ADD COLUMN IF NOT EXISTS issued_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_by     UUID,
  ADD COLUMN IF NOT EXISTS updated_at     TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS graduation_record_certificate_number_uidx
  ON graduation_record (tenant_id, certificate_number)
  WHERE certificate_number IS NOT NULL;
```

- [ ] **Step 4: Repo**

At the end of `src/repo.rs`:

```rust
/// Letterhead + principal mirrored from billing (`tenant.school_profile_updated`,
/// Plan 3e §2.3). One row per tenant.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct KnownSchoolProfile {
    pub tenant_id: Uuid,
    pub school_name: String,
    pub npsn: Option<String>,
    pub principal_name: Option<String>,
    pub principal_nip: Option<String>,
    pub address_line: Option<String>,
    pub village: Option<String>,
    pub subdistrict: Option<String>,
    pub city_regency: Option<String>,
    pub province: Option<String>,
    pub postal_code: Option<String>,
    pub phone_number: Option<String>,
    pub email: Option<String>,
    pub logo_url: Option<String>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Clone)]
pub struct KnownSchoolProfileRepo(PgPool);

impl KnownSchoolProfileRepo {
    pub fn new(pool: PgPool) -> Self {
        Self(pool)
    }

    /// Inserts, or replaces only when `p.updated_at` is newer than the stored
    /// row, so a late older event never overwrites a newer one. Returns
    /// whether a row was written.
    pub async fn upsert(&self, p: &KnownSchoolProfile) -> sqlx::Result<bool> {
        let written = sqlx::query(
            "INSERT INTO known_school_profile \
               (tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village, \
                subdistrict, city_regency, province, postal_code, phone_number, email, logo_url, updated_at) \
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) \
             ON CONFLICT (tenant_id) DO UPDATE SET \
               school_name = EXCLUDED.school_name, npsn = EXCLUDED.npsn, \
               principal_name = EXCLUDED.principal_name, principal_nip = EXCLUDED.principal_nip, \
               address_line = EXCLUDED.address_line, village = EXCLUDED.village, \
               subdistrict = EXCLUDED.subdistrict, city_regency = EXCLUDED.city_regency, \
               province = EXCLUDED.province, postal_code = EXCLUDED.postal_code, \
               phone_number = EXCLUDED.phone_number, email = EXCLUDED.email, \
               logo_url = EXCLUDED.logo_url, updated_at = EXCLUDED.updated_at \
             WHERE known_school_profile.updated_at < EXCLUDED.updated_at",
        )
        .bind(p.tenant_id)
        .bind(&p.school_name)
        .bind(&p.npsn)
        .bind(&p.principal_name)
        .bind(&p.principal_nip)
        .bind(&p.address_line)
        .bind(&p.village)
        .bind(&p.subdistrict)
        .bind(&p.city_regency)
        .bind(&p.province)
        .bind(&p.postal_code)
        .bind(&p.phone_number)
        .bind(&p.email)
        .bind(&p.logo_url)
        .bind(p.updated_at)
        .execute(&self.0)
        .await?;
        Ok(written.rows_affected() == 1)
    }

    pub async fn find<'e, E: PgExecutor<'e>>(
        executor: E,
        tenant_id: Uuid,
    ) -> sqlx::Result<Option<KnownSchoolProfile>> {
        sqlx::query_as(
            "SELECT tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village, \
                    subdistrict, city_regency, province, postal_code, phone_number, email, logo_url, updated_at \
             FROM known_school_profile WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .fetch_optional(executor)
        .await
    }
}
```

In `impl KnownAcademicYearRepo`, after `upsert`:

```rust
    /// `academic_year.created`: also stores the year's name (Plan 3e §2.3).
    /// A replayed event refreshes the name only when one is given.
    pub async fn upsert_created(
        &self,
        tenant_id: Uuid,
        year_id: Uuid,
        status: &str,
        name: Option<&str>,
    ) -> sqlx::Result<()> {
        sqlx::query(
            "INSERT INTO known_academic_year (academic_year_id, tenant_id, status, name) VALUES ($1,$2,$3,$4) \
             ON CONFLICT (academic_year_id) DO UPDATE SET status = EXCLUDED.status, \
               name = COALESCE(EXCLUDED.name, known_academic_year.name), updated_at = NOW()",
        )
        .bind(year_id)
        .bind(tenant_id)
        .bind(status)
        .bind(name)
        .execute(&self.0)
        .await?;
        Ok(())
    }
```

- [ ] **Step 5: State**

In `src/state.rs`, import `KnownSchoolProfileRepo` with the other repos, add `pub known_school_profiles: KnownSchoolProfileRepo,` after `known_report_types`, and `known_school_profiles: KnownSchoolProfileRepo::new(pool.clone()),` in `new`.

- [ ] **Step 6: Consumer**

In `src/events.rs`:
- import `KnownSchoolProfile, KnownSchoolProfileRepo` from `crate::repo`;
- add `"tenant.school_profile_updated",` to `ROUTING_KEYS`;
- add `known_school_profiles: KnownSchoolProfileRepo,` to `ProjectionConsumer`, as the last `new` parameter, and to the struct literal;
- change the `academic_year.created` arm to

```rust
            "academic_year.created" => {
                let payload: AcademicYearCreatedPayload =
                    serde_json::from_value(envelope.payload)?;
                self.years
                    .upsert_created(
                        payload.tenant_id,
                        payload.academic_year_id,
                        payload.status.as_deref().unwrap_or("Draft"),
                        payload.name.as_deref(),
                    )
                    .await?;
            }
```

and add `name: Option<String>,` to `AcademicYearCreatedPayload`;
- add before `_ => {}`:

```rust
            "tenant.school_profile_updated" => {
                let p: KnownSchoolProfile = serde_json::from_value(envelope.payload)?;
                self.known_school_profiles.upsert(&p).await?;
            }
```

`KnownSchoolProfile` therefore also needs `Deserialize`: change its derive to `#[derive(Debug, Clone, Serialize, serde::Deserialize, sqlx::FromRow)]`.

In `src/main.rs`, add `consumer_state.known_school_profiles.clone(),` as the last argument of `ProjectionConsumer::new`.

- [ ] **Step 7: Bootstrap script**

In `apps/backend/scripts/bootstrap-projections.sh`, change the `known_academic_year` step to copy the name:

```bash
run_upsert "academic_ops.known_academic_year" "academic_ops.known_academic_year academic_config.academic_year" "
WITH upserted AS (
  INSERT INTO academic_ops.known_academic_year (academic_year_id, tenant_id, status, name)
  SELECT academic_year_id, tenant_id, status, name
  FROM academic_config.academic_year
  ON CONFLICT (academic_year_id) DO UPDATE
  SET status = EXCLUDED.status,
      name = EXCLUDED.name,
      updated_at = NOW()
  RETURNING 1
)
SELECT COUNT(*) FROM upserted;
"
```

and add after the `known_grade_level` step:

```bash
# academic_ops.known_school_profile: letterhead + principal for promotion
# letters (Plan 3e). Mirrors billing.tenant; later profile edits arrive as
# tenant.school_profile_updated. logo_url is converted from the stored
# media://<owner>/<media_id>.<ext> URI to the public serve path, matching
# billing's resolve_media_uri_for_owner with an empty MEDIA_PUBLIC_BASE_URL.
run_upsert "academic_ops.known_school_profile" "academic_ops.known_school_profile billing.tenant" "
WITH upserted AS (
  INSERT INTO academic_ops.known_school_profile
    (tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village,
     subdistrict, city_regency, province, postal_code, phone_number, email, logo_url, updated_at)
  SELECT tenant_id, school_name, npsn, principal_name, principal_nip, address_line, village,
         subdistrict, city_regency, province, postal_code, phone_number, email,
         CASE WHEN logo_url LIKE 'media://%'
              THEN '/api/v1/billing/media/school/' || split_part(split_part(logo_url, '/', 4), '.', 1)
              ELSE logo_url END,
         updated_at
  FROM billing.tenant
  ON CONFLICT (tenant_id) DO UPDATE
  SET school_name = EXCLUDED.school_name, npsn = EXCLUDED.npsn,
      principal_name = EXCLUDED.principal_name, principal_nip = EXCLUDED.principal_nip,
      address_line = EXCLUDED.address_line, village = EXCLUDED.village,
      subdistrict = EXCLUDED.subdistrict, city_regency = EXCLUDED.city_regency,
      province = EXCLUDED.province, postal_code = EXCLUDED.postal_code,
      phone_number = EXCLUDED.phone_number, email = EXCLUDED.email,
      logo_url = EXCLUDED.logo_url, updated_at = EXCLUDED.updated_at
  WHERE academic_ops.known_school_profile.updated_at <= EXCLUDED.updated_at
  RETURNING 1
)
SELECT COUNT(*) FROM upserted;
"
```

(`media://<owner>/<media_id>.<ext>` split on `/` gives `media:`, ``, `<owner>`, `<media_id>.<ext>`; part 4 then split on `.` gives the id.) Run `bash -n apps/backend/scripts/bootstrap-projections.sh` to syntax-check.

- [ ] **Step 8: Run the tests to verify they pass**

Run the Step 2 command (all four), then regression: `cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact grade_level_created_event_is_consumed_end_to_end` plus the test containing line ~788 (find its name with `grep -n "async fn" tests/integration.rs | awk -F: '$1<788' | tail -1`). Then `cargo check --workspace`. Expected: PASS, check clean.

- [ ] **Step 9: Commit (backend repo)**

```bash
git add services/academic-ops-service scripts/bootstrap-projections.sh
git commit -m "feat(academic-ops): project the school profile and academic year names for letters"
```

---

### Task 3: Academic-ops — letters module, letters summary, class letters (SK)

**Files:**
- Create: `apps/backend/services/academic-ops-service/src/promotion/letters/mod.rs`
- Create: `apps/backend/services/academic-ops-service/src/promotion/letters/repo.rs`
- Create: `apps/backend/services/academic-ops-service/src/promotion/letters/commands.rs`
- Create: `apps/backend/services/academic-ops-service/src/promotion/letters/queries.rs`
- Modify: `apps/backend/services/academic-ops-service/src/promotion/mod.rs` (add `pub mod letters;`)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/http.rs` (routes + handlers)
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs` (new section at the end)

**Interfaces:**
- Consumes: Task 2 `KnownSchoolProfile`, `KnownSchoolProfileRepo::find(executor, tenant_id)`, `known_academic_year.name`, `promotion_class_letter`; existing `crate::promotion::repo::lock_run_row(&mut PgConnection, tenant, run) -> Option<LockedRun{status, academic_year_id, target_academic_year_id}>`, `crate::promotion::commands::ResultCounts { promote, retain, graduate }`.
- Produces (Rust, used by Task 4): in `letters::repo` — `RunHeader`, `run_header`, `LetterSnapshot { school_name: String, principal_name: String, principal_nip: Option<String> }`, `year_name`; in `letters::commands` — `executed_status_error()`, `check_number(&str) -> Result<String, &'static str>`, `snapshot_of(Option<&KnownSchoolProfile>) -> Option<LetterSnapshot>`, `resolve_city(Option<&str>, Option<&KnownSchoolProfile>) -> Option<String>`, `push_error(&mut BTreeMap<String, Vec<String>>, &str, impl Into<String>)`, consts `NO_PRINCIPAL`, `NUMBER_TAKEN`; in `letters::queries` — `executed_run(state, tenant, run) -> Result<RunHeader, AppError>`.
- Produces (HTTP, used by Tasks 5–9):
  - `GET /promotion-runs/:run_id/letters` → `{ school_profile: KnownSchoolProfile|null, class_letters: [{homeroom_id, homeroom_name, counts: {promote, retain, graduate}, letter: ClassLetter|null}], certificates: {graduates, issued} }`
  - `GET /promotion-runs/:run_id/class-letters/:homeroom_id` → `{ letterhead: KnownSchoolProfile|null, source_year_name, target_year_name, homeroom_id, homeroom_name, letter: ClassLetter|null, students: [{student_id, full_name, nis, nisn, result, target_homeroom_name}] }`
  - `PUT /promotion-runs/:run_id/class-letters/:homeroom_id` body `{letter_number, letter_date, city?}` → `ClassLetter`
  - `ClassLetter` = `{homeroom_id, letter_number, letter_date: "YYYY-MM-DD", city, school_name, principal_name, principal_nip, issued_by, issued_at, updated_by, updated_at}`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/integration.rs`:

```rust
// ---------------------------------------------------------------------------
// Plan 3e: promotion letters
// ---------------------------------------------------------------------------

async fn put_json(app: axum::Router, token: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    let resp = app
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(uri)
                .header(header::AUTHORIZATION, format!("Bearer {token}"))
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    (status, body_to_json(resp).await)
}

/// Upserts the letterhead projection; every call is newer than the last.
async fn seed_school_profile(pool: &PgPool, tenant_id: uuid::Uuid, principal: Option<&str>, city: Option<&str>) {
    sqlx::query(
        "INSERT INTO known_school_profile \
           (tenant_id, school_name, npsn, principal_name, principal_nip, address_line, city_regency, logo_url, updated_at) \
         VALUES ($1, 'SMP Negeri 1', '20531234', $2, '196805121993032004', 'Jl. Pemuda 1', $3, \
                 '/api/v1/billing/media/school/logo-1', clock_timestamp()) \
         ON CONFLICT (tenant_id) DO UPDATE SET principal_name = EXCLUDED.principal_name, \
           city_regency = EXCLUDED.city_regency, updated_at = EXCLUDED.updated_at",
    )
    .bind(tenant_id)
    .bind(principal)
    .bind(city)
    .execute(pool)
    .await
    .unwrap();
}

/// `ready_to_execute`, executed, with a letterhead (principal "Dra. Siti
/// Rahayu", city Surabaya) and year names 2025/2026 → 2026/2027.
/// Source homerooms: Mid-A (promote + retain students), Final-A (graduate).
async fn executed_letters_fixture(pool: &PgPool, state: &AppState) -> (ExecutionFixture, axum::Router) {
    let (ex, app) = ready_to_execute(pool, state).await;
    let (status, body) = execute_req(app.clone(), &ex.admin_token, ex.run_id).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    seed_school_profile(pool, ex.fx.tenant_id, Some("Dra. Siti Rahayu"), Some("Surabaya")).await;
    for (year, name) in [(ex.fx.year_id, "2025/2026"), (ex.target_year_id, "2026/2027")] {
        sqlx::query("UPDATE known_academic_year SET name = $1 WHERE academic_year_id = $2")
            .bind(name)
            .bind(year)
            .execute(pool)
            .await
            .unwrap();
    }
    (ex, app)
}

fn class_letter_uri(run_id: uuid::Uuid, homeroom_id: uuid::Uuid) -> String {
    format!("/api/v1/academic-ops/promotion-runs/{run_id}/class-letters/{homeroom_id}")
}

fn letters_uri(run_id: uuid::Uuid) -> String {
    format!("/api/v1/academic-ops/promotion-runs/{run_id}/letters")
}

fn principal_token(tenant_id: uuid::Uuid) -> String {
    common_testing::mint_jwt(uuid::Uuid::new_v4(), tenant_id, "principal").0
}

#[tokio::test]
async fn class_letter_first_issue_snapshots_principal() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;

    let (status, body) = put_json(
        app,
        &ex.admin_token,
        &class_letter_uri(ex.run_id, ex.fx.mid_homeroom),
        json!({ "letter_number": "  421/001/SK/2026  ", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let l = &body["data"];
    assert_eq!(l["homeroom_id"], ex.fx.mid_homeroom.to_string());
    assert_eq!(l["letter_number"], "421/001/SK/2026");
    assert_eq!(l["letter_date"], "2026-06-20");
    assert_eq!(l["city"], "Surabaya", "city defaults to the profile's city_regency");
    assert_eq!(l["school_name"], "SMP Negeri 1");
    assert_eq!(l["principal_name"], "Dra. Siti Rahayu");
    assert_eq!(l["principal_nip"], "196805121993032004");
    assert_eq!(l["issued_by"], l["updated_by"]);
    assert!(l["issued_at"].is_string());
}

#[tokio::test]
async fn class_letter_correction_keeps_snapshot() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let uri = class_letter_uri(ex.run_id, ex.fx.mid_homeroom);

    let (status, first) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_number": "421/001", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {first}");

    seed_school_profile(&pool, ex.fx.tenant_id, Some("Pak Baru"), Some("Surabaya")).await;
    let (status, body) = put_json(
        app,
        &ex.admin_token,
        &uri,
        json!({ "letter_number": "421/002", "letter_date": "2026-06-21", "city": "Sidoarjo" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let l = &body["data"];
    assert_eq!(l["letter_number"], "421/002");
    assert_eq!(l["letter_date"], "2026-06-21");
    assert_eq!(l["city"], "Sidoarjo");
    assert_eq!(l["principal_name"], "Dra. Siti Rahayu", "a correction never re-snapshots");
    assert_eq!(l["issued_at"], first["data"]["issued_at"]);

    let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM promotion_class_letter WHERE run_id = $1")
        .bind(ex.run_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rows, 1);
}

#[tokio::test]
async fn class_letter_validates_fields_city_and_principal() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let uri = class_letter_uri(ex.run_id, ex.fx.mid_homeroom);

    let (status, body) = put_json(app.clone(), &ex.admin_token, &uri, json!({ "letter_number": "   " })).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(body["error"]["fields"]["letter_number"][0], "is required");
    assert_eq!(body["error"]["fields"]["letter_date"][0], "is required");

    let (status, body) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_number": "x".repeat(65), "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["fields"]["letter_number"][0], "must be at most 64 characters");

    seed_school_profile(&pool, ex.fx.tenant_id, None, None).await;
    let (status, body) = put_json(
        app,
        &ex.admin_token,
        &uri,
        json!({ "letter_number": "421/001", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(body["error"]["fields"]["city"][0], "is required");
    assert_eq!(body["error"]["fields"]["principal"][0], "school profile has no principal name");

    let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM promotion_class_letter WHERE run_id = $1")
        .bind(ex.run_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rows, 0, "nothing is written on a rejected issue");
}

#[tokio::test]
async fn class_letter_rejects_number_used_in_tenant() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let body = json!({ "letter_number": "421/001", "letter_date": "2026-06-20" });

    let (status, _) = put_json(app.clone(), &ex.admin_token, &class_letter_uri(ex.run_id, ex.fx.mid_homeroom), body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    let (status, resp) = put_json(app, &ex.admin_token, &class_letter_uri(ex.run_id, ex.fx.final_homeroom), body).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {resp}");
    assert_eq!(resp["error"]["fields"]["letter_number"][0], "is already used by another letter");
}

#[tokio::test]
async fn class_letter_needs_executed_run_and_source_homeroom() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let body = json!({ "letter_number": "421/001", "letter_date": "2026-06-20" });

    // Approved, not executed.
    let (ex, app) = ready_to_execute(&pool, &state).await;
    let (status, resp) = put_json(app.clone(), &ex.admin_token, &class_letter_uri(ex.run_id, ex.fx.mid_homeroom), body.clone()).await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {resp}");
    assert_eq!(resp["error"]["code"], "PROMOTION_RUN_INVALID_STATUS");
    let (status, _) = get_json(app, &ex.admin_token, &letters_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Executed: a target homeroom is not a source homeroom of the run.
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let (status, _) = put_json(app.clone(), &ex.admin_token, &class_letter_uri(ex.run_id, ex.target_mid_homeroom), body.clone()).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = get_json(app.clone(), &ex.admin_token, &class_letter_uri(ex.run_id, ex.target_mid_homeroom)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Another tenant sees nothing.
    let tenant_b = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_b).await;
    let token_b = jwt_for(tenant_b);
    let (status, _) = get_json(app.clone(), &token_b, &letters_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = put_json(app, &token_b, &class_letter_uri(ex.run_id, ex.fx.mid_homeroom), body).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn principal_reads_letters_but_cannot_issue() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let token = principal_token(ex.fx.tenant_id);

    let (status, _) = get_json(app.clone(), &token, &letters_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = get_json(app.clone(), &token, &class_letter_uri(ex.run_id, ex.fx.mid_homeroom)).await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = put_json(
        app,
        &token,
        &class_letter_uri(ex.run_id, ex.fx.mid_homeroom),
        json!({ "letter_number": "421/001", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "body: {body}");
}

#[tokio::test]
async fn letters_summary_and_class_letter_print_data() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let (status, _) = put_json(
        app.clone(),
        &ex.admin_token,
        &class_letter_uri(ex.run_id, ex.fx.mid_homeroom),
        json!({ "letter_number": "421/001", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, body) = get_json(app.clone(), &ex.admin_token, &letters_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let s = &body["data"];
    assert_eq!(s["school_profile"]["principal_name"], "Dra. Siti Rahayu");
    let classes = s["class_letters"].as_array().unwrap();
    assert_eq!(classes.len(), 2);
    let mid = classes.iter().find(|c| c["homeroom_name"] == "Mid-A").unwrap();
    assert_eq!(mid["counts"], json!({ "promote": 1, "retain": 1, "graduate": 0 }));
    assert_eq!(mid["letter"]["letter_number"], "421/001");
    let fin = classes.iter().find(|c| c["homeroom_name"] == "Final-A").unwrap();
    assert_eq!(fin["counts"]["graduate"], 1);
    assert!(fin["letter"].is_null());
    assert_eq!(s["certificates"], json!({ "graduates": 1, "issued": 0 }));

    // Print data (read by a principal token: the print page's caller may be the principal).
    let (status, body) = get_json(app, &principal_token(ex.fx.tenant_id), &class_letter_uri(ex.run_id, ex.fx.mid_homeroom)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let p = &body["data"];
    assert_eq!(p["source_year_name"], "2025/2026");
    assert_eq!(p["target_year_name"], "2026/2027");
    assert_eq!(p["homeroom_name"], "Mid-A");
    assert_eq!(p["letterhead"]["logo_url"], "/api/v1/billing/media/school/logo-1");
    assert_eq!(p["letter"]["letter_number"], "421/001");
    let students = p["students"].as_array().unwrap();
    assert_eq!(students.len(), 2, "source enrollments are closed after execution; rows still come back");
    let promoted = students.iter().find(|r| r["student_id"] == ex.promote_student.to_string()).unwrap();
    assert_eq!(promoted["result"], "promote");
    assert_eq!(promoted["full_name"], "Promo Student");
    assert_eq!(promoted["target_homeroom_name"], "Final-B");
    let retained = students.iter().find(|r| r["student_id"] == ex.retain_student.to_string()).unwrap();
    assert_eq!(retained["target_homeroom_name"], "Mid-B");
}
```

- [ ] **Step 2: Run the tests to verify they fail**

`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact class_letter_first_issue_snapshots_principal class_letter_correction_keeps_snapshot class_letter_validates_fields_city_and_principal class_letter_rejects_number_used_in_tenant class_letter_needs_executed_run_and_source_homeroom principal_reads_letters_but_cannot_issue letters_summary_and_class_letter_print_data`

Expected: all FAIL — every request to the new paths returns 404/405 (route missing); e.g. `left: 405, right: 200`. Record the outputs.

- [ ] **Step 3: Module, repo**

`src/promotion/mod.rs`: add `pub mod letters;`.

`src/promotion/letters/mod.rs`:

```rust
//! Promotion letters (Plan 3e): SK Kenaikan Kelas per source homeroom and
//! Surat Keterangan Lulus per graduate. Only executed runs have letters.
//! `repo` owns SQL, `commands` the writes, `queries` the reads (CQRS split,
//! CONVENTIONS.md §1).

pub mod commands;
pub mod queries;
pub mod repo;
```

`src/promotion/letters/repo.rs`:

```rust
use chrono::{DateTime, NaiveDate, Utc};
use serde::Serialize;
use sqlx::{PgConnection, PgExecutor, PgPool};
use uuid::Uuid;

pub struct RunHeader {
    pub status: String,
    pub academic_year_id: Uuid,
    pub target_academic_year_id: Option<Uuid>,
}

pub async fn run_header(pool: &PgPool, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<Option<RunHeader>> {
    let row: Option<(String, Uuid, Option<Uuid>)> = sqlx::query_as(
        "SELECT status, academic_year_id, target_academic_year_id FROM promotion_run \
         WHERE tenant_id = $1 AND run_id = $2",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|(status, academic_year_id, target_academic_year_id)| RunHeader {
        status,
        academic_year_id,
        target_academic_year_id,
    }))
}

/// What a letter freezes when first issued (spec Q1).
#[derive(Clone)]
pub struct LetterSnapshot {
    pub school_name: String,
    pub principal_name: String,
    pub principal_nip: Option<String>,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct ClassLetter {
    pub homeroom_id: Uuid,
    pub letter_number: String,
    pub letter_date: NaiveDate,
    pub city: String,
    pub school_name: String,
    pub principal_name: String,
    pub principal_nip: Option<String>,
    pub issued_by: Uuid,
    pub issued_at: DateTime<Utc>,
    pub updated_by: Uuid,
    pub updated_at: DateTime<Utc>,
}

const CLASS_LETTER_COLUMNS: &str = "homeroom_id, letter_number, letter_date, city, school_name, \
     principal_name, principal_nip, issued_by, issued_at, updated_by, updated_at";

pub async fn find_class_letter<'e, E: PgExecutor<'e>>(
    executor: E,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
) -> sqlx::Result<Option<ClassLetter>> {
    sqlx::query_as(&format!(
        "SELECT {CLASS_LETTER_COLUMNS} FROM promotion_class_letter \
         WHERE tenant_id = $1 AND run_id = $2 AND homeroom_id = $3"
    ))
    .bind(tenant_id)
    .bind(run_id)
    .bind(homeroom_id)
    .fetch_optional(executor)
    .await
}

pub async fn class_letters_for_run(pool: &PgPool, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<Vec<ClassLetter>> {
    sqlx::query_as(&format!(
        "SELECT {CLASS_LETTER_COLUMNS} FROM promotion_class_letter WHERE tenant_id = $1 AND run_id = $2"
    ))
    .bind(tenant_id)
    .bind(run_id)
    .fetch_all(pool)
    .await
}

/// A homeroom is a source homeroom of the run when some decision starts there.
pub async fn is_source_homeroom(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
) -> sqlx::Result<bool> {
    sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM promotion_decision \
                        WHERE tenant_id = $1 AND run_id = $2 AND homeroom_id = $3)",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(homeroom_id)
    .fetch_one(&mut *conn)
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn insert_class_letter(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
    letter_number: &str,
    letter_date: NaiveDate,
    city: &str,
    snapshot: &LetterSnapshot,
    user_id: Uuid,
) -> sqlx::Result<ClassLetter> {
    sqlx::query_as(&format!(
        "INSERT INTO promotion_class_letter \
           (letter_id, tenant_id, run_id, homeroom_id, letter_number, letter_date, city, school_name, \
            principal_name, principal_nip, issued_by, issued_at, updated_by, updated_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), $11, NOW()) \
         RETURNING {CLASS_LETTER_COLUMNS}"
    ))
    .bind(Uuid::new_v4())
    .bind(tenant_id)
    .bind(run_id)
    .bind(homeroom_id)
    .bind(letter_number)
    .bind(letter_date)
    .bind(city)
    .bind(&snapshot.school_name)
    .bind(&snapshot.principal_name)
    .bind(&snapshot.principal_nip)
    .bind(user_id)
    .fetch_one(&mut *conn)
    .await
}

/// Correction: number, date, city and `updated_*` only — never the snapshot.
#[allow(clippy::too_many_arguments)]
pub async fn update_class_letter(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
    letter_number: &str,
    letter_date: NaiveDate,
    city: &str,
    user_id: Uuid,
) -> sqlx::Result<ClassLetter> {
    sqlx::query_as(&format!(
        "UPDATE promotion_class_letter \
         SET letter_number = $4, letter_date = $5, city = $6, updated_by = $7, updated_at = NOW() \
         WHERE tenant_id = $1 AND run_id = $2 AND homeroom_id = $3 \
         RETURNING {CLASS_LETTER_COLUMNS}"
    ))
    .bind(tenant_id)
    .bind(run_id)
    .bind(homeroom_id)
    .bind(letter_number)
    .bind(letter_date)
    .bind(city)
    .bind(user_id)
    .fetch_one(&mut *conn)
    .await
}

#[derive(sqlx::FromRow)]
pub struct SourceHomeroomRow {
    pub homeroom_id: Uuid,
    pub homeroom_name: Option<String>,
    pub promote: i64,
    pub retain: i64,
    pub graduate: i64,
}

pub async fn source_homerooms(pool: &PgPool, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<Vec<SourceHomeroomRow>> {
    sqlx::query_as(
        "SELECT d.homeroom_id, h.name AS homeroom_name, \
                COUNT(*) FILTER (WHERE d.result = 'promote') AS promote, \
                COUNT(*) FILTER (WHERE d.result = 'retain') AS retain, \
                COUNT(*) FILTER (WHERE d.result = 'graduate') AS graduate \
         FROM promotion_decision d \
         LEFT JOIN homeroom h ON h.tenant_id = d.tenant_id AND h.homeroom_id = d.homeroom_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 \
         GROUP BY d.homeroom_id, h.name \
         ORDER BY h.name NULLS LAST, d.homeroom_id",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_all(pool)
    .await
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ClassLetterStudent {
    pub student_id: Uuid,
    pub full_name: Option<String>,
    pub nis: Option<String>,
    pub nisn: Option<String>,
    pub result: String,
    pub target_homeroom_name: Option<String>,
}

/// Students of one source homeroom with their result and target class.
/// Reads decisions + `student` + `homeroom`, never enrollments, so the rows
/// survive execution closing the source enrollments.
pub async fn class_letter_students(
    pool: &PgPool,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
) -> sqlx::Result<Vec<ClassLetterStudent>> {
    sqlx::query_as(
        "SELECT d.student_id, s.full_name, s.nis, s.nisn, d.result, th.name AS target_homeroom_name \
         FROM promotion_decision d \
         LEFT JOIN student s ON s.tenant_id = d.tenant_id AND s.student_id = d.student_id \
         LEFT JOIN homeroom th ON th.tenant_id = d.tenant_id AND th.homeroom_id = d.target_homeroom_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.homeroom_id = $3 \
         ORDER BY s.full_name NULLS LAST, d.student_id",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(homeroom_id)
    .fetch_all(pool)
    .await
}

pub async fn year_name(pool: &PgPool, tenant_id: Uuid, academic_year_id: Uuid) -> sqlx::Result<Option<String>> {
    let name: Option<Option<String>> = sqlx::query_scalar(
        "SELECT name FROM known_academic_year WHERE tenant_id = $1 AND academic_year_id = $2",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .fetch_optional(pool)
    .await?;
    Ok(name.flatten())
}

/// (graduates of the run, graduates with a certificate number).
pub async fn certificate_counts(pool: &PgPool, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<(i64, i64)> {
    sqlx::query_as(
        "SELECT COUNT(*), COUNT(g.certificate_number) \
         FROM promotion_decision d \
         JOIN graduation_record g ON g.tenant_id = d.tenant_id AND g.student_id = d.student_id \
                                 AND g.academic_year_id = d.academic_year_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.result = 'graduate'",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_one(pool)
    .await
}
```

- [ ] **Step 4: Commands**

`src/promotion/letters/commands.rs`:

```rust
use std::collections::BTreeMap;

use chrono::NaiveDate;
use common_errors::AppError;
use uuid::Uuid;

use crate::promotion::letters::repo::{self, ClassLetter, LetterSnapshot};
use crate::promotion::repo as run_repo;
use crate::repo::{KnownSchoolProfile, KnownSchoolProfileRepo};
use crate::AppState;

pub const NO_PRINCIPAL: &str = "school profile has no principal name";
pub const NUMBER_TAKEN: &str = "is already used by another letter";
const LETTER_NUMBER_MAX: usize = 64;

pub fn executed_status_error() -> AppError {
    AppError::conflict("PROMOTION_RUN_INVALID_STATUS", "promotion run must be in executed status")
}

pub fn push_error(errors: &mut BTreeMap<String, Vec<String>>, field: &str, message: impl Into<String>) {
    errors.entry(field.to_string()).or_default().push(message.into());
}

/// Trimmed letter / certificate number, or the validation message.
pub fn check_number(value: &str) -> Result<String, &'static str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Err("is required")
    } else if trimmed.chars().count() > LETTER_NUMBER_MAX {
        Err("must be at most 64 characters")
    } else {
        Ok(trimmed.to_string())
    }
}

/// `None` when there is no profile or its principal name is blank (spec §2.5).
pub fn snapshot_of(profile: Option<&KnownSchoolProfile>) -> Option<LetterSnapshot> {
    let profile = profile?;
    let name = profile.principal_name.as_deref().map(str::trim).filter(|n| !n.is_empty())?;
    Some(LetterSnapshot {
        school_name: profile.school_name.clone(),
        principal_name: name.to_string(),
        principal_nip: profile.principal_nip.clone(),
    })
}

/// The given city, else the profile's `city_regency`; `None` when both are blank.
pub fn resolve_city(input: Option<&str>, profile: Option<&KnownSchoolProfile>) -> Option<String> {
    let given = input.map(str::trim).filter(|c| !c.is_empty());
    let fallback = profile
        .and_then(|p| p.city_regency.as_deref())
        .map(str::trim)
        .filter(|c| !c.is_empty());
    given.or(fallback).map(str::to_string)
}

pub struct IssueClassLetter {
    pub tenant_id: Uuid,
    pub user_id: Uuid,
    pub run_id: Uuid,
    pub homeroom_id: Uuid,
    pub letter_number: String,
    pub letter_date: Option<NaiveDate>,
    pub city: Option<String>,
}

/// Only the class-letter number index means "number already used"; any
/// other database error is a 500.
fn map_class_letter_error(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(db) = &err {
        if db.constraint() == Some("promotion_class_letter_number_uidx") {
            return AppError::validation_error_single("letter_number", NUMBER_TAKEN);
        }
    }
    AppError::internal(err)
}

/// First call issues the SK (snapshot + `issued_*`); later calls correct
/// number, date and city only (spec §3.2, Q4). The run row is locked so two
/// first issues for the same class cannot race.
pub async fn issue_class_letter(state: &AppState, input: IssueClassLetter) -> Result<ClassLetter, AppError> {
    let mut errors = BTreeMap::new();
    let number = match check_number(&input.letter_number) {
        Ok(n) => Some(n),
        Err(message) => {
            push_error(&mut errors, "letter_number", message);
            None
        }
    };
    if input.letter_date.is_none() {
        push_error(&mut errors, "letter_date", "is required");
    }
    let (Some(number), Some(letter_date)) = (number, input.letter_date) else {
        return Err(AppError::validation_error(errors));
    };

    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let run = run_repo::lock_run_row(&mut tx, input.tenant_id, input.run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "executed" {
        return Err(executed_status_error());
    }
    if !repo::is_source_homeroom(&mut tx, input.tenant_id, input.run_id, input.homeroom_id)
        .await
        .map_err(AppError::internal)?
    {
        return Err(AppError::not_found("homeroom"));
    }

    let profile = KnownSchoolProfileRepo::find(&mut *tx, input.tenant_id)
        .await
        .map_err(AppError::internal)?;
    let existing = repo::find_class_letter(&mut *tx, input.tenant_id, input.run_id, input.homeroom_id)
        .await
        .map_err(AppError::internal)?;
    let city = resolve_city(input.city.as_deref(), profile.as_ref());
    let snapshot = snapshot_of(profile.as_ref());
    if city.is_none() {
        push_error(&mut errors, "city", "is required");
    }
    if existing.is_none() && snapshot.is_none() {
        push_error(&mut errors, "principal", NO_PRINCIPAL);
    }
    let Some(city) = city else {
        return Err(AppError::validation_error(errors));
    };
    if !errors.is_empty() {
        return Err(AppError::validation_error(errors));
    }

    let letter = match (existing, snapshot) {
        (Some(_), _) => repo::update_class_letter(
            &mut tx,
            input.tenant_id,
            input.run_id,
            input.homeroom_id,
            &number,
            letter_date,
            &city,
            input.user_id,
        )
        .await
        .map_err(map_class_letter_error)?,
        (None, Some(snapshot)) => repo::insert_class_letter(
            &mut tx,
            input.tenant_id,
            input.run_id,
            input.homeroom_id,
            &number,
            letter_date,
            &city,
            &snapshot,
            input.user_id,
        )
        .await
        .map_err(map_class_letter_error)?,
        (None, None) => return Err(AppError::validation_error_single("principal", NO_PRINCIPAL)),
    };
    tx.commit().await.map_err(AppError::internal)?;
    Ok(letter)
}
```

- [ ] **Step 5: Queries**

`src/promotion/letters/queries.rs`:

```rust
use common_errors::AppError;
use serde::Serialize;
use uuid::Uuid;

use crate::promotion::commands::ResultCounts;
use crate::promotion::letters::commands::executed_status_error;
use crate::promotion::letters::repo::{self, ClassLetter, ClassLetterStudent, RunHeader};
use crate::repo::{KnownSchoolProfile, KnownSchoolProfileRepo};
use crate::AppState;

/// The run, tenant-scoped (404) and executed (409).
pub async fn executed_run(state: &AppState, tenant_id: Uuid, run_id: Uuid) -> Result<RunHeader, AppError> {
    let run = repo::run_header(&state.pool, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "executed" {
        return Err(executed_status_error());
    }
    Ok(run)
}

#[derive(Serialize)]
pub struct ClassLetterSummary {
    pub homeroom_id: Uuid,
    pub homeroom_name: Option<String>,
    pub counts: ResultCounts,
    pub letter: Option<ClassLetter>,
}

#[derive(Serialize)]
pub struct CertificateSummary {
    pub graduates: i64,
    pub issued: i64,
}

#[derive(Serialize)]
pub struct LettersSummary {
    pub school_profile: Option<KnownSchoolProfile>,
    pub class_letters: Vec<ClassLetterSummary>,
    pub certificates: CertificateSummary,
}

pub async fn letters_summary(state: &AppState, tenant_id: Uuid, run_id: Uuid) -> Result<LettersSummary, AppError> {
    executed_run(state, tenant_id, run_id).await?;
    let school_profile = KnownSchoolProfileRepo::find(&state.pool, tenant_id)
        .await
        .map_err(AppError::internal)?;
    let mut letters = repo::class_letters_for_run(&state.pool, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?;
    let class_letters = repo::source_homerooms(&state.pool, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?
        .into_iter()
        .map(|row| {
            let letter = letters
                .iter()
                .position(|l| l.homeroom_id == row.homeroom_id)
                .map(|i| letters.swap_remove(i));
            ClassLetterSummary {
                homeroom_id: row.homeroom_id,
                homeroom_name: row.homeroom_name,
                counts: ResultCounts { promote: row.promote, retain: row.retain, graduate: row.graduate },
                letter,
            }
        })
        .collect();
    let (graduates, issued) = repo::certificate_counts(&state.pool, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?;
    Ok(LettersSummary {
        school_profile,
        class_letters,
        certificates: CertificateSummary { graduates, issued },
    })
}

#[derive(Serialize)]
pub struct ClassLetterPrint {
    pub letterhead: Option<KnownSchoolProfile>,
    pub source_year_name: Option<String>,
    pub target_year_name: Option<String>,
    pub homeroom_id: Uuid,
    pub homeroom_name: Option<String>,
    pub letter: Option<ClassLetter>,
    pub students: Vec<ClassLetterStudent>,
}

pub async fn class_letter_print(
    state: &AppState,
    tenant_id: Uuid,
    run_id: Uuid,
    homeroom_id: Uuid,
) -> Result<ClassLetterPrint, AppError> {
    let run = executed_run(state, tenant_id, run_id).await?;
    let homeroom = repo::source_homerooms(&state.pool, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?
        .into_iter()
        .find(|h| h.homeroom_id == homeroom_id)
        .ok_or_else(|| AppError::not_found("homeroom"))?;
    let letterhead = KnownSchoolProfileRepo::find(&state.pool, tenant_id)
        .await
        .map_err(AppError::internal)?;
    let source_year_name = repo::year_name(&state.pool, tenant_id, run.academic_year_id)
        .await
        .map_err(AppError::internal)?;
    let target_year_name = match run.target_academic_year_id {
        Some(year) => repo::year_name(&state.pool, tenant_id, year).await.map_err(AppError::internal)?,
        None => None,
    };
    let letter = repo::find_class_letter(&state.pool, tenant_id, run_id, homeroom_id)
        .await
        .map_err(AppError::internal)?;
    let students = repo::class_letter_students(&state.pool, tenant_id, run_id, homeroom_id)
        .await
        .map_err(AppError::internal)?;
    Ok(ClassLetterPrint {
        letterhead,
        source_year_name,
        target_year_name,
        homeroom_id,
        homeroom_name: homeroom.homeroom_name,
        letter,
        students,
    })
}
```

- [ ] **Step 6: HTTP**

In `src/promotion/http.rs`, add to the imports `use chrono::NaiveDate;`, `routing::get` (or use `axum::routing::get` inline as the file does), and `use crate::promotion::letters;`. Add routes inside `routes()` before the closing:

```rust
        .route(
            "/api/v1/academic-ops/promotion-runs/:run_id/letters",
            axum::routing::get(get_promotion_letters),
        )
        .route(
            "/api/v1/academic-ops/promotion-runs/:run_id/class-letters/:homeroom_id",
            axum::routing::get(get_class_letter).put(put_class_letter),
        )
```

Handlers at the end of the file:

```rust
async fn get_promotion_letters(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path(run_id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    require_read_permission(&auth)?;
    let summary = letters::queries::letters_summary(&state, auth.tenant_id, run_id).await?;
    Ok(envelope(summary))
}

async fn get_class_letter(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path((run_id, homeroom_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<Value>, AppError> {
    require_read_permission(&auth)?;
    let print = letters::queries::class_letter_print(&state, auth.tenant_id, run_id, homeroom_id).await?;
    Ok(envelope(print))
}

#[derive(Debug, Deserialize)]
struct ClassLetterBody {
    #[serde(default)]
    letter_number: String,
    letter_date: Option<NaiveDate>,
    city: Option<String>,
}

async fn put_class_letter(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path((run_id, homeroom_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<ClassLetterBody>,
) -> Result<Json<Value>, AppError> {
    auth.require_permission(PERM_PROMOTION_MANAGE)?;
    let letter = letters::commands::issue_class_letter(
        &state,
        letters::commands::IssueClassLetter {
            tenant_id: auth.tenant_id,
            user_id: auth.user_id,
            run_id,
            homeroom_id,
            letter_number: body.letter_number,
            letter_date: body.letter_date,
            city: body.city,
        },
    )
    .await?;
    Ok(envelope(letter))
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run the Step 2 command. Expected: 7 PASS. Then regression `--exact execute_moves_every_student_and_publishes_events` and `cargo check --workspace`.

- [ ] **Step 8: Commit (backend repo)**

```bash
git add services/academic-ops-service/src/promotion services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): issue class promotion letters for executed runs"
```

---

### Task 4: Academic-ops — certificates (Surat Keterangan Lulus) and principal refresh

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/promotion/letters/repo.rs` (append)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/letters/commands.rs` (append)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/letters/queries.rs` (append)
- Modify: `apps/backend/services/academic-ops-service/src/promotion/http.rs` (routes + handlers)
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs` (append to the Plan 3e section)

**Interfaces:**
- Consumes: Task 3 helpers (`executed_run`, `check_number`, `snapshot_of`, `resolve_city`, `push_error`, `NO_PRINCIPAL`, `NUMBER_TAKEN`, `LetterSnapshot`, `executed_status_error`), test helpers `executed_letters_fixture`, `put_json`, `principal_token`, `seed_school_profile`, `class_letter_uri`.
- Produces (HTTP, used by Tasks 5–9):
  - `GET /promotion-runs/:run_id/certificates?student_id=` → `{ letterhead: KnownSchoolProfile|null, source_year_name: string|null, certificates: [Certificate] }`, `Certificate` = `{student_id, full_name, nis, nisn, birth_place, birth_date, last_homeroom_name, graduation_date, certificate_number, letter_date, city, school_name, principal_name, principal_nip, issued_at, updated_at}` (letter fields `null` until issued), ordered by `last_homeroom_name`, then `full_name`.
  - `PUT /promotion-runs/:run_id/certificates` body `{letter_date, city?, items:[{student_id, certificate_number}]}` → `{updated: n}`.
  - `POST /promotion-runs/:run_id/letters/refresh-principal` → `{updated: n}`.
- Error messages under `items` (all `student <id>: …`): `not a graduate of this run`, `listed more than once`, `certificate number is required`, `certificate number must be at most 64 characters`, `certificate number <n> is used twice in this request`, `certificate number <n> is already used by another letter`. Size: `items` → `must contain between 1 and 2000 items`. A 23505 race on the partial index → `items` → `a certificate number is already used by another letter`.

- [ ] **Step 1: Write the failing tests**

Append to the Plan 3e section of `tests/integration.rs`:

```rust
fn certificates_uri(run_id: uuid::Uuid) -> String {
    format!("/api/v1/academic-ops/promotion-runs/{run_id}/certificates")
}

/// Adds a second graduate in Final-A to an executed run by copying the
/// first graduate's decision and graduation record (execution itself is
/// already covered by Plan 3c tests).
async fn add_second_graduate(pool: &PgPool, ex: &ExecutionFixture) -> uuid::Uuid {
    let student_id = uuid::Uuid::new_v4();
    sqlx::query(
        "INSERT INTO student (student_id, tenant_id, nis, full_name, gender, birth_date, birth_place, nisn, status) \
         VALUES ($1, $2, $3, 'Ani Lulus', 'female', '2009-03-04', 'Sidoarjo', '0091234567', 'lulus')",
    )
    .bind(student_id)
    .bind(ex.fx.tenant_id)
    .bind(format!("G-{student_id}"))
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO promotion_decision \
           (decision_id, run_id, tenant_id, student_id, enrollment_id, academic_year_id, homeroom_id, \
            recommended, result, computed_metrics) \
         SELECT $1, run_id, tenant_id, $2, enrollment_id, academic_year_id, homeroom_id, \
                recommended, result, computed_metrics \
         FROM promotion_decision WHERE run_id = $3 AND student_id = $4",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(student_id)
    .bind(ex.run_id)
    .bind(ex.graduate_student)
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO graduation_record (graduation_id, tenant_id, student_id, academic_year_id, graduation_date) \
         SELECT $1, tenant_id, $2, academic_year_id, graduation_date FROM graduation_record WHERE student_id = $3",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(student_id)
    .bind(ex.graduate_student)
    .execute(pool)
    .await
    .unwrap();
    student_id
}

async fn certificate_row(pool: &PgPool, student_id: uuid::Uuid) -> (Option<String>, Option<String>, Option<chrono::DateTime<chrono::Utc>>) {
    sqlx::query_as("SELECT certificate_number, principal_name, issued_at FROM graduation_record WHERE student_id = $1")
        .bind(student_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn certificates_issue_with_snapshot_and_print_data() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let second = add_second_graduate(&pool, &ex).await;

    let (status, body) = put_json(
        app.clone(),
        &ex.admin_token,
        &certificates_uri(ex.run_id),
        json!({
            "letter_date": "2026-06-22",
            "items": [
                { "student_id": ex.graduate_student, "certificate_number": " 421.3/001/SKL/2026 " },
                { "student_id": second, "certificate_number": "421.3/002/SKL/2026" },
            ],
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["updated"], 2);

    let (status, body) = get_json(app.clone(), &principal_token(ex.fx.tenant_id), &certificates_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let p = &body["data"];
    assert_eq!(p["source_year_name"], "2025/2026");
    assert_eq!(p["letterhead"]["school_name"], "SMP Negeri 1");
    let certs = p["certificates"].as_array().unwrap();
    assert_eq!(certs.len(), 2);
    let ani = certs.iter().find(|c| c["student_id"] == second.to_string()).unwrap();
    assert_eq!(ani["certificate_number"], "421.3/002/SKL/2026");
    assert_eq!(ani["birth_place"], "Sidoarjo");
    assert_eq!(ani["birth_date"], "2009-03-04");
    assert_eq!(ani["nisn"], "0091234567");
    assert_eq!(ani["last_homeroom_name"], "Final-A");
    assert_eq!(ani["letter_date"], "2026-06-22");
    assert_eq!(ani["city"], "Surabaya");
    assert_eq!(ani["principal_name"], "Dra. Siti Rahayu");
    assert!(ani["graduation_date"].is_string());

    let (status, body) = get_json(
        app.clone(),
        &ex.admin_token,
        &format!("{}?student_id={second}", certificates_uri(ex.run_id)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["data"]["certificates"].as_array().unwrap().len(), 1);

    let (_, body) = get_json(app, &ex.admin_token, &letters_uri(ex.run_id)).await;
    assert_eq!(body["data"]["certificates"], json!({ "graduates": 2, "issued": 2 }));
}

#[tokio::test]
async fn certificate_correction_keeps_snapshot() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let uri = certificates_uri(ex.run_id);
    let item = |n: &str| json!({ "letter_date": "2026-06-22", "items": [{ "student_id": ex.graduate_student, "certificate_number": n }] });

    let (status, _) = put_json(app.clone(), &ex.admin_token, &uri, item("SKL/001")).await;
    assert_eq!(status, StatusCode::OK);
    let (_, _, issued_at) = certificate_row(&pool, ex.graduate_student).await;

    seed_school_profile(&pool, ex.fx.tenant_id, Some("Pak Baru"), Some("Surabaya")).await;
    let (status, body) = put_json(app, &ex.admin_token, &uri, item("SKL/009")).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    let (number, principal, issued_again) = certificate_row(&pool, ex.graduate_student).await;
    assert_eq!(number.as_deref(), Some("SKL/009"));
    assert_eq!(principal.as_deref(), Some("Dra. Siti Rahayu"), "a correction never re-snapshots");
    assert_eq!(issued_at, issued_again);
}

#[tokio::test]
async fn certificates_can_swap_numbers_in_one_request() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let second = add_second_graduate(&pool, &ex).await;
    let uri = certificates_uri(ex.run_id);

    let (status, _) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [
            { "student_id": ex.graduate_student, "certificate_number": "A" },
            { "student_id": second, "certificate_number": "B" },
        ]}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = put_json(
        app,
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [
            { "student_id": ex.graduate_student, "certificate_number": "B" },
            { "student_id": second, "certificate_number": "A" },
        ]}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(certificate_row(&pool, ex.graduate_student).await.0.as_deref(), Some("B"));
    assert_eq!(certificate_row(&pool, second).await.0.as_deref(), Some("A"));
}

#[tokio::test]
async fn certificates_reject_bad_items_all_or_nothing() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let second = add_second_graduate(&pool, &ex).await;
    let uri = certificates_uri(ex.run_id);

    // `second` already holds "TAKEN" from an earlier request.
    let (status, _) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [{ "student_id": second, "certificate_number": "TAKEN" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, body) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [
            { "student_id": ex.promote_student, "certificate_number": "X1" },
            { "student_id": ex.graduate_student, "certificate_number": "TAKEN" },
            { "student_id": ex.graduate_student, "certificate_number": "X2" },
        ]}),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    let items: Vec<String> = serde_json::from_value(body["error"]["fields"]["items"].clone()).unwrap();
    assert!(items.contains(&format!("student {}: not a graduate of this run", ex.promote_student)), "{items:?}");
    assert!(items.contains(&format!("student {}: listed more than once", ex.graduate_student)), "{items:?}");
    assert!(
        items.contains(&format!("student {}: certificate number TAKEN is already used by another letter", ex.graduate_student)),
        "{items:?}"
    );
    assert_eq!(certificate_row(&pool, ex.graduate_student).await.0, None, "nothing written");

    let (status, body) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [
            { "student_id": ex.graduate_student, "certificate_number": "DUP" },
            { "student_id": second, "certificate_number": "DUP" },
        ]}),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let items: Vec<String> = serde_json::from_value(body["error"]["fields"]["items"].clone()).unwrap();
    assert!(items.contains(&format!("student {second}: certificate number DUP is used twice in this request")), "{items:?}");

    let (status, body) = put_json(
        app.clone(),
        &ex.admin_token,
        &uri,
        json!({ "letter_date": "2026-06-22", "items": [{ "student_id": ex.graduate_student, "certificate_number": "  " }] }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(
        body["error"]["fields"]["items"][0],
        format!("student {}: certificate number is required", ex.graduate_student)
    );

    let (status, body) = put_json(app.clone(), &ex.admin_token, &uri, json!({ "letter_date": "2026-06-22", "items": [] })).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["fields"]["items"][0], "must contain between 1 and 2000 items");

    let too_many: Vec<Value> = (0..2001)
        .map(|i| json!({ "student_id": uuid::Uuid::new_v4(), "certificate_number": format!("N{i}") }))
        .collect();
    let (status, body) = put_json(app, &ex.admin_token, &uri, json!({ "letter_date": "2026-06-22", "items": too_many })).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["fields"]["items"][0], "must contain between 1 and 2000 items");
}

#[tokio::test]
async fn certificates_need_principal_for_first_issue() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    seed_school_profile(&pool, ex.fx.tenant_id, Some("  "), Some("Surabaya")).await;

    let (status, body) = put_json(
        app,
        &ex.admin_token,
        &certificates_uri(ex.run_id),
        json!({ "letter_date": "2026-06-22", "items": [{ "student_id": ex.graduate_student, "certificate_number": "SKL/1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert_eq!(body["error"]["fields"]["principal"][0], "school profile has no principal name");
}

#[tokio::test]
async fn refresh_principal_resnapshots_this_runs_letters_only() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let (status, _) = put_json(
        app.clone(),
        &ex.admin_token,
        &class_letter_uri(ex.run_id, ex.fx.mid_homeroom),
        json!({ "letter_number": "SK/1", "letter_date": "2026-06-20" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = put_json(
        app.clone(),
        &ex.admin_token,
        &certificates_uri(ex.run_id),
        json!({ "letter_date": "2026-06-22", "items": [{ "student_id": ex.graduate_student, "certificate_number": "SKL/1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // A letter of another run of the same tenant must stay untouched.
    let other_run = seed_promotion_run_with_status(&pool, ex.fx.tenant_id, ex.target_year_id, "executed").await;
    sqlx::query(
        "INSERT INTO promotion_class_letter (letter_id, tenant_id, run_id, homeroom_id, letter_number, letter_date, \
           city, school_name, principal_name, issued_by, issued_at, updated_by, updated_at) \
         VALUES ($1, $2, $3, $4, 'SK/OTHER', '2026-06-20', 'Surabaya', 'SMP Negeri 1', 'Lama', $5, NOW(), $5, NOW())",
    )
    .bind(uuid::Uuid::new_v4())
    .bind(ex.fx.tenant_id)
    .bind(other_run)
    .bind(ex.target_mid_homeroom)
    .bind(uuid::Uuid::new_v4())
    .execute(&pool)
    .await
    .unwrap();

    seed_school_profile(&pool, ex.fx.tenant_id, Some("Pak Baru"), Some("Surabaya")).await;
    let (status, body) = post_json_body(
        app.clone(),
        &ex.admin_token,
        &format!("/api/v1/academic-ops/promotion-runs/{}/letters/refresh-principal", ex.run_id),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["data"]["updated"], 2);

    let names: Vec<(uuid::Uuid, String)> =
        sqlx::query_as("SELECT run_id, principal_name FROM promotion_class_letter WHERE tenant_id = $1")
            .bind(ex.fx.tenant_id)
            .fetch_all(&pool)
            .await
            .unwrap();
    for (run, name) in names {
        if run == ex.run_id {
            assert_eq!(name, "Pak Baru");
        } else {
            assert_eq!(name, "Lama", "another run's letter must not change");
        }
    }
    assert_eq!(certificate_row(&pool, ex.graduate_student).await.1.as_deref(), Some("Pak Baru"));
}

#[tokio::test]
async fn principal_cannot_issue_certificates_or_refresh() {
    let (pool, state, _url, _pg, _rabbit) = boot().await;
    let (ex, app) = executed_letters_fixture(&pool, &state).await;
    let token = principal_token(ex.fx.tenant_id);

    let (status, _) = put_json(
        app.clone(),
        &token,
        &certificates_uri(ex.run_id),
        json!({ "letter_date": "2026-06-22", "items": [{ "student_id": ex.graduate_student, "certificate_number": "SKL/1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let resp = post_json(
        app.clone(),
        &token,
        &format!("/api/v1/academic-ops/promotion-runs/{}/letters/refresh-principal", ex.run_id),
        json!({}),
    )
    .await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    // Another tenant: 404 on every certificate endpoint.
    let tenant_b = uuid::Uuid::new_v4();
    seed_active_subscription(&pool, tenant_b).await;
    let (status, _) = get_json(app, &jwt_for(tenant_b), &certificates_uri(ex.run_id)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
```

`post_json` returns a raw `Response`; add this helper next to `certificates_uri` for the refresh test:

```rust
async fn post_json_body(app: axum::Router, token: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    let resp = post_json(app, token, uri, body).await;
    let status = resp.status();
    (status, body_to_json(resp).await)
}
```

`student.status` accepts `'lulus'` (Plan 3c V6 values) and `birth_place`/`nisn` exist (V6). If the INSERT in `add_second_graduate` fails on another NOT NULL column, add it with the same value `seed_promoted_student` uses and list it under Adaptations.

- [ ] **Step 2: Run the tests to verify they fail**

`cargo test -p academic-ops-service --test integration -- --test-threads=2 --exact certificates_issue_with_snapshot_and_print_data certificate_correction_keeps_snapshot certificates_can_swap_numbers_in_one_request certificates_reject_bad_items_all_or_nothing certificates_need_principal_for_first_issue refresh_principal_resnapshots_this_runs_letters_only principal_cannot_issue_certificates_or_refresh`

Expected: FAIL — `/certificates` and `/letters/refresh-principal` return 404/405 (`left: 405, right: 200`). `principal_cannot_issue_certificates_or_refresh` may fail on its last 404 assertion or pass the 403 lines vacuously (405 ≠ 403 → it fails at the first assertion; that is the expected RED).

- [ ] **Step 3: Repo**

Append to `src/promotion/letters/repo.rs`:

```rust
/// Graduates of the run with their record's current number.
pub struct RunGraduate {
    pub student_id: Uuid,
    pub certificate_number: Option<String>,
}

pub async fn run_graduates(conn: &mut PgConnection, tenant_id: Uuid, run_id: Uuid) -> sqlx::Result<Vec<RunGraduate>> {
    let rows: Vec<(Uuid, Option<String>)> = sqlx::query_as(
        "SELECT d.student_id, g.certificate_number \
         FROM promotion_decision d \
         JOIN graduation_record g ON g.tenant_id = d.tenant_id AND g.student_id = d.student_id \
                                 AND g.academic_year_id = d.academic_year_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.result = 'graduate'",
    )
    .bind(tenant_id)
    .bind(run_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(student_id, certificate_number)| RunGraduate { student_id, certificate_number })
        .collect())
}

/// Numbers among `numbers` already held by graduation records of the tenant
/// whose student is NOT in `exclude` (the request's own students may swap).
pub async fn certificate_numbers_held_elsewhere(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    numbers: &[String],
    exclude: &[Uuid],
) -> sqlx::Result<Vec<String>> {
    sqlx::query_scalar(
        "SELECT certificate_number FROM graduation_record \
         WHERE tenant_id = $1 AND certificate_number = ANY($2) AND NOT (student_id = ANY($3))",
    )
    .bind(tenant_id)
    .bind(numbers)
    .bind(exclude)
    .fetch_all(&mut *conn)
    .await
}

/// Frees the request's own numbers first so a swap does not hit the unique index.
pub async fn clear_certificate_numbers(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    students: &[Uuid],
) -> sqlx::Result<()> {
    sqlx::query(
        "UPDATE graduation_record SET certificate_number = NULL \
         WHERE tenant_id = $1 AND academic_year_id = $2 AND student_id = ANY($3)",
    )
    .bind(tenant_id)
    .bind(academic_year_id)
    .bind(students)
    .execute(&mut *conn)
    .await?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub async fn write_certificate(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    academic_year_id: Uuid,
    student_id: Uuid,
    number: &str,
    letter_date: NaiveDate,
    city: &str,
    first_issue: Option<&LetterSnapshot>,
    user_id: Uuid,
) -> sqlx::Result<u64> {
    let outcome = match first_issue {
        Some(s) => sqlx::query(
            "UPDATE graduation_record SET certificate_number = $4, letter_date = $5, city = $6, \
               school_name = $7, principal_name = $8, principal_nip = $9, \
               issued_by = $10, issued_at = NOW(), updated_by = $10, updated_at = NOW() \
             WHERE tenant_id = $1 AND academic_year_id = $2 AND student_id = $3",
        )
        .bind(tenant_id)
        .bind(academic_year_id)
        .bind(student_id)
        .bind(number)
        .bind(letter_date)
        .bind(city)
        .bind(&s.school_name)
        .bind(&s.principal_name)
        .bind(&s.principal_nip)
        .bind(user_id)
        .execute(&mut *conn)
        .await?,
        None => sqlx::query(
            "UPDATE graduation_record SET certificate_number = $4, letter_date = $5, city = $6, \
               updated_by = $7, updated_at = NOW() \
             WHERE tenant_id = $1 AND academic_year_id = $2 AND student_id = $3",
        )
        .bind(tenant_id)
        .bind(academic_year_id)
        .bind(student_id)
        .bind(number)
        .bind(letter_date)
        .bind(city)
        .bind(user_id)
        .execute(&mut *conn)
        .await?,
    };
    Ok(outcome.rows_affected())
}

/// Re-snapshots every issued letter of the run (class letters and
/// certificates). Returns the number of letters updated.
pub async fn refresh_snapshots(
    conn: &mut PgConnection,
    tenant_id: Uuid,
    run_id: Uuid,
    academic_year_id: Uuid,
    s: &LetterSnapshot,
    user_id: Uuid,
) -> sqlx::Result<u64> {
    let class = sqlx::query(
        "UPDATE promotion_class_letter SET school_name = $3, principal_name = $4, principal_nip = $5, \
           updated_by = $6, updated_at = NOW() \
         WHERE tenant_id = $1 AND run_id = $2",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(&s.school_name)
    .bind(&s.principal_name)
    .bind(&s.principal_nip)
    .bind(user_id)
    .execute(&mut *conn)
    .await?;
    let certs = sqlx::query(
        "UPDATE graduation_record g SET school_name = $4, principal_name = $5, principal_nip = $6, \
           updated_by = $7, updated_at = NOW() \
         WHERE g.tenant_id = $1 AND g.academic_year_id = $3 AND g.certificate_number IS NOT NULL \
           AND g.student_id IN (SELECT d.student_id FROM promotion_decision d \
                                WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.result = 'graduate')",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(academic_year_id)
    .bind(&s.school_name)
    .bind(&s.principal_name)
    .bind(&s.principal_nip)
    .bind(user_id)
    .execute(&mut *conn)
    .await?;
    Ok(class.rows_affected() + certs.rows_affected())
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Certificate {
    pub student_id: Uuid,
    pub full_name: Option<String>,
    pub nis: Option<String>,
    pub nisn: Option<String>,
    pub birth_place: Option<String>,
    pub birth_date: Option<NaiveDate>,
    pub last_homeroom_name: Option<String>,
    pub graduation_date: NaiveDate,
    pub certificate_number: Option<String>,
    pub letter_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub school_name: Option<String>,
    pub principal_name: Option<String>,
    pub principal_nip: Option<String>,
    pub issued_at: Option<DateTime<Utc>>,
    pub updated_at: Option<DateTime<Utc>>,
}

pub async fn certificates(
    pool: &PgPool,
    tenant_id: Uuid,
    run_id: Uuid,
    student_id: Option<Uuid>,
) -> sqlx::Result<Vec<Certificate>> {
    sqlx::query_as(
        "SELECT d.student_id, s.full_name, s.nis, s.nisn, s.birth_place, s.birth_date, \
                h.name AS last_homeroom_name, g.graduation_date, g.certificate_number, g.letter_date, \
                g.city, g.school_name, g.principal_name, g.principal_nip, g.issued_at, g.updated_at \
         FROM promotion_decision d \
         JOIN graduation_record g ON g.tenant_id = d.tenant_id AND g.student_id = d.student_id \
                                 AND g.academic_year_id = d.academic_year_id \
         LEFT JOIN student s ON s.tenant_id = d.tenant_id AND s.student_id = d.student_id \
         LEFT JOIN homeroom h ON h.tenant_id = d.tenant_id AND h.homeroom_id = d.homeroom_id \
         WHERE d.tenant_id = $1 AND d.run_id = $2 AND d.result = 'graduate' \
           AND ($3::uuid IS NULL OR d.student_id = $3) \
         ORDER BY h.name NULLS LAST, s.full_name NULLS LAST, d.student_id",
    )
    .bind(tenant_id)
    .bind(run_id)
    .bind(student_id)
    .fetch_all(pool)
    .await
}
```

- [ ] **Step 4: Commands**

Append to `src/promotion/letters/commands.rs` (add `use std::collections::{HashMap, HashSet};` and `use serde::Serialize;` to the imports):

```rust
pub const MAX_CERTIFICATES: usize = 2000;

pub struct CertificateItem {
    pub student_id: Uuid,
    pub certificate_number: String,
}

pub struct IssueCertificates {
    pub tenant_id: Uuid,
    pub user_id: Uuid,
    pub run_id: Uuid,
    pub letter_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub items: Vec<CertificateItem>,
}

#[derive(Serialize)]
pub struct UpdatedOutcome {
    pub updated: u64,
}

fn map_certificate_error(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(db) = &err {
        if db.constraint() == Some("graduation_record_certificate_number_uidx") {
            return AppError::validation_error_single(
                "items",
                "a certificate number is already used by another letter",
            );
        }
    }
    AppError::internal(err)
}

/// Issues or corrects graduation certificate numbers, all-or-nothing (spec
/// §3.2). Numbers held by the request's own students do not conflict: the
/// batch clears its own numbers first, so two graduates can swap.
pub async fn issue_certificates(state: &AppState, input: IssueCertificates) -> Result<UpdatedOutcome, AppError> {
    let mut errors = BTreeMap::new();
    if input.items.is_empty() || input.items.len() > MAX_CERTIFICATES {
        return Err(AppError::validation_error_single("items", "must contain between 1 and 2000 items"));
    }
    if input.letter_date.is_none() {
        push_error(&mut errors, "letter_date", "is required");
    }

    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let run = crate::promotion::repo::lock_run_row(&mut tx, input.tenant_id, input.run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "executed" {
        return Err(executed_status_error());
    }

    let graduates: HashMap<Uuid, Option<String>> = repo::run_graduates(&mut tx, input.tenant_id, input.run_id)
        .await
        .map_err(AppError::internal)?
        .into_iter()
        .map(|g| (g.student_id, g.certificate_number))
        .collect();

    let mut seen_students = HashSet::new();
    let mut seen_numbers: HashMap<String, Uuid> = HashMap::new();
    let mut accepted: Vec<(Uuid, String)> = Vec::new();
    for item in &input.items {
        let sid = item.student_id;
        if !graduates.contains_key(&sid) {
            push_error(&mut errors, "items", format!("student {sid}: not a graduate of this run"));
            continue;
        }
        if !seen_students.insert(sid) {
            push_error(&mut errors, "items", format!("student {sid}: listed more than once"));
            continue;
        }
        let number = match check_number(&item.certificate_number) {
            Ok(n) => n,
            Err(message) => {
                push_error(&mut errors, "items", format!("student {sid}: certificate number {message}"));
                continue;
            }
        };
        if seen_numbers.insert(number.clone(), sid).is_some() {
            push_error(&mut errors, "items", format!("student {sid}: certificate number {number} is used twice in this request"));
            continue;
        }
        accepted.push((sid, number));
    }

    let own: Vec<Uuid> = accepted.iter().map(|(sid, _)| *sid).collect();
    let numbers: Vec<String> = accepted.iter().map(|(_, n)| n.clone()).collect();
    let held: HashSet<String> = repo::certificate_numbers_held_elsewhere(&mut tx, input.tenant_id, &numbers, &own)
        .await
        .map_err(AppError::internal)?
        .into_iter()
        .collect();
    for (sid, number) in &accepted {
        if held.contains(number) {
            push_error(&mut errors, "items", format!("student {sid}: certificate number {number} {NUMBER_TAKEN}"));
        }
    }

    let profile = KnownSchoolProfileRepo::find(&mut *tx, input.tenant_id)
        .await
        .map_err(AppError::internal)?;
    let city = resolve_city(input.city.as_deref(), profile.as_ref());
    if city.is_none() {
        push_error(&mut errors, "city", "is required");
    }
    let needs_snapshot = accepted.iter().any(|(sid, _)| graduates.get(sid).map_or(false, |n| n.is_none()));
    let snapshot = snapshot_of(profile.as_ref());
    if needs_snapshot && snapshot.is_none() {
        push_error(&mut errors, "principal", NO_PRINCIPAL);
    }
    if !errors.is_empty() {
        return Err(AppError::validation_error(errors));
    }
    let (Some(letter_date), Some(city)) = (input.letter_date, city) else {
        return Err(AppError::validation_error(errors));
    };

    repo::clear_certificate_numbers(&mut tx, input.tenant_id, run.academic_year_id, &own)
        .await
        .map_err(AppError::internal)?;
    let mut updated = 0;
    for (sid, number) in &accepted {
        let first_issue = graduates.get(sid).map_or(false, |n| n.is_none());
        updated += repo::write_certificate(
            &mut tx,
            input.tenant_id,
            run.academic_year_id,
            *sid,
            number,
            letter_date,
            &city,
            if first_issue { snapshot.as_ref() } else { None },
            input.user_id,
        )
        .await
        .map_err(map_certificate_error)?;
    }
    tx.commit().await.map_err(AppError::internal)?;
    Ok(UpdatedOutcome { updated })
}

/// Re-snapshots school and principal on every issued letter of the run
/// (spec §3.2, Q4: only on explicit request).
pub async fn refresh_principal(
    state: &AppState,
    tenant_id: Uuid,
    user_id: Uuid,
    run_id: Uuid,
) -> Result<UpdatedOutcome, AppError> {
    let mut tx = state.pool.begin().await.map_err(AppError::internal)?;
    let run = crate::promotion::repo::lock_run_row(&mut tx, tenant_id, run_id)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("promotion run"))?;
    if run.status != "executed" {
        return Err(executed_status_error());
    }
    let profile = KnownSchoolProfileRepo::find(&mut *tx, tenant_id)
        .await
        .map_err(AppError::internal)?;
    let snapshot = snapshot_of(profile.as_ref())
        .ok_or_else(|| AppError::validation_error_single("principal", NO_PRINCIPAL))?;
    let updated = repo::refresh_snapshots(&mut tx, tenant_id, run_id, run.academic_year_id, &snapshot, user_id)
        .await
        .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(UpdatedOutcome { updated })
}
```

- [ ] **Step 5: Queries**

Append to `src/promotion/letters/queries.rs` (import `Certificate` from `repo`):

```rust
#[derive(Serialize)]
pub struct CertificatesPrint {
    pub letterhead: Option<KnownSchoolProfile>,
    pub source_year_name: Option<String>,
    pub certificates: Vec<repo::Certificate>,
}

pub async fn certificates_print(
    state: &AppState,
    tenant_id: Uuid,
    run_id: Uuid,
    student_id: Option<Uuid>,
) -> Result<CertificatesPrint, AppError> {
    let run = executed_run(state, tenant_id, run_id).await?;
    let letterhead = KnownSchoolProfileRepo::find(&state.pool, tenant_id)
        .await
        .map_err(AppError::internal)?;
    let source_year_name = repo::year_name(&state.pool, tenant_id, run.academic_year_id)
        .await
        .map_err(AppError::internal)?;
    let certificates = repo::certificates(&state.pool, tenant_id, run_id, student_id)
        .await
        .map_err(AppError::internal)?;
    Ok(CertificatesPrint { letterhead, source_year_name, certificates })
}
```

- [ ] **Step 6: HTTP**

Routes in `routes()`:

```rust
        .route(
            "/api/v1/academic-ops/promotion-runs/:run_id/certificates",
            axum::routing::get(get_certificates).put(put_certificates),
        )
        .route(
            "/api/v1/academic-ops/promotion-runs/:run_id/letters/refresh-principal",
            post(refresh_letters_principal),
        )
```

Handlers:

```rust
#[derive(Debug, Deserialize)]
struct CertificatesQuery {
    student_id: Option<Uuid>,
}

async fn get_certificates(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path(run_id): Path<Uuid>,
    Query(query): Query<CertificatesQuery>,
) -> Result<Json<Value>, AppError> {
    require_read_permission(&auth)?;
    let print = letters::queries::certificates_print(&state, auth.tenant_id, run_id, query.student_id).await?;
    Ok(envelope(print))
}

#[derive(Debug, Deserialize)]
struct CertificateItemBody {
    student_id: Uuid,
    #[serde(default)]
    certificate_number: String,
}

#[derive(Debug, Deserialize)]
struct CertificatesBody {
    letter_date: Option<NaiveDate>,
    city: Option<String>,
    #[serde(default)]
    items: Vec<CertificateItemBody>,
}

async fn put_certificates(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path(run_id): Path<Uuid>,
    Json(body): Json<CertificatesBody>,
) -> Result<Json<Value>, AppError> {
    auth.require_permission(PERM_PROMOTION_MANAGE)?;
    let outcome = letters::commands::issue_certificates(
        &state,
        letters::commands::IssueCertificates {
            tenant_id: auth.tenant_id,
            user_id: auth.user_id,
            run_id,
            letter_date: body.letter_date,
            city: body.city,
            items: body
                .items
                .into_iter()
                .map(|i| letters::commands::CertificateItem {
                    student_id: i.student_id,
                    certificate_number: i.certificate_number,
                })
                .collect(),
        },
    )
    .await?;
    Ok(envelope(outcome))
}

async fn refresh_letters_principal(
    State(state): State<AppState>,
    auth: AuthContext,
    _feature: AcademicOpsEntitlement,
    Path(run_id): Path<Uuid>,
) -> Result<Json<Value>, AppError> {
    auth.require_permission(PERM_PROMOTION_MANAGE)?;
    let outcome = letters::commands::refresh_principal(&state, auth.tenant_id, auth.user_id, run_id).await?;
    Ok(envelope(outcome))
}
```

Note the size check runs before the run lookup, so a 2,001-item body for any run id is a 400 — that is intended (cheap rejection first, same as `assign_targets`).

- [ ] **Step 7: Run the tests to verify they pass**

Run the Step 2 command: 7 PASS. Re-run Task 3's seven tests (`class_letter_first_issue_snapshots_principal … letters_summary_and_class_letter_print_data`) as regression, then `cargo check --workspace`.

- [ ] **Step 8: Commit (backend repo)**

```bash
git add services/academic-ops-service/src/promotion services/academic-ops-service/tests/integration.rs
git commit -m "feat(academic-ops): issue graduation certificates and refresh letter signatories"
```

---

### Task 5: Web — letters data layer, school-profile principal fields

**Files:**
- Create: `apps/web/src/lib/query/queries/use-promotion-letters.ts`
- Create: `apps/web/src/lib/query/mutations/use-promotion-letters.ts`
- Create: `apps/web/src/lib/schemas/promotion-letters.ts`
- Create: `apps/web/src/lib/schemas/promotion-letters.test.ts`
- Modify: `apps/web/src/lib/errors/messages.ts` (`PROMOTION_FIELD_LABELS` ~117)
- Modify: `apps/web/src/lib/errors/promotion-messages.test.ts` (one new case)
- Modify: `apps/web/src/lib/schemas/academic-ops.ts` (`schoolProfileSchema` ~105)
- Modify: `apps/web/src/lib/query/queries/use-school-profile.ts` (`SchoolProfile` type)
- Modify: `apps/web/src/app/settings/school-profile/page.tsx` (`SchoolProfileView` ~294, `SchoolProfileForm` ~332)
- Test: `apps/web/src/lib/schemas/academic-ops.test.ts` (one new case)

**Interfaces:**
- Consumes: Task 3/4 endpoints; `PROMOTION_QUERY_KEY` from `@/lib/query/queries/use-promotion`.
- Produces types (`use-promotion-letters.ts`): `Letterhead`, `ClassLetter`, `LettersSummary`, `ClassLetterSummary`, `ClassLetterPrint`, `ClassLetterStudent`, `Certificate`, `CertificatesPrint` (shapes exactly as the backend JSON in Tasks 3–4; dates as `string`, nullable fields as `| null`).
- Produces hooks: `usePromotionLetters(runId?: string)`, `useClassLetterPrint(runId?: string, homeroomId?: string)`, `useCertificatesPrint(runId?: string, studentId?: string)`; mutations `useIssueClassLetter(runId)` (`mutateAsync({homeroomId, letter_number, letter_date, city})`), `useIssueCertificates(runId)` (`mutateAsync({letter_date, city, items})`), `useRefreshLetterPrincipal(runId)` (`mutateAsync()`). Every mutation invalidates `PROMOTION_QUERY_KEY` on settled.
- Produces schemas: `classLetterSchema` / `ClassLetterForm` `{letter_number, letter_date, city}`; `numberPatternSchema` / `NumberPatternForm` `{pattern, start, digits, letter_date, city, overwrite}`; `toCityPayload(city: string): string | null`.
- Produces copy: field labels `letter_number` "Nomor SK", `certificate_number` "Nomor surat", `letter_date` "Tanggal surat", `city` "Kota", `principal` "Kepala sekolah", `items` "Daftar lulusan"; `PRINCIPAL_MISSING_MESSAGE`.
- `SchoolProfile` gains `principal_name?: string | null; principal_nip?: string | null`.

- [ ] **Step 1: Write the failing tests**

`src/lib/schemas/promotion-letters.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import { classLetterSchema, numberPatternSchema, toCityPayload } from "@/lib/schemas/promotion-letters";

describe("classLetterSchema", () => {
  it("needs a number and a date; city may be blank", () => {
    expect(classLetterSchema.safeParse({ letter_number: "421/001", letter_date: "2026-06-20", city: "" }).success).toBe(true);
    const r = classLetterSchema.safeParse({ letter_number: "  ", letter_date: "", city: "" });
    expect(r.success).toBe(false);
    if (!r.success) {
      const f = r.error.flatten().fieldErrors;
      expect(f.letter_number?.[0]).toBe("Nomor SK wajib diisi");
      expect(f.letter_date?.[0]).toBe("Tanggal surat wajib diisi");
    }
  });

  it("caps the number at 64 characters", () => {
    const r = classLetterSchema.safeParse({ letter_number: "x".repeat(65), letter_date: "2026-06-20", city: "" });
    expect(r.success).toBe(false);
  });
});

describe("numberPatternSchema", () => {
  const ok = { pattern: "421.3/{n}/SKL/2026", start: "1", digits: "3", letter_date: "2026-06-22", city: "", overwrite: false };

  it("accepts a pattern with {n}", () => {
    expect(numberPatternSchema.safeParse(ok).success).toBe(true);
  });

  it("requires {n}, a positive start and 1–6 digits", () => {
    const r = numberPatternSchema.safeParse({ ...ok, pattern: "421.3/SKL", start: "0", digits: "9" });
    expect(r.success).toBe(false);
    if (!r.success) {
      const f = r.error.flatten().fieldErrors;
      expect(f.pattern?.[0]).toBe("Pola harus memuat {n}");
      expect(f.start?.[0]).toBe("Isi bilangan bulat 1 atau lebih");
      expect(f.digits?.[0]).toBe("Isi 1 sampai 6");
    }
  });
});

describe("toCityPayload", () => {
  it("sends null for a blank city so the server uses the profile's city", () => {
    expect(toCityPayload("  ")).toBeNull();
    expect(toCityPayload(" Sidoarjo ")).toBe("Sidoarjo");
  });
});
```

In `src/lib/errors/promotion-messages.test.ts`, add inside the existing `describe`:

```ts
  it("labels the letter fields", () => {
    const error = new ApiHttpError(400, {
      code: "VALIDATION_ERROR",
      message: "invalid",
      fields: { principal: ["school profile has no principal name"], letter_number: ["is already used by another letter"] },
    });
    expect(promotionFieldGroups(error).map((g) => g.label)).toEqual(["Nomor SK", "Kepala sekolah"]);
  });
```

In `src/lib/schemas/academic-ops.test.ts`, change the import to `import { homeroomSchema, schoolProfileSchema } from "@/lib/schemas/academic-ops";` and add:

```ts
describe("schoolProfileSchema principal", () => {
  it("accepts the principal fields and caps their length", () => {
    expect(schoolProfileSchema.safeParse({ school_name: "SMP 1", principal_name: "Dra. Siti", principal_nip: "" }).success).toBe(true);
    const r = schoolProfileSchema.safeParse({ school_name: "SMP 1", principal_name: "a".repeat(201), principal_nip: "1".repeat(65) });
    expect(r.success).toBe(false);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

`pnpm vitest run src/lib/schemas/promotion-letters.test.ts src/lib/errors/promotion-messages.test.ts src/lib/schemas/academic-ops.test.ts`

Expected: `promotion-letters.test.ts` fails to resolve `@/lib/schemas/promotion-letters` (named RED for a new module); the labels case fails with `expected [ 'principal', 'letter_number' ] to deeply equal [ 'Nomor SK', 'Kepala sekolah' ]` (unknown keys keep their raw name); the principal-length case fails because zod strips unknown keys and returns success. Record each.

- [ ] **Step 3: Schemas**

`src/lib/schemas/promotion-letters.ts`:

```ts
import { z } from "zod";

const number64 = (required: string) =>
  z.string().trim().min(1, required).max(64, "Maksimal 64 karakter");

/** SK Kenaikan Kelas dialog; keys match the backend so field errors map. */
export const classLetterSchema = z.object({
  letter_number: number64("Nomor SK wajib diisi"),
  letter_date: z.string().min(1, "Tanggal surat wajib diisi"),
  city: z.string().trim().max(200, "Maksimal 200 karakter"),
});
export type ClassLetterForm = z.infer<typeof classLetterSchema>;

function isPositiveInt(value: string) {
  const n = Number(value);
  return value.trim() !== "" && Number.isInteger(n) && n >= 1;
}

function isDigits(value: string) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= 6;
}

/** "Isi nomor dari pola" dialog (spec §4.1). */
export const numberPatternSchema = z.object({
  pattern: z
    .string()
    .trim()
    .min(1, "Pola wajib diisi")
    .refine((p) => p.includes("{n}"), "Pola harus memuat {n}"),
  start: z.string().refine(isPositiveInt, "Isi bilangan bulat 1 atau lebih"),
  digits: z.string().refine(isDigits, "Isi 1 sampai 6"),
  letter_date: z.string().min(1, "Tanggal surat wajib diisi"),
  city: z.string().trim().max(200, "Maksimal 200 karakter"),
  overwrite: z.boolean(),
});
export type NumberPatternForm = z.infer<typeof numberPatternSchema>;

/** Blank city → null: the server then uses the school profile's city. */
export function toCityPayload(city: string): string | null {
  const trimmed = city.trim();
  return trimmed === "" ? null : trimmed;
}
```

In `src/lib/schemas/academic-ops.ts`, add to `schoolProfileSchema` after `postal_code`:

```ts
  principal_name: z.string().max(200, "Maksimal 200 karakter").optional().or(z.literal("")),
  principal_nip: z.string().max(64, "Maksimal 64 karakter").optional().or(z.literal("")),
```

- [ ] **Step 4: Error copy**

In `src/lib/errors/messages.ts`, append to `PROMOTION_FIELD_LABELS` (after `['assignments', 'Penempatan']`):

```ts
  ['letter_number', 'Nomor SK'],
  ['certificate_number', 'Nomor surat'],
  ['letter_date', 'Tanggal surat'],
  ['city', 'Kota'],
  ['principal', 'Kepala sekolah'],
  ['items', 'Daftar lulusan'],
```

and after `promotionFieldGroups`:

```ts
/** Shown when the school profile has no principal name (letters spec §2.5). */
export const PRINCIPAL_MISSING_MESSAGE =
  'Nama kepala sekolah belum diisi di Profil Sekolah. Lengkapi dulu sebelum menerbitkan surat.';

/** Backend number-conflict message → Indonesian, per field or row. */
export function letterNumberMessage(message: string): string {
  if (message.includes('already used by another letter')) return 'Nomor sudah dipakai surat lain';
  if (message.includes('used twice in this request')) return 'Nomor dipakai dua kali';
  if (message.includes('not a graduate of this run')) return 'Bukan lulusan evaluasi ini';
  if (message.includes('is required')) return 'Nomor wajib diisi';
  if (message.includes('at most 64 characters')) return 'Maksimal 64 karakter';
  return message;
}
```

- [ ] **Step 5: Queries and mutations**

`src/lib/query/queries/use-promotion-letters.ts`:

```ts
"use client";

import { useQuery } from "@tanstack/react-query";

import { apiFetch } from "@/lib/api/client";
import { PROMOTION_QUERY_KEY, type PromotionCounts, type PromotionResult } from "@/lib/query/queries/use-promotion";

const BASE = "/api/v1/academic-ops/promotion-runs";

export type Letterhead = {
  tenant_id: string;
  school_name: string;
  npsn: string | null;
  principal_name: string | null;
  principal_nip: string | null;
  address_line: string | null;
  village: string | null;
  subdistrict: string | null;
  city_regency: string | null;
  province: string | null;
  postal_code: string | null;
  phone_number: string | null;
  email: string | null;
  logo_url: string | null;
  updated_at: string;
};

export type ClassLetter = {
  homeroom_id: string;
  letter_number: string;
  letter_date: string;
  city: string;
  school_name: string;
  principal_name: string;
  principal_nip: string | null;
  issued_by: string;
  issued_at: string;
  updated_by: string;
  updated_at: string;
};

export type ClassLetterSummary = {
  homeroom_id: string;
  homeroom_name: string | null;
  counts: PromotionCounts;
  letter: ClassLetter | null;
};

export type LettersSummary = {
  school_profile: Letterhead | null;
  class_letters: ClassLetterSummary[];
  certificates: { graduates: number; issued: number };
};

export type ClassLetterStudent = {
  student_id: string;
  full_name: string | null;
  nis: string | null;
  nisn: string | null;
  result: PromotionResult;
  target_homeroom_name: string | null;
};

export type ClassLetterPrint = {
  letterhead: Letterhead | null;
  source_year_name: string | null;
  target_year_name: string | null;
  homeroom_id: string;
  homeroom_name: string | null;
  letter: ClassLetter | null;
  students: ClassLetterStudent[];
};

export type Certificate = {
  student_id: string;
  full_name: string | null;
  nis: string | null;
  nisn: string | null;
  birth_place: string | null;
  birth_date: string | null;
  last_homeroom_name: string | null;
  graduation_date: string;
  certificate_number: string | null;
  letter_date: string | null;
  city: string | null;
  school_name: string | null;
  principal_name: string | null;
  principal_nip: string | null;
  issued_at: string | null;
  updated_at: string | null;
};

export type CertificatesPrint = {
  letterhead: Letterhead | null;
  source_year_name: string | null;
  certificates: Certificate[];
};

export function usePromotionLetters(runId?: string) {
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "letters", runId],
    queryFn: () => apiFetch<LettersSummary>({ service: "academic-ops", path: `${BASE}/${runId}/letters`, authenticated: true }),
    enabled: Boolean(runId),
  });
}

export function useClassLetterPrint(runId?: string, homeroomId?: string) {
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "class-letter", runId, homeroomId],
    queryFn: () =>
      apiFetch<ClassLetterPrint>({
        service: "academic-ops",
        path: `${BASE}/${runId}/class-letters/${homeroomId}`,
        authenticated: true,
      }),
    enabled: Boolean(runId && homeroomId),
  });
}

export function useCertificatesPrint(runId?: string, studentId?: string) {
  const query = studentId ? `?student_id=${encodeURIComponent(studentId)}` : "";
  return useQuery({
    queryKey: [...PROMOTION_QUERY_KEY, "certificates", runId, studentId ?? null],
    queryFn: () =>
      apiFetch<CertificatesPrint>({
        service: "academic-ops",
        path: `${BASE}/${runId}/certificates${query}`,
        authenticated: true,
      }),
    enabled: Boolean(runId),
  });
}
```

`src/lib/query/mutations/use-promotion-letters.ts`:

```ts
"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";

import { apiFetch } from "@/lib/api/client";
import { PROMOTION_QUERY_KEY } from "@/lib/query/queries/use-promotion";
import type { ClassLetter } from "@/lib/query/queries/use-promotion-letters";

const BASE = "/api/v1/academic-ops/promotion-runs";

function useSettle() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: PROMOTION_QUERY_KEY });
}

export function useIssueClassLetter(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: ({
      homeroomId,
      ...body
    }: {
      homeroomId: string;
      letter_number: string;
      letter_date: string;
      city: string | null;
    }) =>
      apiFetch<ClassLetter>({
        service: "academic-ops",
        path: `${BASE}/${runId}/class-letters/${homeroomId}`,
        method: "PUT",
        authenticated: true,
        body,
      }),
    onSettled: settle,
  });
}

export type CertificateItem = { student_id: string; certificate_number: string };

export function useIssueCertificates(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: (body: { letter_date: string; city: string | null; items: CertificateItem[] }) =>
      apiFetch<{ updated: number }>({
        service: "academic-ops",
        path: `${BASE}/${runId}/certificates`,
        method: "PUT",
        authenticated: true,
        body,
      }),
    onSettled: settle,
  });
}

export function useRefreshLetterPrincipal(runId: string) {
  const settle = useSettle();
  return useMutation({
    mutationFn: () =>
      apiFetch<{ updated: number }>({
        service: "academic-ops",
        path: `${BASE}/${runId}/letters/refresh-principal`,
        method: "POST",
        authenticated: true,
      }),
    onSettled: settle,
  });
}
```

If `PromotionCounts` or `PromotionResult` are not exported from `use-promotion.ts` under those names, use the exported names and list the adaptation.

- [ ] **Step 6: School profile page**

In `src/lib/query/queries/use-school-profile.ts`, add to `SchoolProfile`: `principal_name?: string | null;` and `principal_nip?: string | null;`.

In `src/app/settings/school-profile/page.tsx`:
- `SchoolProfileView`: add a section after "Identitas Sekolah":

```tsx
      <div className="space-y-4">
        <h3 className="text-sm font-semibold text-foreground">Kepala Sekolah</h3>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <ViewField label="Nama Kepala Sekolah" value={profile.principal_name} />
          <ViewField label="NIP" value={profile.principal_nip} />
        </div>
      </div>
```

- `SchoolProfileForm` `defaultValues`: add `principal_name: profile.principal_name ?? "",` and `principal_nip: profile.principal_nip ?? "",`.
- In the form, after the "Identitas Sekolah" block's closing `</div>`, add:

```tsx
        <div className="space-y-4">
          <h3 className="text-sm font-semibold text-foreground">Kepala Sekolah</h3>
          <p className="text-xs text-muted-foreground">
            Dipakai sebagai penanda tangan SK Kenaikan Kelas dan Surat Keterangan Lulus.
          </p>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <FormField
              control={form.control}
              name="principal_name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Nama Kepala Sekolah</FormLabel>
                  <FormControl>
                    <Input {...field} placeholder="Dra. Siti Rahayu, M.Pd." />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="principal_nip"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>NIP</FormLabel>
                  <FormControl>
                    <Input {...field} placeholder="Kosongkan jika tidak ada" />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>
        </div>
```

The PATCH already sends the whole form; empty strings for the two new keys become `null` on the server (Task 1 trims blank to cleared).

- [ ] **Step 7: Run the tests to verify they pass**

`pnpm vitest run src/lib/schemas/promotion-letters.test.ts src/lib/errors/promotion-messages.test.ts src/lib/schemas/academic-ops.test.ts`, then `pnpm typecheck` and `pnpm lint` (no new errors in touched files). Expected: PASS.

- [ ] **Step 8: Commit (web repo)**

```bash
git add src/lib/query/queries/use-promotion-letters.ts src/lib/query/mutations/use-promotion-letters.ts src/lib/schemas/promotion-letters.ts src/lib/schemas/promotion-letters.test.ts src/lib/errors/messages.ts src/lib/errors/promotion-messages.test.ts src/lib/schemas/academic-ops.ts src/lib/schemas/academic-ops.test.ts src/lib/query/queries/use-school-profile.ts src/app/settings/school-profile/page.tsx
git commit -m "feat(web): add the letters data layer and principal fields on the school profile"
```

---

### Task 6: Web — pure certificate numbering module

**Files:**
- Create: `apps/web/src/lib/promotion/letters.ts`
- Create: `apps/web/src/lib/promotion/letters.test.ts`

**Interfaces:**
- Consumes: `Certificate` type (Task 5).
- Produces (used by Task 8):
  - `type CertificateDraft = Record<string, string>` — student_id → number as typed (only edited rows are present).
  - `orderGraduates(rows: Certificate[]): Certificate[]` — by `last_homeroom_name` then `full_name` (Indonesian locale), then `student_id`.
  - `formatNumber(pattern: string, n: number, digits: number): string` — replaces every `{n}` with `n` left-padded with zeros to `digits`.
  - `buildCertificateNumbers(rows: Certificate[], draft: CertificateDraft, opts: { pattern: string; start: number; digits: number; overwrite: boolean }): CertificateDraft` — walks `orderGraduates(rows)`; a row whose effective number (draft, else saved) is non-blank is skipped unless `overwrite`; every filled or overwritten row consumes the next counter value; skipped rows do not.
  - `effectiveNumber(row: Certificate, draft: CertificateDraft): string`.
  - `duplicateNumbers(rows: Certificate[], draft: CertificateDraft): Set<string>` — student_ids whose trimmed effective number is non-blank and shared with another row.
  - `certificateChanges(rows: Certificate[], draft: CertificateDraft): { student_id: string; certificate_number: string }[]` — rows in the draft whose trimmed value differs from the saved number (blank drafts are included so the server reports them).
  - `mapStudentErrors(messages: string[], knownIds: ReadonlySet<string>): { byStudent: Record<string, string[]>; unmatched: string[] }` — `student <uuid>: <text>` lines go to that student when known; everything else is unmatched.
  - `formatLetterDate(value: string | null | undefined): string` — `"2026-06-20"` → `"20 Juni 2026"`, parsed as a local calendar date (used by Tasks 7, 8, 9). Not `formatDate` from `date-utils`: that parses a DATE string as UTC midnight, so west of UTC it shows the previous day — wrong on an official letter.

- [ ] **Step 1: Write the failing tests**

`src/lib/promotion/letters.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import type { Certificate } from "@/lib/query/queries/use-promotion-letters";
import {
  buildCertificateNumbers,
  certificateChanges,
  duplicateNumbers,
  effectiveNumber,
  formatLetterDate,
  formatNumber,
  mapStudentErrors,
  orderGraduates,
} from "@/lib/promotion/letters";

const A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

function cert(student_id: string, full_name: string, homeroom: string, certificate_number: string | null = null): Certificate {
  return {
    student_id,
    full_name,
    nis: null,
    nisn: null,
    birth_place: null,
    birth_date: null,
    last_homeroom_name: homeroom,
    graduation_date: "2026-06-15",
    certificate_number,
    letter_date: null,
    city: null,
    school_name: null,
    principal_name: null,
    principal_nip: null,
    issued_at: null,
    updated_at: null,
  };
}

const rows = [cert(C, "Citra", "IX-B"), cert(A, "Budi", "IX-A"), cert(B, "Ani", "IX-A")];
const opts = { pattern: "421.3/{n}/SKL/2026", start: 1, digits: 3, overwrite: false };

describe("formatNumber", () => {
  it("pads and replaces every {n}", () => {
    expect(formatNumber("421.3/{n}/SKL", 7, 3)).toBe("421.3/007/SKL");
    expect(formatNumber("{n}-{n}", 12, 1)).toBe("12-12");
  });
});

describe("orderGraduates", () => {
  it("orders by class then name", () => {
    expect(orderGraduates(rows).map((r) => r.full_name)).toEqual(["Ani", "Budi", "Citra"]);
  });
});

describe("buildCertificateNumbers", () => {
  it("numbers graduates in class-then-name order", () => {
    expect(buildCertificateNumbers(rows, {}, opts)).toEqual({
      [B]: "421.3/001/SKL/2026",
      [A]: "421.3/002/SKL/2026",
      [C]: "421.3/003/SKL/2026",
    });
  });

  it("keeps typed numbers unless overwrite", () => {
    const typed = { [A]: "MANUAL-9" };
    const filled = buildCertificateNumbers(rows, typed, opts);
    expect(filled[A]).toBe("MANUAL-9");
    expect(filled[B]).toBe("421.3/001/SKL/2026");
    expect(filled[C]).toBe("421.3/002/SKL/2026");

    const overwritten = buildCertificateNumbers(rows, typed, { ...opts, overwrite: true });
    expect(overwritten[A]).toBe("421.3/002/SKL/2026");
  });

  it("keeps saved numbers unless overwrite", () => {
    const saved = [cert(B, "Ani", "IX-A", "OLD-1"), cert(A, "Budi", "IX-A")];
    const filled = buildCertificateNumbers(saved, {}, { ...opts, start: 5 });
    expect(filled[B]).toBeUndefined();
    expect(filled[A]).toBe("421.3/005/SKL/2026");
  });
});

describe("duplicateNumbers", () => {
  it("flags rows sharing a non-blank number, saved or drafted", () => {
    const saved = [cert(A, "Budi", "IX-A", "X"), cert(B, "Ani", "IX-A"), cert(C, "Citra", "IX-B")];
    expect(duplicateNumbers(saved, { [B]: " X ", [C]: "" })).toEqual(new Set([A, B]));
  });
});

describe("certificateChanges", () => {
  it("sends only drafted rows that differ from the saved number", () => {
    const saved = [cert(A, "Budi", "IX-A", "X"), cert(B, "Ani", "IX-A")];
    expect(certificateChanges(saved, { [A]: " X ", [B]: "Y" })).toEqual([{ student_id: B, certificate_number: "Y" }]);
    expect(effectiveNumber(saved[0], {})).toBe("X");
  });
});

describe("formatLetterDate", () => {
  it("formats a DATE as a local calendar day in Indonesian", () => {
    expect(formatLetterDate("2026-06-20")).toBe("20 Juni 2026");
    expect(formatLetterDate("2009-03-04")).toBe("4 Maret 2009");
    expect(formatLetterDate(null)).toBe("");
  });
});

describe("mapStudentErrors", () => {
  it("maps student lines to rows and keeps the rest", () => {
    const out = mapStudentErrors(
      [`student ${A}: listed more than once`, "must contain between 1 and 2000 items", `student ${C}: not a graduate of this run`],
      new Set([A, B]),
    );
    expect(out.byStudent).toEqual({ [A]: ["listed more than once"] });
    expect(out.unmatched).toEqual(["must contain between 1 and 2000 items", `student ${C}: not a graduate of this run`]);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/lib/promotion/letters.test.ts`
Expected: FAIL — `Failed to resolve import "@/lib/promotion/letters"` (named RED for a new module).

- [ ] **Step 3: Implement**

`src/lib/promotion/letters.ts`:

```ts
import { format } from "date-fns";
import { id as idLocale } from "date-fns/locale/id";

import type { Certificate } from "@/lib/query/queries/use-promotion-letters";

/** "2026-06-20" → "20 Juni 2026" as a local calendar date (never shifted by timezone). */
export function formatLetterDate(value: string | null | undefined): string {
  if (!value) return "";
  const [y, m, d] = value.slice(0, 10).split("-").map(Number);
  if (!y || !m || !d) return "";
  return format(new Date(y, m - 1, d), "d MMMM yyyy", { locale: idLocale });
}

/** student_id → certificate number as typed; only edited rows are present. */
export type CertificateDraft = Record<string, string>;

const collator = new Intl.Collator("id", { sensitivity: "base" });

export function orderGraduates(rows: Certificate[]): Certificate[] {
  return [...rows].sort(
    (a, b) =>
      collator.compare(a.last_homeroom_name ?? "", b.last_homeroom_name ?? "") ||
      collator.compare(a.full_name ?? "", b.full_name ?? "") ||
      a.student_id.localeCompare(b.student_id),
  );
}

export function formatNumber(pattern: string, n: number, digits: number): string {
  return pattern.split("{n}").join(String(n).padStart(digits, "0"));
}

export function effectiveNumber(row: Certificate, draft: CertificateDraft): string {
  return row.student_id in draft ? draft[row.student_id] : (row.certificate_number ?? "");
}

/** Fills numbers from a pattern; filled rows consume the counter, skipped rows do not. */
export function buildCertificateNumbers(
  rows: Certificate[],
  draft: CertificateDraft,
  opts: { pattern: string; start: number; digits: number; overwrite: boolean },
): CertificateDraft {
  const next: CertificateDraft = { ...draft };
  let n = opts.start;
  for (const row of orderGraduates(rows)) {
    if (!opts.overwrite && effectiveNumber(row, draft).trim() !== "") continue;
    next[row.student_id] = formatNumber(opts.pattern, n, opts.digits);
    n += 1;
  }
  return next;
}

export function duplicateNumbers(rows: Certificate[], draft: CertificateDraft): Set<string> {
  const byNumber = new Map<string, string[]>();
  for (const row of rows) {
    const value = effectiveNumber(row, draft).trim();
    if (value === "") continue;
    byNumber.set(value, [...(byNumber.get(value) ?? []), row.student_id]);
  }
  const duplicates = new Set<string>();
  for (const ids of byNumber.values()) if (ids.length > 1) ids.forEach((id) => duplicates.add(id));
  return duplicates;
}

export function certificateChanges(
  rows: Certificate[],
  draft: CertificateDraft,
): { student_id: string; certificate_number: string }[] {
  const changes: { student_id: string; certificate_number: string }[] = [];
  for (const row of rows) {
    if (!(row.student_id in draft)) continue;
    const value = draft[row.student_id].trim();
    if (value !== (row.certificate_number ?? "")) changes.push({ student_id: row.student_id, certificate_number: value });
  }
  return changes;
}

const STUDENT_PREFIX = /^student ([0-9a-f-]{36}): (.*)$/i;

export function mapStudentErrors(
  messages: string[],
  knownIds: ReadonlySet<string>,
): { byStudent: Record<string, string[]>; unmatched: string[] } {
  const byStudent: Record<string, string[]> = {};
  const unmatched: string[] = [];
  for (const message of messages) {
    const match = STUDENT_PREFIX.exec(message);
    if (match && knownIds.has(match[1])) {
      (byStudent[match[1]] ??= []).push(match[2]);
    } else {
      unmatched.push(message);
    }
  }
  return { byStudent, unmatched };
}
```

- [ ] **Step 4: Run the test to verify it passes**

`pnpm vitest run src/lib/promotion/letters.test.ts`, then `TZ=America/New_York pnpm vitest run src/lib/promotion/letters.test.ts`, `pnpm typecheck`, `pnpm lint`. Expected: PASS in both timezones.

- [ ] **Step 5: Commit (web repo)**

```bash
git add src/lib/promotion/letters.ts src/lib/promotion/letters.test.ts
git commit -m "feat(web): add pure graduation certificate numbering"
```

---

### Task 7: Web — "Surat" tab, principal card, SK Kenaikan Kelas section

**Files:**
- Create: `apps/web/src/components/features/promotion/letters-tab.tsx`
- Create: `apps/web/src/components/features/promotion/class-letter-dialog.tsx`
- Create: `apps/web/src/components/features/promotion/letters-tab.test.tsx`
- Modify: `apps/web/src/components/features/promotion/run-detail.tsx` (tabs ~150–181)

**Interfaces:**
- Consumes: Task 5 hooks/types/schemas/copy; `ConfirmDialog` from `@/components/ui/confirm-dialog`; `DatePicker` from `@/components/ui/date-picker` (`value: "YYYY-MM-DD"`, `onChange(string)`); `formatDateTime` from `@/lib/date-utils`; Task 6 `formatLetterDate` from `@/lib/promotion/letters`; `promotionFieldGroups`, `getErrorMessage`, `PRINCIPAL_MISSING_MESSAGE`, `letterNumberMessage` from `@/lib/errors/messages`; `applyServerFieldErrors` from `@/lib/forms/apply-server-field-errors`.
- Produces: `LettersTab({ runId, editable }: { runId: string; editable: boolean })`. It renders the principal card, the SK section, and — at the marker `{/* CERTIFICATES_SECTION */}` — nothing yet (Task 8 replaces the marker).
- Produces: `ClassLetterDialog({ runId, row, defaultCity, open, onOpenChange })` where `row: ClassLetterSummary | null`.
- `run-detail.tsx`: a "Surat" tab, shown only when `run.status === "executed"`, rendering `<LettersTab runId={runId} editable={access.canManage} />`.

- [ ] **Step 1: Write the failing test**

`src/components/features/promotion/letters-tab.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiHttpError } from "@/lib/api/types";
import type { LettersSummary } from "@/lib/query/queries/use-promotion-letters";

const issue = vi.hoisted(() => vi.fn());
const summary = vi.hoisted(() => ({ current: null as LettersSummary | null }));

vi.mock("@/lib/query/queries/use-promotion-letters", () => ({
  usePromotionLetters: () => ({ data: summary.current, isLoading: false, error: null }),
  useCertificatesPrint: () => ({ data: { letterhead: null, source_year_name: null, certificates: [] }, isLoading: false }),
}));
vi.mock("@/lib/query/mutations/use-promotion-letters", () => ({
  useIssueClassLetter: () => ({ mutateAsync: issue, isPending: false }),
  useIssueCertificates: () => ({ mutateAsync: vi.fn(), isPending: false }),
  useRefreshLetterPrincipal: () => ({ mutateAsync: vi.fn(), isPending: false }),
}));

import { LettersTab } from "@/components/features/promotion/letters-tab";

const H = "11111111-1111-4111-8111-111111111111";

function base(principal: string | null): LettersSummary {
  return {
    school_profile: principal
      ? ({ school_name: "SMP Negeri 1", principal_name: principal, principal_nip: null, city_regency: "Surabaya" } as LettersSummary["school_profile"])
      : null,
    class_letters: [{ homeroom_id: H, homeroom_name: "VII-A", counts: { promote: 30, retain: 1, graduate: 0 }, letter: null }],
    certificates: { graduates: 0, issued: 0 },
  };
}

describe("LettersTab", () => {
  beforeEach(() => issue.mockReset());

  it("locks issuing when the school profile has no principal", () => {
    summary.current = base(null);
    render(<LettersTab runId="run-1" editable />);
    expect(screen.getByText(/Nama kepala sekolah belum diisi/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Buka Profil Sekolah" }).getAttribute("href")).toBe("/settings/school-profile");
    expect((screen.getByRole("button", { name: "Terbitkan" }) as HTMLButtonElement).disabled).toBe(true);
  });

  it("disables printing until the letter is issued and hides actions when read-only", () => {
    summary.current = base("Dra. Siti Rahayu");
    const { rerender } = render(<LettersTab runId="run-1" editable />);
    expect(screen.getByText("Belum terbit")).toBeTruthy();
    expect((screen.getByRole("button", { name: "Cetak" }) as HTMLButtonElement).disabled).toBe(true);
    rerender(<LettersTab runId="run-1" editable={false} />);
    expect(screen.queryByRole("button", { name: "Terbitkan" })).toBeNull();
  });

  it("maps a duplicate-number error to the number field", async () => {
    summary.current = base("Dra. Siti Rahayu");
    issue.mockRejectedValueOnce(
      new ApiHttpError(400, {
        code: "VALIDATION_ERROR",
        message: "invalid",
        fields: { letter_number: ["is already used by another letter"] },
      }),
    );
    render(<LettersTab runId="run-1" editable />);
    fireEvent.click(screen.getByRole("button", { name: "Terbitkan" }));
    fireEvent.change(screen.getByLabelText(/Nomor SK/), { target: { value: "421/001" } });
    fireEvent.click(screen.getByRole("button", { name: "Simpan" }));
    await waitFor(() => expect(issue).toHaveBeenCalledTimes(1));
    expect(issue.mock.calls[0][0]).toMatchObject({ homeroomId: H, letter_number: "421/001", city: null });
    expect(await screen.findByText("Nomor sudah dipakai surat lain")).toBeTruthy();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/components/features/promotion/letters-tab.test.tsx`
Expected: FAIL — cannot resolve `@/components/features/promotion/letters-tab`.

- [ ] **Step 3: Class letter dialog**

`src/components/features/promotion/class-letter-dialog.tsx`:

```tsx
"use client";

import * as React from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { DatePicker } from "@/components/ui/date-picker";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormLabelRequired, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/toaster";
import { ApiHttpError } from "@/lib/api/types";
import { getErrorMessage, letterNumberMessage } from "@/lib/errors/messages";
import { useIssueClassLetter } from "@/lib/query/mutations/use-promotion-letters";
import type { ClassLetterSummary } from "@/lib/query/queries/use-promotion-letters";
import { classLetterSchema, toCityPayload, type ClassLetterForm } from "@/lib/schemas/promotion-letters";

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export function ClassLetterDialog({
  runId,
  row,
  defaultCity,
  open,
  onOpenChange,
}: {
  runId: string;
  row: ClassLetterSummary | null;
  defaultCity: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const issue = useIssueClassLetter(runId);
  const [failure, setFailure] = React.useState<unknown>(null);
  const form = useForm<ClassLetterForm>({
    resolver: zodResolver(classLetterSchema),
    defaultValues: { letter_number: "", letter_date: today(), city: "" },
  });

  React.useEffect(() => {
    if (open && row) {
      form.reset({
        letter_number: row.letter?.letter_number ?? "",
        letter_date: row.letter?.letter_date ?? today(),
        city: row.letter?.city ?? "",
      });
      setFailure(null);
    }
  }, [open, row, form]);

  if (!row) return null;

  async function onSubmit(values: ClassLetterForm) {
    setFailure(null);
    try {
      await issue.mutateAsync({
        homeroomId: row!.homeroom_id,
        letter_number: values.letter_number,
        letter_date: values.letter_date,
        city: toCityPayload(values.city),
      });
      toast.success(row!.letter ? "SK diperbarui." : "SK diterbitkan.");
      onOpenChange(false);
    } catch (error) {
      const fields = error instanceof ApiHttpError ? error.fields : undefined;
      let applied = false;
      for (const key of ["letter_number", "letter_date", "city"] as const) {
        const message = fields?.[key]?.[0];
        if (message) {
          form.setError(key, { type: "server", message: letterNumberMessage(message) });
          applied = true;
        }
      }
      if (!applied || fields?.principal) setFailure(error);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{row.letter ? "Ubah" : "Terbitkan"} SK — {row.homeroom_name ?? "—"}</DialogTitle>
          <DialogDescription>
            Nama sekolah dan kepala sekolah diambil saat SK pertama kali diterbitkan dan tidak berubah saat SK dikoreksi.
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
            <FormField
              control={form.control}
              name="letter_number"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Nomor SK</FormLabelRequired>
                  <FormControl>
                    <Input {...field} placeholder="421/001/SK/2026" />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="letter_date"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Tanggal surat</FormLabelRequired>
                  <FormControl>
                    <DatePicker value={field.value} onChange={field.onChange} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="city"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Kota</FormLabel>
                  <FormControl>
                    <Input {...field} placeholder={defaultCity ?? "Kota penerbitan"} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            {failure ? (
              <Alert variant="destructive">
                <AlertDescription>{getErrorMessage(failure, { fallback: "SK gagal disimpan." })}</AlertDescription>
              </Alert>
            ) : null}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Batal
              </Button>
              <Button type="submit" loading={issue.isPending}>
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

`FormLabelRequired` is exported from `@/components/ui/form` (the school-profile page imports it). If `FormControl` around `DatePicker` conflicts with its props in the type checker, render `DatePicker` without `FormControl` and pass `aria-invalid={!!fieldState.error}` from the render prop; list the adaptation.

- [ ] **Step 4: Letters tab**

`src/components/features/promotion/letters-tab.tsx`:

```tsx
"use client";

import * as React from "react";
import Link from "next/link";

import { ClassLetterDialog } from "@/components/features/promotion/class-letter-dialog";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toaster";
import { formatDateTime } from "@/lib/date-utils";
import { getErrorMessage, PRINCIPAL_MISSING_MESSAGE } from "@/lib/errors/messages";
import { formatLetterDate } from "@/lib/promotion/letters";
import { useRefreshLetterPrincipal } from "@/lib/query/mutations/use-promotion-letters";
import { usePromotionLetters, type ClassLetterSummary } from "@/lib/query/queries/use-promotion-letters";

export function LettersTab({ runId, editable }: { runId: string; editable: boolean }) {
  const letters = usePromotionLetters(runId);
  const refresh = useRefreshLetterPrincipal(runId);
  const [editing, setEditing] = React.useState<ClassLetterSummary | null>(null);
  const [refreshing, setRefreshing] = React.useState(false);

  if (letters.isLoading) return <Skeleton className="h-64 w-full" />;
  if (letters.error || !letters.data) {
    return (
      <Alert variant="destructive">
        <AlertDescription>{getErrorMessage(letters.error, { fallback: "Tidak bisa memuat data surat." })}</AlertDescription>
      </Alert>
    );
  }

  const data = letters.data;
  const profile = data.school_profile;
  const hasPrincipal = Boolean(profile?.principal_name?.trim());
  const issuedCount = data.class_letters.filter((c) => c.letter).length + data.certificates.issued;

  async function onRefresh() {
    try {
      const outcome = await refresh.mutateAsync();
      toast.success(`${outcome.updated} surat memakai data kepala sekolah terbaru.`);
      setRefreshing(false);
    } catch (error) {
      toast.error(getErrorMessage(error, { fallback: "Gagal memperbarui data kepala sekolah." }));
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <CardTitle className="text-base">Data kepala sekolah</CardTitle>
          {editable && hasPrincipal && issuedCount > 0 ? (
            <Button variant="outline" size="sm" onClick={() => setRefreshing(true)}>
              Perbarui data kepala sekolah
            </Button>
          ) : null}
        </CardHeader>
        <CardContent className="grid grid-cols-1 gap-2 text-sm md:grid-cols-3">
          {hasPrincipal ? (
            <>
              <p>
                <span className="text-muted-foreground">Nama: </span>
                {profile!.principal_name}
              </p>
              <p>
                <span className="text-muted-foreground">NIP: </span>
                {profile!.principal_nip || "—"}
              </p>
              <p>
                <span className="text-muted-foreground">Kota: </span>
                {profile!.city_regency || "—"}
              </p>
            </>
          ) : (
            <Alert className="md:col-span-3">
              <AlertTitle>Kepala sekolah belum diisi</AlertTitle>
              <AlertDescription>
                {PRINCIPAL_MISSING_MESSAGE}{" "}
                <Link href="/settings/school-profile" className="underline">
                  Buka Profil Sekolah
                </Link>
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">SK Kenaikan Kelas</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Kelas</TableHead>
                <TableHead className="text-right">Naik / Tinggal / Lulus</TableHead>
                <TableHead>Nomor SK</TableHead>
                <TableHead>Tanggal</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Aksi</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.class_letters.map((row) => (
                <TableRow key={row.homeroom_id}>
                  <TableCell className="font-medium">{row.homeroom_name ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {row.counts.promote} / {row.counts.retain} / {row.counts.graduate}
                  </TableCell>
                  <TableCell>{row.letter?.letter_number ?? "—"}</TableCell>
                  <TableCell>{row.letter ? formatLetterDate(row.letter.letter_date) : "—"}</TableCell>
                  <TableCell>
                    {row.letter ? (
                      <span className="text-xs">
                        <Badge variant="secondary">Terbit</Badge> diubah {formatDateTime(row.letter.updated_at)}
                      </span>
                    ) : (
                      <Badge variant="outline">Belum terbit</Badge>
                    )}
                  </TableCell>
                  <TableCell className="space-x-2 text-right">
                    {editable ? (
                      <Button size="sm" variant="outline" disabled={!row.letter && !hasPrincipal} onClick={() => setEditing(row)}>
                        {row.letter ? "Ubah" : "Terbitkan"}
                      </Button>
                    ) : null}
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={!row.letter}
                      onClick={() =>
                        window.open(`/promotion/${runId}/print/class-letter/${row.homeroom_id}`, "_blank", "noopener")
                      }
                    >
                      Cetak
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* CERTIFICATES_SECTION */}

      <ClassLetterDialog
        runId={runId}
        row={editing}
        defaultCity={profile?.city_regency ?? null}
        open={editing !== null}
        onOpenChange={(open) => !open && setEditing(null)}
      />
      <ConfirmDialog
        open={refreshing}
        onOpenChange={setRefreshing}
        title="Perbarui data kepala sekolah?"
        description={`${issuedCount} surat akan memakai data kepala sekolah terbaru (${profile?.principal_name ?? "—"}).`}
        confirmLabel="Perbarui"
        loading={refresh.isPending}
        onConfirm={onRefresh}
      />
    </div>
  );
}
```

- [ ] **Step 5: Wire into the run detail**

In `src/components/features/promotion/run-detail.tsx`:
- import `LettersTab` from `@/components/features/promotion/letters-tab`;
- after `const showPlacement = ...`, add `const showLetters = run.status === "executed";`;
- in `TabsList`, after the placement trigger: `{showLetters ? <TabsTrigger value="letters">Surat</TabsTrigger> : null}`;
- after the placement `TabsContent` block:

```tsx
        {showLetters ? (
          <TabsContent value="letters">
            <LettersTab runId={runId} editable={access.canManage} />
          </TabsContent>
        ) : null}
```

- [ ] **Step 6: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion/letters-tab.test.tsx`, then `pnpm vitest run src/components/features/promotion src/lib/promotion`, `pnpm typecheck`, `pnpm lint`. Expected: PASS. If the DatePicker (a Radix Popover) breaks in jsdom, the test never opens it; only the number field is typed.

- [ ] **Step 7: Commit (web repo)**

```bash
git add src/components/features/promotion/letters-tab.tsx src/components/features/promotion/class-letter-dialog.tsx src/components/features/promotion/letters-tab.test.tsx src/components/features/promotion/run-detail.tsx
git commit -m "feat(web): issue class promotion letters from the run detail"
```

---

### Task 8: Web — Surat Keterangan Lulus section

**Files:**
- Create: `apps/web/src/components/features/promotion/certificates-section.tsx`
- Create: `apps/web/src/components/features/promotion/number-pattern-dialog.tsx`
- Create: `apps/web/src/components/features/promotion/certificates-section.test.tsx`
- Modify: `apps/web/src/components/features/promotion/letters-tab.tsx` (replace `{/* CERTIFICATES_SECTION */}`)

**Interfaces:**
- Consumes: Task 5 `useCertificatesPrint(runId)` (the list of graduates with their numbers), `useIssueCertificates(runId)`, `numberPatternSchema`, `toCityPayload`, `letterNumberMessage`, `promotionFieldGroups`; Task 6 numbering functions; `withStudentNames` from `@/lib/promotion/placement`.
- Produces: `CertificatesSection({ runId, editable, hasPrincipal, defaultCity }: { runId: string; editable: boolean; hasPrincipal: boolean; defaultCity: string | null })`; `NumberPatternDialog({ open, onOpenChange, defaultCity, onApply })` where `onApply(values: NumberPatternForm) => void`.
- The section keeps `letter_date` and `city` for the next save in local state; they are set by the pattern dialog and shown above the table with "Ubah tanggal/kota" (re-opens the dialog). Saving with rows changed but no date asks the user to fill the pattern dialog first.

- [ ] **Step 1: Write the failing test**

`src/components/features/promotion/certificates-section.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ApiHttpError } from "@/lib/api/types";
import type { Certificate } from "@/lib/query/queries/use-promotion-letters";

const save = vi.hoisted(() => vi.fn());
const A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function cert(student_id: string, full_name: string, certificate_number: string | null): Certificate {
  return {
    student_id, full_name, nis: `N-${full_name}`, nisn: null, birth_place: null, birth_date: null,
    last_homeroom_name: "IX-A", graduation_date: "2026-06-15", certificate_number,
    letter_date: certificate_number ? "2026-06-22" : null, city: certificate_number ? "Surabaya" : null,
    school_name: null, principal_name: null, principal_nip: null, issued_at: null, updated_at: null,
  };
}

vi.mock("@/lib/query/queries/use-promotion-letters", () => ({
  useCertificatesPrint: () => ({
    data: { letterhead: null, source_year_name: "2025/2026", certificates: [cert(A, "Budi", null), cert(B, "Ani", "X-1")] },
    isLoading: false,
    error: null,
  }),
}));
vi.mock("@/lib/query/mutations/use-promotion-letters", () => ({
  useIssueCertificates: () => ({ mutateAsync: save, isPending: false }),
}));

import { CertificatesSection } from "@/components/features/promotion/certificates-section";

describe("CertificatesSection", () => {
  beforeEach(() => save.mockReset());

  it("flags duplicate numbers before saving and blocks the save", () => {
    render(<CertificatesSection runId="run-1" editable hasPrincipal defaultCity="Surabaya" />);
    fireEvent.change(screen.getByLabelText("Nomor surat Budi"), { target: { value: "X-1" } });
    expect(screen.getAllByText("Nomor dipakai dua kali").length).toBe(2);
    expect((screen.getByRole("button", { name: "Simpan nomor" }) as HTMLButtonElement).disabled).toBe(true);
  });

  it("sends only changed rows and maps row errors to names", async () => {
    save.mockRejectedValueOnce(
      new ApiHttpError(400, {
        code: "VALIDATION_ERROR",
        message: "invalid",
        fields: { items: [`student ${A}: certificate number X-9 is already used by another letter`] },
      }),
    );
    render(<CertificatesSection runId="run-1" editable hasPrincipal defaultCity="Surabaya" />);
    fireEvent.change(screen.getByLabelText("Nomor surat Budi"), { target: { value: "X-9" } });
    fireEvent.click(screen.getByRole("button", { name: "Simpan nomor" }));
    await waitFor(() => expect(save).toHaveBeenCalledTimes(1));
    // Ani's saved date is reused when no pattern dialog has set one.
    expect(save.mock.calls[0][0]).toEqual({
      letter_date: "2026-06-22",
      city: null,
      items: [{ student_id: A, certificate_number: "X-9" }],
    });
    expect(await screen.findByText("Nomor sudah dipakai surat lain")).toBeTruthy();
  });

  it("is read-only without manage", () => {
    render(<CertificatesSection runId="run-1" editable={false} hasPrincipal defaultCity={null} />);
    expect(screen.queryByRole("button", { name: "Isi nomor dari pola" })).toBeNull();
    expect(screen.queryByLabelText("Nomor surat Budi")).toBeNull();
    expect(screen.getByText("X-1")).toBeTruthy();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/components/features/promotion/certificates-section.test.tsx`
Expected: FAIL — cannot resolve `@/components/features/promotion/certificates-section`.

- [ ] **Step 3: Pattern dialog**

`src/components/features/promotion/number-pattern-dialog.tsx`:

```tsx
"use client";

import * as React from "react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { DatePicker } from "@/components/ui/date-picker";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormLabelRequired, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { formatNumber } from "@/lib/promotion/letters";
import { numberPatternSchema, type NumberPatternForm } from "@/lib/schemas/promotion-letters";

export function NumberPatternDialog({
  open,
  onOpenChange,
  defaultCity,
  initial,
  onApply,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultCity: string | null;
  initial: { letter_date: string; city: string };
  onApply: (values: NumberPatternForm) => void;
}) {
  const form = useForm<NumberPatternForm>({
    resolver: zodResolver(numberPatternSchema),
    defaultValues: { pattern: "", start: "1", digits: "3", letter_date: initial.letter_date, city: initial.city, overwrite: false },
  });

  React.useEffect(() => {
    if (open) form.reset({ ...form.getValues(), letter_date: initial.letter_date, city: initial.city, overwrite: false });
  }, [open, initial.letter_date, initial.city, form]);

  const pattern = form.watch("pattern");
  const start = Number(form.watch("start")) || 1;
  const digits = Number(form.watch("digits")) || 1;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Isi nomor dari pola</DialogTitle>
          <DialogDescription>
            Nomor diurutkan per kelas lalu nama. Nomor yang sudah ada tidak diubah kecuali Anda memilih untuk menimpanya.
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form
            onSubmit={form.handleSubmit((values) => {
              onApply(values);
              onOpenChange(false);
            })}
            className="space-y-4"
            noValidate
          >
            <FormField
              control={form.control}
              name="pattern"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Pola</FormLabelRequired>
                  <FormControl>
                    <Input {...field} placeholder="421.3/{n}/SKL/2026" />
                  </FormControl>
                  <FormMessage />
                  {pattern.includes("{n}") ? (
                    <p className="text-xs text-muted-foreground">Contoh: {formatNumber(pattern, start, digits)}</p>
                  ) : null}
                </FormItem>
              )}
            />
            <div className="grid grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="start"
                render={({ field }) => (
                  <FormItem>
                    <FormLabelRequired>Nomor awal</FormLabelRequired>
                    <FormControl>
                      <Input {...field} inputMode="numeric" />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="digits"
                render={({ field }) => (
                  <FormItem>
                    <FormLabelRequired>Jumlah digit</FormLabelRequired>
                    <FormControl>
                      <Input {...field} inputMode="numeric" />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>
            <FormField
              control={form.control}
              name="letter_date"
              render={({ field }) => (
                <FormItem>
                  <FormLabelRequired>Tanggal surat</FormLabelRequired>
                  <FormControl>
                    <DatePicker value={field.value} onChange={field.onChange} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="city"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Kota</FormLabel>
                  <FormControl>
                    <Input {...field} placeholder={defaultCity ?? "Kota penerbitan"} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="overwrite"
              render={({ field }) => (
                <FormItem className="flex items-center gap-2 space-y-0">
                  <FormControl>
                    <Checkbox checked={field.value} onCheckedChange={(c) => field.onChange(c === true)} />
                  </FormControl>
                  <FormLabel className="font-normal">Timpa nomor yang sudah ada</FormLabel>
                </FormItem>
              )}
            />
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Batal
              </Button>
              <Button type="submit">Isi nomor</Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Certificates section**

`src/components/features/promotion/certificates-section.tsx`:

```tsx
"use client";

import * as React from "react";

import { NumberPatternDialog } from "@/components/features/promotion/number-pattern-dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/toaster";
import { ApiHttpError } from "@/lib/api/types";
import { getErrorMessage, letterNumberMessage, promotionFieldGroups } from "@/lib/errors/messages";
import {
  buildCertificateNumbers,
  certificateChanges,
  duplicateNumbers,
  effectiveNumber,
  formatLetterDate,
  mapStudentErrors,
  orderGraduates,
  type CertificateDraft,
} from "@/lib/promotion/letters";
import { withStudentNames } from "@/lib/promotion/placement";
import { useIssueCertificates } from "@/lib/query/mutations/use-promotion-letters";
import { useCertificatesPrint } from "@/lib/query/queries/use-promotion-letters";
import { toCityPayload, type NumberPatternForm } from "@/lib/schemas/promotion-letters";

export function CertificatesSection({
  runId,
  editable,
  hasPrincipal,
  defaultCity,
}: {
  runId: string;
  editable: boolean;
  hasPrincipal: boolean;
  defaultCity: string | null;
}) {
  const list = useCertificatesPrint(runId);
  const save = useIssueCertificates(runId);
  const [draft, setDraft] = React.useState<CertificateDraft>({});
  const [meta, setMeta] = React.useState<{ letter_date: string; city: string } | null>(null);
  const [patternOpen, setPatternOpen] = React.useState(false);
  const [rowErrors, setRowErrors] = React.useState<Record<string, string[]>>({});
  const [failure, setFailure] = React.useState<string[]>([]);

  const rows = React.useMemo(() => orderGraduates(list.data?.certificates ?? []), [list.data]);
  const changes = React.useMemo(() => certificateChanges(rows, draft), [rows, draft]);
  const duplicates = React.useMemo(() => duplicateNumbers(rows, draft), [rows, draft]);
  const dirty = changes.length > 0;

  React.useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  if (list.isLoading) return <Skeleton className="h-48 w-full" />;
  if (list.error || !list.data) {
    return (
      <Alert variant="destructive">
        <AlertDescription>{getErrorMessage(list.error, { fallback: "Tidak bisa memuat daftar lulusan." })}</AlertDescription>
      </Alert>
    );
  }
  if (rows.length === 0) return null;

  // Date/city for the next save: the pattern dialog's, else the last issued certificate's.
  const issued = rows.find((r) => r.letter_date);
  const current = meta ?? { letter_date: issued?.letter_date ?? "", city: "" };
  const names = new Map(rows.map((r) => [r.student_id, r.full_name ?? r.student_id]));

  function applyPattern(values: NumberPatternForm) {
    setDraft((d) =>
      buildCertificateNumbers(rows, d, {
        pattern: values.pattern,
        start: Number(values.start),
        digits: Number(values.digits),
        overwrite: values.overwrite,
      }),
    );
    setMeta({ letter_date: values.letter_date, city: values.city });
    setRowErrors({});
  }

  async function onSave() {
    if (!current.letter_date) {
      setPatternOpen(true);
      return;
    }
    setRowErrors({});
    setFailure([]);
    try {
      const outcome = await save.mutateAsync({
        letter_date: current.letter_date,
        city: toCityPayload(current.city),
        items: changes,
      });
      toast.success(`${outcome.updated} nomor surat disimpan.`);
      setDraft({});
    } catch (error) {
      const items = error instanceof ApiHttpError ? (error.fields?.items ?? []) : [];
      const { byStudent, unmatched } = mapStudentErrors(items, new Set(rows.map((r) => r.student_id)));
      setRowErrors(byStudent);
      const other = promotionFieldGroups(error)
        .filter((g) => g.field !== "items")
        .flatMap((g) => g.messages.map((m) => `${g.label}: ${m}`));
      const lines = [...unmatched.map((m) => withStudentNames(m, names)), ...other];
      setFailure(lines.length > 0 || Object.keys(byStudent).length > 0 ? lines : [getErrorMessage(error, { fallback: "Nomor surat gagal disimpan." })]);
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div className="space-y-1">
          <CardTitle className="text-base">Surat Keterangan Lulus</CardTitle>
          <p className="text-xs text-muted-foreground">
            {current.letter_date ? `Tanggal surat ${formatLetterDate(current.letter_date)}` : "Tanggal surat belum diisi"}
            {current.city ? ` · ${current.city}` : defaultCity ? ` · ${defaultCity}` : ""}
          </p>
        </div>
        <div className="flex gap-2">
          {editable ? (
            <>
              <Button size="sm" variant="outline" disabled={!hasPrincipal} onClick={() => setPatternOpen(true)}>
                Isi nomor dari pola
              </Button>
              <Button size="sm" disabled={!dirty || duplicates.size > 0 || !hasPrincipal} loading={save.isPending} onClick={onSave}>
                Simpan nomor
              </Button>
            </>
          ) : null}
          <Button
            size="sm"
            variant="ghost"
            disabled={dirty || !rows.some((r) => r.certificate_number)}
            onClick={() => window.open(`/promotion/${runId}/print/certificates`, "_blank", "noopener")}
          >
            Cetak semua
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {dirty ? <Badge variant="outline">{changes.length} perubahan belum disimpan</Badge> : null}
        {failure.length > 0 ? (
          <Alert variant="destructive">
            <AlertDescription>
              <ul className="list-disc pl-4">
                {failure.map((line, i) => (
                  <li key={i}>{line}</li>
                ))}
              </ul>
            </AlertDescription>
          </Alert>
        ) : null}
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nama</TableHead>
              <TableHead>NIS</TableHead>
              <TableHead>Kelas</TableHead>
              <TableHead>Nomor surat</TableHead>
              <TableHead className="text-right">Aksi</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => {
              const value = effectiveNumber(row, draft);
              const errors = [
                ...(duplicates.has(row.student_id) ? ["Nomor dipakai dua kali"] : []),
                ...(rowErrors[row.student_id] ?? []).map(letterNumberMessage),
              ];
              return (
                <TableRow key={row.student_id}>
                  <TableCell className="font-medium">{row.full_name ?? "—"}</TableCell>
                  <TableCell>{row.nis ?? "—"}</TableCell>
                  <TableCell>{row.last_homeroom_name ?? "—"}</TableCell>
                  <TableCell>
                    {editable ? (
                      <Input
                        aria-label={`Nomor surat ${row.full_name ?? row.student_id}`}
                        aria-invalid={errors.length > 0}
                        value={value}
                        onChange={(e) => setDraft((d) => ({ ...d, [row.student_id]: e.target.value }))}
                        className="h-8"
                      />
                    ) : (
                      <span>{row.certificate_number ?? "—"}</span>
                    )}
                    {errors.map((message, i) => (
                      <p key={i} className="mt-1 text-xs text-destructive">
                        {message}
                      </p>
                    ))}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={!row.certificate_number || row.student_id in draft}
                      onClick={() =>
                        window.open(`/promotion/${runId}/print/certificates?student=${row.student_id}`, "_blank", "noopener")
                      }
                    >
                      Cetak
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </CardContent>
      <NumberPatternDialog
        open={patternOpen}
        onOpenChange={setPatternOpen}
        defaultCity={defaultCity}
        initial={current}
        onApply={applyPattern}
      />
    </Card>
  );
}
```

The test expects the "Nomor dipakai dua kali" line on **both** rows (Budi typed X-1; Ani's saved number is X-1): `duplicateNumbers` returns both ids, and each row renders the message — `getAllByText(...).length === 2`.

In the second test the `items` error maps to Budi's row; `letterNumberMessage` turns `certificate number X-9 is already used by another letter` into "Nomor sudah dipakai surat lain".

- [ ] **Step 5: Wire into the letters tab**

In `src/components/features/promotion/letters-tab.tsx`, import `CertificatesSection` and replace `{/* CERTIFICATES_SECTION */}` with:

```tsx
      {data.certificates.graduates > 0 ? (
        <CertificatesSection
          runId={runId}
          editable={editable}
          hasPrincipal={hasPrincipal}
          defaultCity={profile?.city_regency ?? null}
        />
      ) : null}
```

The Task 7 test mocks `useCertificatesPrint` already; its fixtures have `graduates: 0`, so the section does not render there.

- [ ] **Step 6: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion/certificates-section.test.tsx src/components/features/promotion/letters-tab.test.tsx`, then `pnpm vitest run src/components/features/promotion src/lib/promotion`, `pnpm typecheck`, `pnpm lint`. Expected: PASS.

- [ ] **Step 7: Commit (web repo)**

```bash
git add src/components/features/promotion/certificates-section.tsx src/components/features/promotion/number-pattern-dialog.tsx src/components/features/promotion/certificates-section.test.tsx src/components/features/promotion/letters-tab.tsx
git commit -m "feat(web): number and save graduation certificates"
```

---

### Task 9: Web — print documents and print pages

**Files:**
- Create: `apps/web/src/components/features/promotion/letter-print.tsx` (shared letterhead, signature block, `LetterPrintShell`)
- Create: `apps/web/src/components/features/promotion/class-letter-document.tsx`
- Create: `apps/web/src/components/features/promotion/certificate-document.tsx`
- Create: `apps/web/src/components/features/promotion/letter-documents.test.tsx`
- Create: `apps/web/src/app/promotion/[runId]/print/class-letter/[homeroomId]/page.tsx`
- Create: `apps/web/src/app/promotion/[runId]/print/certificates/page.tsx`

**Interfaces:**
- Consumes: Task 5 types and hooks (`useClassLetterPrint`, `useCertificatesPrint`), `ReportCardPrintStyles` from `@/components/features/grading/report-card-print-document`, `AuthGuard` from `@/components/features/auth-guard`, `usePromotionAccess` from `@/lib/query/queries/use-promotion`, Task 6 `formatLetterDate`. Letters word results themselves (no `RESULT_LABEL`).
- Produces: `Letterhead({ letterhead, schoolName })`, `SignatureBlock({ city, date, name, nip })`, `LetterPrintShell({ ready, children, backHref })` (Back button hidden in print, prints once `ready`), `ClassLetterDocument({ data }: { data: ClassLetterPrint })`, `CertificateDocument({ certificate, letterhead, sourceYearName })`, `classLetterResultText(student: ClassLetterStudent): string`.
- Print pages use `AuthGuard` + `usePromotionAccess` directly (not `PromotionPage`, which wraps content in the sidebar layout). Without manage-or-approve they show an alert. An unissued class letter, an executed-status error (409) or no issued certificate shows an alert, never an empty document.

- [ ] **Step 1: Write the failing test**

`src/components/features/promotion/letter-documents.test.tsx`:

```tsx
/** @vitest-environment jsdom */
import * as React from "react";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { CertificateDocument } from "@/components/features/promotion/certificate-document";
import { ClassLetterDocument, classLetterResultText } from "@/components/features/promotion/class-letter-document";
import type { Certificate, ClassLetterPrint, Letterhead } from "@/lib/query/queries/use-promotion-letters";

const letterhead = {
  school_name: "SMP Negeri 1 (nama terkini)",
  npsn: "20531234",
  address_line: "Jl. Pemuda 1",
  city_regency: "Surabaya",
  province: "Jawa Timur",
  logo_url: null,
} as unknown as Letterhead;

const data: ClassLetterPrint = {
  letterhead,
  source_year_name: "2025/2026",
  target_year_name: "2026/2027",
  homeroom_id: "h",
  homeroom_name: "VII-A",
  letter: {
    homeroom_id: "h",
    letter_number: "421/001/SK/2026",
    letter_date: "2026-06-20",
    city: "Surabaya",
    school_name: "SMP Negeri 1",
    principal_name: "Dra. Siti Rahayu",
    principal_nip: null,
    issued_by: "u",
    issued_at: "2026-06-20T01:00:00Z",
    updated_by: "u",
    updated_at: "2026-06-20T01:00:00Z",
  },
  students: [
    { student_id: "1", full_name: "Ani", nis: "001", nisn: "0091", result: "promote", target_homeroom_name: "VIII-A" },
    { student_id: "2", full_name: "Budi", nis: "002", nisn: null, result: "retain", target_homeroom_name: "VII-B" },
  ],
};

describe("classLetterResultText", () => {
  it("words each result", () => {
    expect(classLetterResultText(data.students[0])).toBe("Naik ke kelas VIII-A");
    expect(classLetterResultText(data.students[1])).toBe("Tinggal di kelas VII-B");
    expect(classLetterResultText({ ...data.students[0], result: "graduate", target_homeroom_name: null })).toBe("Lulus");
  });
});

describe("ClassLetterDocument", () => {
  it("renders the snapshot, the year and the students, without an empty NIP line", () => {
    render(<ClassLetterDocument data={data} />);
    expect(screen.getByText("Nomor: 421/001/SK/2026")).toBeTruthy();
    expect(screen.getByText(/Kenaikan Kelas Tahun Ajaran 2025\/2026/)).toBeTruthy();
    expect(screen.getByText("Dra. Siti Rahayu")).toBeTruthy();
    expect(screen.getAllByText("SMP Negeri 1").length).toBeGreaterThan(0);
    expect(screen.queryByText("SMP Negeri 1 (nama terkini)")).toBeNull();
    expect(screen.getByText("Naik ke kelas VIII-A")).toBeTruthy();
    expect(screen.getByText(/Surabaya, 20 Juni 2026/)).toBeTruthy();
    expect(screen.queryByText(/NIP\./)).toBeNull();
  });
});

describe("CertificateDocument", () => {
  it("renders the graduate's identity and the principal with NIP", () => {
    const certificate: Certificate = {
      student_id: "1",
      full_name: "Ani Lulus",
      nis: "001",
      nisn: "0091234567",
      birth_place: "Sidoarjo",
      birth_date: "2009-03-04",
      last_homeroom_name: "IX-A",
      graduation_date: "2026-06-15",
      certificate_number: "421.3/001/SKL/2026",
      letter_date: "2026-06-22",
      city: "Surabaya",
      school_name: "SMP Negeri 1",
      principal_name: "Dra. Siti Rahayu",
      principal_nip: "196805121993032004",
      issued_at: "2026-06-22T01:00:00Z",
      updated_at: "2026-06-22T01:00:00Z",
    };
    render(<CertificateDocument certificate={certificate} letterhead={letterhead} sourceYearName="2025/2026" />);
    expect(screen.getByText("SURAT KETERANGAN LULUS")).toBeTruthy();
    expect(screen.getByText("Nomor: 421.3/001/SKL/2026")).toBeTruthy();
    expect(screen.getByText("Ani Lulus")).toBeTruthy();
    expect(screen.getByText("Sidoarjo, 4 Maret 2009")).toBeTruthy();
    expect(screen.getByText(/pada Tahun Ajaran 2025\/2026/)).toBeTruthy();
    expect(screen.getByText("NIP. 196805121993032004")).toBeTruthy();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

`pnpm vitest run src/components/features/promotion/letter-documents.test.tsx`
Expected: FAIL — cannot resolve `@/components/features/promotion/certificate-document`.

- [ ] **Step 3: Shared print pieces**

`src/components/features/promotion/letter-print.tsx`:

```tsx
"use client";

import * as React from "react";
import { ArrowLeft } from "lucide-react";
import { useRouter } from "next/navigation";

import { ReportCardPrintStyles } from "@/components/features/grading/report-card-print-document";
import { Button } from "@/components/ui/button";
import { formatLetterDate } from "@/lib/promotion/letters";
import type { Letterhead as LetterheadData } from "@/lib/query/queries/use-promotion-letters";

/** Kop surat. `schoolName` is the letter's snapshot; the rest is the live letterhead. */
export function Letterhead({ letterhead, schoolName }: { letterhead: LetterheadData | null; schoolName: string }) {
  const address = [
    letterhead?.address_line,
    letterhead?.village,
    letterhead?.subdistrict,
    letterhead?.city_regency,
    letterhead?.province,
    letterhead?.postal_code,
  ]
    .filter(Boolean)
    .join(", ");
  const contact = [letterhead?.phone_number && `Telp. ${letterhead.phone_number}`, letterhead?.email]
    .filter(Boolean)
    .join(" · ");
  return (
    <header className="flex items-center gap-4 border-b-[3px] border-double border-black pb-3">
      {letterhead?.logo_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- print page; next/image needs remote config and adds nothing here
        <img src={letterhead.logo_url} alt="Logo sekolah" className="h-20 w-20 object-contain" />
      ) : null}
      <div className="flex-1 text-center">
        <p className="text-xl font-bold uppercase">{schoolName}</p>
        {letterhead?.npsn ? <p className="text-sm">NPSN {letterhead.npsn}</p> : null}
        {address ? <p className="text-sm">{address}</p> : null}
        {contact ? <p className="text-sm">{contact}</p> : null}
      </div>
    </header>
  );
}

export function SignatureBlock({
  city,
  date,
  name,
  nip,
}: {
  city: string;
  date: string;
  name: string;
  nip: string | null;
}) {
  return (
    <div className="mt-10 flex justify-end break-inside-avoid">
      <div className="w-64 text-center">
        <p>
          {city}, {formatLetterDate(date)}
        </p>
        <p>Kepala Sekolah,</p>
        <div className="h-20" />
        <p className="font-bold underline">{name}</p>
        {nip ? <p>NIP. {nip}</p> : null}
      </div>
    </div>
  );
}

/** Back button (not printed) and one `window.print()` once `ready`. */
export function LetterPrintShell({
  ready,
  backHref,
  children,
}: {
  ready: boolean;
  backHref: string;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const printed = React.useRef(false);

  React.useEffect(() => {
    if (!ready || printed.current) return;
    printed.current = true;
    const timer = setTimeout(() => window.print(), 600);
    return () => clearTimeout(timer);
  }, [ready]);

  function back() {
    if (window.opener) window.close();
    else router.push(backHref);
  }

  return (
    <main className="mx-auto min-h-screen bg-white p-6 font-serif text-black sm:p-12 md:max-w-[210mm] print:m-0 print:max-w-none print:p-0">
      <ReportCardPrintStyles />
      <div className="mb-6 flex items-center border-b pb-4 font-sans print:hidden">
        <Button variant="ghost" onClick={back} className="flex items-center gap-2">
          <ArrowLeft className="h-4 w-4" /> Kembali
        </Button>
      </div>
      {children}
    </main>
  );
}
```

`ReportCardPrintStyles` is exported from the report-card document (it is imported that way by `src/app/grading/report-cards/print/page.tsx`). If `@next/next/no-img-element` is not a configured rule, drop the disable comment.

- [ ] **Step 4: Documents**

`src/components/features/promotion/class-letter-document.tsx`:

```tsx
import { Letterhead, SignatureBlock } from "@/components/features/promotion/letter-print";
import type { ClassLetterPrint, ClassLetterStudent } from "@/lib/query/queries/use-promotion-letters";

export function classLetterResultText(s: ClassLetterStudent): string {
  if (s.result === "graduate") return "Lulus";
  const target = s.target_homeroom_name ?? "—";
  return s.result === "promote" ? `Naik ke kelas ${target}` : `Tinggal di kelas ${target}`;
}

/** SK Kenaikan Kelas for one source homeroom (spec §4.2). Needs `data.letter`. */
export function ClassLetterDocument({ data }: { data: ClassLetterPrint }) {
  const letter = data.letter!;
  const year = data.source_year_name ?? "—";
  return (
    <article className="text-[12pt] leading-relaxed">
      <Letterhead letterhead={data.letterhead} schoolName={letter.school_name} />
      <div className="my-6 text-center">
        <p className="font-bold underline">SURAT KEPUTUSAN KEPALA SEKOLAH</p>
        <p>Nomor: {letter.letter_number}</p>
        <p className="mt-2 font-bold">Tentang Kenaikan Kelas Tahun Ajaran {year}</p>
      </div>
      <p className="text-justify">
        Kepala {letter.school_name}, berdasarkan hasil evaluasi akhir Tahun Ajaran {year} dan keputusan rapat dewan
        guru, menetapkan hasil kenaikan kelas siswa kelas {data.homeroom_name ?? "—"} sebagai berikut
        {data.target_year_name ? `, berlaku untuk Tahun Ajaran ${data.target_year_name}` : ""}:
      </p>
      <table className="mt-4 w-full border-collapse text-[11pt]">
        <thead className="table-header-group">
          <tr>
            <th className="border border-black px-2 py-1">No</th>
            <th className="border border-black px-2 py-1 text-left">Nama</th>
            <th className="border border-black px-2 py-1">NIS / NISN</th>
            <th className="border border-black px-2 py-1 text-left">Hasil</th>
          </tr>
        </thead>
        <tbody>
          {data.students.map((s, i) => (
            <tr key={s.student_id} className="break-inside-avoid">
              <td className="border border-black px-2 py-1 text-center">{i + 1}</td>
              <td className="border border-black px-2 py-1">{s.full_name ?? "—"}</td>
              <td className="border border-black px-2 py-1 text-center">
                {s.nis ?? "—"}
                {s.nisn ? ` / ${s.nisn}` : ""}
              </td>
              <td className="border border-black px-2 py-1">{classLetterResultText(s)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="mt-4 text-justify">
        Keputusan ini berlaku sejak tanggal ditetapkan. Apabila di kemudian hari terdapat kekeliruan, akan diperbaiki
        sebagaimana mestinya.
      </p>
      <SignatureBlock
        city={letter.city}
        date={letter.letter_date}
        name={letter.principal_name}
        nip={letter.principal_nip}
      />
    </article>
  );
}
```

`src/components/features/promotion/certificate-document.tsx`:

```tsx
import { Letterhead, SignatureBlock } from "@/components/features/promotion/letter-print";
import { formatLetterDate } from "@/lib/promotion/letters";
import type { Certificate, Letterhead as LetterheadData } from "@/lib/query/queries/use-promotion-letters";

/** Surat Keterangan Lulus for one issued graduate (spec §4.2). */
export function CertificateDocument({
  certificate: c,
  letterhead,
  sourceYearName,
}: {
  certificate: Certificate;
  letterhead: LetterheadData | null;
  sourceYearName: string | null;
}) {
  const school = c.school_name ?? letterhead?.school_name ?? "—";
  const birth = [c.birth_place, c.birth_date ? formatLetterDate(c.birth_date) : null].filter(Boolean).join(", ") || "—";
  const rows: [string, string][] = [
    ["Nama", c.full_name ?? "—"],
    ["Tempat, tanggal lahir", birth],
    ["NIS", c.nis ?? "—"],
    ["NISN", c.nisn ?? "—"],
    ["Kelas terakhir", c.last_homeroom_name ?? "—"],
  ];
  return (
    <article className="text-[12pt] leading-relaxed">
      <Letterhead letterhead={letterhead} schoolName={school} />
      <div className="my-6 text-center">
        <p className="font-bold underline">SURAT KETERANGAN LULUS</p>
        <p>Nomor: {c.certificate_number}</p>
      </div>
      <p>Yang bertanda tangan di bawah ini, Kepala {school} menerangkan bahwa:</p>
      <table className="my-4 ml-8">
        <tbody>
          {rows.map(([label, value]) => (
            <tr key={label}>
              <td className="w-48 py-0.5 align-top">{label}</td>
              <td className="px-2 py-0.5 align-top">:</td>
              <td className="py-0.5 font-semibold">{value}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="text-justify">
        telah <span className="font-bold">LULUS</span> dari {school} pada Tahun Ajaran {sourceYearName ?? "—"}, dengan
        tanggal kelulusan {formatLetterDate(c.graduation_date)}.
      </p>
      <p className="mt-2">Demikian surat keterangan ini dibuat untuk dipergunakan sebagaimana mestinya.</p>
      <SignatureBlock
        city={c.city ?? "—"}
        date={c.letter_date ?? c.graduation_date}
        name={c.principal_name ?? "—"}
        nip={c.principal_nip}
      />
    </article>
  );
}
```

- [ ] **Step 5: Print pages**

`src/app/promotion/[runId]/print/class-letter/[homeroomId]/page.tsx`:

```tsx
"use client";

import { useParams } from "next/navigation";

import { AuthGuard } from "@/components/features/auth-guard";
import { ClassLetterDocument } from "@/components/features/promotion/class-letter-document";
import { LetterPrintShell } from "@/components/features/promotion/letter-print";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { getErrorMessage } from "@/lib/errors/messages";
import { usePromotionAccess } from "@/lib/query/queries/use-promotion";
import { useClassLetterPrint } from "@/lib/query/queries/use-promotion-letters";

export default function ClassLetterPrintPage() {
  return (
    <AuthGuard fallback={<Skeleton className="m-6 h-[80vh]" />}>
      <ClassLetterPrint />
    </AuthGuard>
  );
}

function ClassLetterPrint() {
  const { runId, homeroomId } = useParams<{ runId: string; homeroomId: string }>();
  const access = usePromotionAccess();
  const print = useClassLetterPrint(access.canRead ? runId : undefined, homeroomId);
  const backHref = `/promotion/${runId}`;

  let body: React.ReactNode;
  if (access.isLoading || (access.canRead && print.isLoading)) {
    body = <Skeleton className="h-[80vh] w-full" />;
  } else if (!access.canRead) {
    body = <Notice title="Tidak punya akses" text="Halaman ini untuk pengelola atau penyetuju kenaikan kelas." />;
  } else if (print.error || !print.data) {
    body = <Notice title="Surat tidak bisa dimuat" text={getErrorMessage(print.error, { fallback: "Coba lagi nanti." })} />;
  } else if (!print.data.letter) {
    body = <Notice title="SK belum terbit" text="Terbitkan nomor SK untuk kelas ini di tab Surat sebelum mencetak." />;
  } else {
    body = <ClassLetterDocument data={print.data} />;
  }

  return (
    <LetterPrintShell ready={Boolean(print.data?.letter)} backHref={backHref}>
      {body}
    </LetterPrintShell>
  );
}

function Notice({ title, text }: { title: string; text: string }) {
  return (
    <Alert className="font-sans">
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{text}</AlertDescription>
    </Alert>
  );
}
```

(`React` is used as a type namespace; add `import type * as React from "react";` if the type checker needs it.)

`src/app/promotion/[runId]/print/certificates/page.tsx`:

```tsx
"use client";

import type * as React from "react";
import { useParams, useSearchParams } from "next/navigation";

import { AuthGuard } from "@/components/features/auth-guard";
import { CertificateDocument } from "@/components/features/promotion/certificate-document";
import { LetterPrintShell } from "@/components/features/promotion/letter-print";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import { getErrorMessage } from "@/lib/errors/messages";
import { usePromotionAccess } from "@/lib/query/queries/use-promotion";
import { useCertificatesPrint } from "@/lib/query/queries/use-promotion-letters";

export default function CertificatesPrintPage() {
  return (
    <AuthGuard fallback={<Skeleton className="m-6 h-[80vh]" />}>
      <CertificatesPrint />
    </AuthGuard>
  );
}

function CertificatesPrint() {
  const { runId } = useParams<{ runId: string }>();
  const student = useSearchParams().get("student") ?? undefined;
  const access = usePromotionAccess();
  const print = useCertificatesPrint(access.canRead ? runId : undefined, student);
  const issued = (print.data?.certificates ?? []).filter((c) => c.certificate_number);

  let body: React.ReactNode;
  if (access.isLoading || (access.canRead && print.isLoading)) {
    body = <Skeleton className="h-[80vh] w-full" />;
  } else if (!access.canRead) {
    body = <Notice title="Tidak punya akses" text="Halaman ini untuk pengelola atau penyetuju kenaikan kelas." />;
  } else if (print.error || !print.data) {
    body = <Notice title="Surat tidak bisa dimuat" text={getErrorMessage(print.error, { fallback: "Coba lagi nanti." })} />;
  } else if (issued.length === 0) {
    body = <Notice title="Belum ada surat terbit" text="Simpan nomor Surat Keterangan Lulus di tab Surat sebelum mencetak." />;
  } else {
    body = issued.map((c, i) => (
      <div key={c.student_id} className={i > 0 ? "break-before-page" : undefined}>
        <CertificateDocument certificate={c} letterhead={print.data!.letterhead} sourceYearName={print.data!.source_year_name} />
      </div>
    ));
  }

  return (
    <LetterPrintShell ready={issued.length > 0} backHref={`/promotion/${runId}`}>
      {body}
    </LetterPrintShell>
  );
}

function Notice({ title, text }: { title: string; text: string }) {
  return (
    <Alert className="font-sans">
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{text}</AlertDescription>
    </Alert>
  );
}
```

`useSearchParams` in a client page may need a `Suspense` boundary for `next build`; if the build in Task 10 reports "useSearchParams() should be wrapped in a suspense boundary", wrap `<CertificatesPrint />` in `<React.Suspense fallback={...}>` inside `CertificatesPrintPage`. Do it now pre-emptively:

```tsx
export default function CertificatesPrintPage() {
  return (
    <AuthGuard fallback={<Skeleton className="m-6 h-[80vh]" />}>
      <Suspense fallback={<Skeleton className="m-6 h-[80vh]" />}>
        <CertificatesPrint />
      </Suspense>
    </AuthGuard>
  );
}
```

with `import { Suspense } from "react";` (and change the `import type * as React` line to keep the `React.ReactNode` type).

- [ ] **Step 6: Run the tests to verify they pass**

`pnpm vitest run src/components/features/promotion/letter-documents.test.tsx`, then `pnpm vitest run src/components/features/promotion src/lib/promotion`, `pnpm typecheck`, `pnpm lint`. Expected: PASS. Also run the document test once with `TZ=America/New_York pnpm vitest run src/components/features/promotion/letter-documents.test.tsx`: the dates must not shift a day.

- [ ] **Step 7: Commit (web repo)**

```bash
git add src/components/features/promotion/letter-print.tsx src/components/features/promotion/class-letter-document.tsx src/components/features/promotion/certificate-document.tsx src/components/features/promotion/letter-documents.test.tsx "src/app/promotion/[runId]/print"
git commit -m "feat(web): print promotion letters and graduation certificates"
```

---

### Task 10: Final gate, contract docs, branches (controller)

**Files:**
- Modify (parent): `docs/internal/11_integration_contracts/apis/billing-service-api.md` (School profile ~154–215)
- Create (parent): `docs/internal/11_integration_contracts/events/tenant.school_profile_updated.md`
- Modify (parent): `docs/internal/11_integration_contracts/events/academic-year-created.md` (Consumers: academic-ops now projects `name`)
- Modify (parent): `docs/internal/11_integration_contracts/apis/promotion-service-api.md` (new "Letters" section)
- Modify (parent): `docs/internal/10_data_design/02_Billing_Service_ERD.md` (principal paragraph ~66–71)
- Modify (parent): `docs/internal/10_data_design/07_Promotion_Service_ERD.md` (letter tables)
- Modify (parent): `apps/backend`, `apps/web` submodule pointers

**Interfaces:** none new. This task proves the branch and records the contract.

- [ ] **Step 1: Whole-branch review** — one reviewer over backend `develop..feat/promotion-letters` and web `develop..feat/promotion-letters` against the spec and this plan; one fix wave if needed, then a scoped re-review.

- [ ] **Step 2: Backend full suites, once, one service at a time** (`apps/backend/CONVENTIONS.md` §7.1):

```bash
cargo test -p billing-service
cargo test -p academic-ops-service --lib
cargo test -p academic-ops-service --test integration -- --test-threads=2
cargo clippy --workspace --all-targets
```

Known pre-existing failures (`docs/superpowers/backlog.md`): academic-ops `import_valid_sheet_and_bad_sheet_rolls_back`, `photo_upload_validates_type_and_size_and_sets_photo_url`. Any `WaitContainer(StartupTimeout)` counts only after the test passes re-run alone (`--exact --test-threads=1`). Remove leftover test containers afterwards.

- [ ] **Step 3: Web full checks, once**

```bash
pnpm typecheck
pnpm lint
pnpm test
pnpm build
```

Expected: all pass except the 7 pre-existing lint errors in files this plan does not touch. Restore `next-env.d.ts` if `pnpm build` rewrites it (`git checkout -- next-env.d.ts`).

- [ ] **Step 4: Dev database** — apply billing `V5` and academic-ops `V20` to the dev DB (`docker compose exec -T postgres psql -U akademiq -d akademiq`, schemas `billing` and `academic_ops`; refinery history is behind in dev, apply the SQL by hand as with V16–V19), then run `apps/backend/scripts/bootstrap-projections.sh` so `known_school_profile` and `known_academic_year.name` are filled.

- [ ] **Step 5: Contract docs** — document, from the code:
  - `billing-service-api.md`: `principal_name`, `principal_nip` in GET/PATCH (absent/null/blank semantics, length limits and messages); PATCH and logo upload/delete publish `tenant.school_profile_updated`.
  - New `events/tenant.school_profile_updated.md`: envelope, payload table (every field, nullability, `logo_url` as resolved serve path, `updated_at` as ordering key), routing, consumer academic-ops, newer-wins rule.
  - `academic-year-created.md`: academic-ops projects `name`; renames are not propagated.
  - `promotion-service-api.md` "Letters": six endpoints with request/response shapes, permission per endpoint, executed-only 409, 404 rules, the validation table (Task 3/4 messages verbatim), snapshot vs live fields.
  - ERDs: billing principal columns (replace the "deferred" note); promotion ERD `promotion_class_letter`, `graduation_record` letter columns, `known_school_profile`.

- [ ] **Step 6: Submodule bump and branches**
  - Parent: commit the docs, then bump both submodule pointers in one commit: `chore: bump backend and web to promotion letters`.
  - Never push without the user's go-ahead; `main` is not touched.

---

## Self-Review

**Spec coverage**

| Spec | Task |
|---|---|
| §2.1 billing principal fields, PATCH semantics, web form | 1, 5 |
| §2.2 event and payload, published on PATCH + logo | 1 |
| §2.3 `known_school_profile`, newer-wins, `known_academic_year.name`, bootstrap | 2 |
| §2.4 print pages read only academic-ops | 3, 4 (letterhead + year names in print data), 9 (one call per page) |
| §2.5 no principal → 400 `principal` | 3, 4 |
| §3.1 V20 tables and indexes | 2 |
| §3.2 six endpoints, permissions, executed-only, source homeroom 404, city default | 3, 4 |
| §3.3 validation table, 23505 mapping | 3, 4 (+ deviations table) |
| §4.1 Surat tab, principal card, refresh confirm, SK section, certificates section, pattern, draft, duplicates, row errors | 7, 8 |
| §4.2 two print documents, letterhead, signature, repeated `thead`, no empty NIP | 9 |
| §4.3 error copy | 5 (labels, `letterNumberMessage`), 7, 8 |
| §5 tests | 1–9 |
| §6 contract docs | 10 |

**Placeholder scan:** no TBD/TODO. `{/* CERTIFICATES_SECTION */}` in Task 7 is an edit anchor Task 8 replaces.

**Type consistency:** `KnownSchoolProfile` (Task 2) is the `letterhead` / `school_profile` JSON and matches `Letterhead` (Task 5). `ClassLetter` Rust (Task 3) ↔ TS (Task 5) field-for-field. `Certificate` Rust (Task 4) ↔ TS (Task 5) field-for-field, consumed by Tasks 6, 8, 9. `LetterSnapshot`, `check_number`, `snapshot_of`, `resolve_city`, `push_error`, `executed_status_error`, `NO_PRINCIPAL`, `NUMBER_TAKEN`, `executed_run` defined in Task 3 and used by Task 4. `ProjectionConsumer::new` gains its last argument in Task 2 for every caller. `CertificateDraft`, `effectiveNumber`, `certificateChanges`, `duplicateNumbers`, `mapStudentErrors`, `buildCertificateNumbers`, `orderGraduates` (Task 6) used by Task 8; `formatLetterDate` (Task 6) used by Tasks 7, 8, 9 for every DATE shown. `useIssueClassLetter` body `{homeroomId, letter_number, letter_date, city}` matches Task 7's call; `useIssueCertificates` body matches Task 8's call.

**Review Focus:** each of the five lines has a named test in its owning task (Tasks 2, 3, 4, 6).
