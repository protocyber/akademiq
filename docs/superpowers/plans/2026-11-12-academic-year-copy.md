# Academic Year Copy Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin copies a school's yearly setup (terms, grade levels, classes, curriculum, passing score, report types, weights, optionally homeroom teachers / assignments / timetable) from any source year into a Draft year through a resumable wizard.

**Architecture:** One idempotent `POST …/academic-years/copy` endpoint per service (academic-config → academic-ops → grading), each one transaction, skip-existing by natural key, with a `dry_run` mode. academic-config owns an `academic_year_copy_run` record and returns a source→target id map that the web forwards to the next two services. The web wizard (full page, side step list) drives the order and resumes interrupted runs from a banner.

**Tech Stack:** Rust (Axum 0.7, SQLx 0.8, refinery, lapin), PostgreSQL 18, RabbitMQ; Next.js 16 / React 19, TanStack Query 5, React Hook Form 7 + Zod 3, shadcn/ui, Vitest 2.

**Spec:** `docs/superpowers/specs/2026-11-12-academic-year-copy-design.md`

## Global Constraints

- Branch `feat/academic-year-copy` from `develop` in the parent repo, `apps/backend` and `apps/web`. No commit on `develop`/`main`.
- Backend rules: `apps/backend/CONVENTIONS.md`. Every query filters by `tenant_id`, including every JOIN. `tenant_id` comes from the JWT only. Never edit an applied migration.
- Backend test cadence (§7.1): per task `cargo check --workspace` plus that task's new tests by exact name, `-- --test-threads=4`. Full suites run once, in Task 9, one service at a time. Build with `RUSTFLAGS="-Clink-arg=-fuse-ld=mold"`.
- RED must be a real failing assertion or a 404/405 from a missing route. "0 tests matched" is not RED. After adding a migration, `touch services/<svc>/src/lib.rs` so `embed_migrations!` picks it up.
- Web rules: `apps/web/CONVENTIONS.md`. shadcn/ui only; data only through TanStack hooks in `src/lib/query/**`; error copy through `getErrorMessage` / `src/lib/errors/messages.ts`.
- User-facing copy is Bahasa Indonesia; code, comments, commit messages English, no trailers.
- Item keys (wire format, exact): `terms`, `grade_levels`, `classes`, `homeroom_teachers`, `curriculum`, `grading_policy`, `report_types`, `evaluation_weights`, `teaching_assignments`, `timetable`.
- Owners: academic-config `terms grade_levels classes(class templates) curriculum grading_policy`; academic-ops `classes(homerooms) homeroom_teachers teaching_assignments timetable`; grading `report_types evaluation_weights`. An endpoint ignores items it does not own.
- Permission on every new endpoint: role `tenant_admin` **and** permission `academic.config.write` (spec C3); otherwise 403 `FORBIDDEN`.
- New error codes (exact): `ACADEMIC_YEAR_NOT_DRAFT` (409), `COPY_DEPENDENCY_NOT_READY` (409), `COPY_RUN_IN_PROGRESS` (409), `COPY_RUN_NOT_IN_PROGRESS` (409), `ACADEMIC_YEAR_NOT_ACTIVE` (409). Same-year / unknown year → `VALIDATION_ERROR`.
- Per-item result shape (exact): `{ "item", "source", "target_existing", "copied", "skipped" }`. With `dry_run: true` nothing is written; `copied`/`skipped` are what a real run would do (ops/grading without `id_map`: `copied` = `source`, `skipped` = 0).
- Copied rows emit the same events, with the same payloads, as the manual create endpoints.
- Migration: academic-config `V10__academic_year_copy_run.sql`. No migrations in academic-ops or grading.

## Review Focus

1. Running the same copy twice copies nothing the second time and reports every row as skipped, and the second run's id map still points at the first run's rows (Task 3 `copy_twice_skips_everything_and_maps_existing`, Task 4 `ops_copy_is_idempotent`, Task 5 `grading_copy_is_idempotent`).
2. A failure in the middle of one service step leaves that service's target untouched — e.g. a shifted term overlapping an existing target term rolls back grade levels copied in the same call (Task 3 `copy_rolls_back_when_a_term_overlaps`).
3. Copying into an `Active` target, or with source = target, is refused before anything is written, in all three services (Task 3 `copy_rejects_non_draft_target`, Task 4 `ops_copy_rejects_non_draft_target`, Task 5 `grading_copy_rejects_non_draft_target`).
4. An archived or deleted teacher never comes across as wali kelas or in an assignment (Task 4 `ops_copy_skips_archived_teachers`).
5. A source term ending 29 February shifted into a non-leap year lands on 28 February, not an error (Task 6 test "clamps 29 February").

## Deviations and notes decided while planning

| Spec | Plan | Why |
|---|---|---|
| §4 "enrolling requires an Active year" | `enroll_student`, transfer and the initial placement in `create_student` check `Active`. **Promotion execution is unchanged**: it still accepts a Draft or Active target year (3c rule `target academic year must not be Closed or Archived`) | Promotion has its own target-year rule from spec 3c; changing it is outside this feature. Flagged for the maintainer |
| §2 counts | Result shape gains `source` and `target_existing` | Step 3 needs the source count and whether the target already holds an item (dependency locking) |
| §6 who creates the run | `POST …/copy-runs` stores `items`, `term_dates`, source; the config copy call must reference an `in_progress` run of the same target unless `dry_run` | Keeps `config_result` + `id_map` written in the same transaction as the copy |
| §3 subject group / curriculum copy | Copying a curriculum version does **not** create the automatic default group; the source's groups are copied instead | Otherwise every copy adds a stray default group |
| §3 grade level conflicts | A new grade-level code whose ordinal (or `is_final`) collides with a different target level fails the whole call with the existing manual error | Same rule as manual creation; nothing half-applied |

---

### Task 1: academic-ops — classes in Draft years, enrolment only in Active years

**Files:**
- Modify: `apps/backend/services/academic-ops-service/src/repo.rs` (`KnownYearRepo`, near `is_active` :841)
- Modify: `apps/backend/services/academic-ops-service/src/commands.rs` (`create_homeroom` :824, `enroll_student` :977, transfer at :1025–1045, initial placement :405–425)
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Produces: `KnownYearRepo::status(&self, tenant_id: Uuid, year_id: Uuid) -> sqlx::Result<Option<String>>` (used again in Task 4).

- [ ] **Step 1: Update the existing test and write the failing ones**

Rename `homeroom_requires_known_active_year` to `homeroom_requires_known_draft_or_active_year`: unknown year → 400 `UNKNOWN_ACADEMIC_YEAR` (unchanged); `seed_year(.., "Draft")` → 201; `seed_year(.., "Closed")` → 400 `UNKNOWN_ACADEMIC_YEAR`.

New `enroll_requires_active_year`: homeroom created in a Draft year, POST enrollment for a new student → 409 `ACADEMIC_YEAR_NOT_ACTIVE`, message `academic year must be Active to enroll students`; after `UPDATE known_academic_year SET status='Active'` the same request → 201.

New `create_student_initial_placement_requires_active_year`: create student with `initial_placement` into the Draft-year homeroom → 409 `ACADEMIC_YEAR_NOT_ACTIVE`, and no student row is created.

- [ ] **Step 2: Run to verify they fail**

Run: `cargo test -p academic-ops-service --test integration -- homeroom_requires_known_draft_or_active_year enroll_requires_active_year create_student_initial_placement_requires_active_year --test-threads=4`
Expected: FAIL (Draft homeroom returns 400).

- [ ] **Step 3: Implement**

Add `KnownYearRepo::status`. `create_homeroom` accepts `Some("Draft" | "Active")`, otherwise the existing `UNKNOWN_ACADEMIC_YEAR` error (update its message to `academic year is unknown, closed or archived`). Add `fn require_active_year(state, tenant_id, year_id) -> Result<(), AppError>` returning `AppError::conflict("ACADEMIC_YEAR_NOT_ACTIVE", "academic year must be Active to enroll students")`, called by `enroll_student`, the transfer command and the initial-placement path before any insert. Leave `promotion/*` untouched.

- [ ] **Step 4: Run to verify they pass** — same command, expected PASS. Then `cargo check --workspace`.

- [ ] **Step 5: Commit** — `fix(academic-ops): allow classes in Draft years; enrol only in Active years`

---

### Task 2: academic-config — copy run record and endpoints

**Files:**
- Create: `apps/backend/services/academic-config-service/migrations/V10__academic_year_copy_run.sql`
- Create: `apps/backend/services/academic-config-service/src/year_copy.rs` (copy-run commands/queries + Task 3 copy command; `pub mod year_copy;` in `lib.rs`)
- Modify: `apps/backend/services/academic-config-service/src/http.rs` (routes + handlers)
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Produces: `CopyItem` enum (serde `snake_case`, the ten keys) in `year_copy.rs`; `CopyRun { copy_run_id, source_academic_year_id, target_academic_year_id, items: Vec<CopyItem>, term_dates: Option<Value>, status: String, id_map: Option<Value>, config_result: Option<Value>, ops_result: Option<Value>, grading_result: Option<Value>, created_at, updated_at }` serialized as-is.
- Routes: `POST /api/v1/academic-config/academic-years/:academic_year_id/copy-runs` (201, body `{source_academic_year_id, items, term_dates?}`), `GET /api/v1/academic-config/academic-years/:academic_year_id/copy-runs/current` (200 or 404), `PATCH /api/v1/academic-config/copy-runs/:copy_run_id` (body `{step: "ops"|"grading", result: [...]}` or `{status: "completed"|"cancelled"}`).

- [ ] **Step 1: Migration**

Table per spec §6 plus `id_map JSONB`; `status VARCHAR(16) NOT NULL CHECK (status IN ('in_progress','completed','cancelled'))`; `items TEXT[] NOT NULL`; FKs to `academic_year` for both years; partial unique index `academic_year_copy_run_one_in_progress_idx ON (tenant_id, target_academic_year_id) WHERE status='in_progress'`; index on `(tenant_id, target_academic_year_id, created_at DESC)`.

- [ ] **Step 2: Write the failing tests**

`copy_run_lifecycle`: Draft target + another year as source; POST → 201 `status=in_progress`; second POST → 409 `COPY_RUN_IN_PROGRESS`; GET current → same id; PATCH `{step:"ops", result:[{item:"classes",source:6,target_existing:0,copied:6,skipped:0}]}` → 200 and `ops_result` stored; PATCH `{status:"completed"}` → GET current 404; a new POST → 201.
`copy_run_rejects_bad_input`: source = target → 400 `VALIDATION_ERROR` field `source_academic_year_id`; Active target → 409 `ACADEMIC_YEAR_NOT_DRAFT`; unknown item key → 400 `VALIDATION_ERROR` field `items`; token for role `principal` → 403.
`copy_run_is_tenant_scoped`: a run of tenant A is 404 for tenant B's GET and PATCH.
`copy_run_patch_after_completion_is_rejected`: PATCH `{step:"grading",…}` on a completed run → 409 `COPY_RUN_NOT_IN_PROGRESS`.

- [ ] **Step 3: Run to verify they fail** — `cargo test -p academic-config-service --test integration -- copy_run_ --test-threads=4`; expected 404/405 from missing routes.

- [ ] **Step 4: Implement** the three commands and handlers. Permission helper `fn require_year_copy(auth: &AuthContext) -> Result<(), AppError>` = `auth.has_role("tenant_admin")` (else 403 `FORBIDDEN`) + `require_academic_config_write`. A PATCH on a run that is not `in_progress` → `AppError::conflict("COPY_RUN_NOT_IN_PROGRESS", "copy run is not in progress")`.

- [ ] **Step 5: Run to verify they pass**, `cargo check --workspace`.

- [ ] **Step 6: Commit** — `feat(academic-config): record academic year copy runs`

---

### Task 3: academic-config — copy endpoint

**Files:**
- Modify: `apps/backend/services/academic-config-service/src/year_copy.rs`, `src/http.rs`, `src/commands.rs` (extract event payload builders only)
- Test: `apps/backend/services/academic-config-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 2 `CopyItem`, copy-run table.
- Produces: `POST /api/v1/academic-config/academic-years/copy`, body `{source_academic_year_id, target_academic_year_id, copy_run_id?, items, term_dates?, dry_run?}` → `{data:{results:[…], id_map:{terms:{}, grade_levels:{}, subjects:{}}}}`. `copy_run_id` is required unless `dry_run`.
- Extracted (same file as today): `fn academic_term_created_payload(&AcademicTerm) -> Value`, `fn grade_level_created_payload(&GradeLevel) -> Value`, `fn grading_policy_configured_payload(&GradingPolicy) -> Value`; the existing create commands call them.

- [ ] **Step 1: Write the failing tests** (helper `seed_source_year(app, token) -> SourceFixture` builds: year 2025-2026 Closed with terms "Semester 1" 2025-07-01..2025-12-31 and "Semester 2" 2026-01-01..2026-06-30, grade levels A (ord 1) … C (ord 3, is_final), class templates for A–C capacity 30, curriculum "K13" with group code `UMUM` and subjects `MTK` "Matematika", `BIN` "Bahasa Indonesia", grading policy 70; target year 2026-2027 Draft 2026-07-01..2027-06-30 which already has its automatic "Semester 1")

`copy_dry_run_reports_counts_and_writes_nothing`: dry run with all config items → `terms {source:2,target_existing:1,copied:1,skipped:1}`, `grade_levels {3,0,3,0}`, `classes {3,0,3,0}`, `curriculum {source:2 …}` (source counts subjects), `grading_policy {1,0,1,0}`; target tables unchanged.
`copy_copies_config_and_returns_id_map`: start a run (Task 2), copy → target has "Semester 1" (existing, untouched) and "Semester 2" dated 2027-01-01..2027-06-30, levels A–C with same ordinals and `is_final` on C, templates per level, curriculum "K13" with exactly one group `UMUM` and both subjects, grading policy 70; `id_map.grade_levels` has 3 entries pointing at target ids; `id_map.terms` maps both source terms (Semester 1 → the existing target term); run's `config_result` and `id_map` stored; outbox holds 1 `academic_term.created`, 3 `grade_level.created`, 1 `grading_policy.configured`.
`copy_twice_skips_everything_and_maps_existing`: second copy (same run) → every item `copied:0`, id map equal to the first.
`copy_honours_term_date_overrides`: `term_dates` for Semester 2 = 2027-01-06..2027-06-20 → stored as given.
`copy_rolls_back_when_a_term_overlaps`: override Semester 2 to start 2026-12-01 (overlaps target Semester 1) → 400 `VALIDATION_ERROR` field `term_dates`; target has no grade levels.
`copy_rejects_non_draft_target`: Active target → 409 `ACADEMIC_YEAR_NOT_DRAFT`; dry run too.
`copy_without_run_is_rejected`: no `copy_run_id`, not dry run → 400 `VALIDATION_ERROR` field `copy_run_id`; run of another target → same.

- [ ] **Step 2: Run to verify they fail** — `cargo test -p academic-config-service --test integration -- copy_ --test-threads=4` (route missing → 404/405).

- [ ] **Step 3: Implement `pub async fn copy_year_config(state: &AppState, input: CopyYearConfig) -> Result<CopyYearConfigOutput, AppError>`**

One transaction; order terms → grade levels → class templates → curriculum (versions, groups, subjects) → grading policy. Natural keys per spec §3. Term shift: `target.start_date - source.start_date` in days, then clamp an invalid day to the month's last day (`chrono` `with_day` fallback); overrides win; each copied term runs the same checks as `create_academic_term` (inside the year, no overlap, name unique) and gets `status = Draft`. Skipped rows still go into the id map. On a real run update `academic_year_copy_run` (`config_result`, `id_map`, `updated_at`) in the same transaction. Dry run: same computation, `tx.rollback()`.

- [ ] **Step 4: Run to verify they pass**, `cargo check --workspace`.

- [ ] **Step 5: Commit** — `feat(academic-config): copy a year's setup into a Draft year`

---

### Task 4: academic-ops — copy endpoint

**Files:**
- Create: `apps/backend/services/academic-ops-service/src/year_copy.rs` (`pub mod year_copy;`)
- Modify: `apps/backend/services/academic-ops-service/src/http.rs`
- Test: `apps/backend/services/academic-ops-service/tests/integration.rs`

**Interfaces:**
- Consumes: Task 1 `KnownYearRepo::status`; id map shape from Task 3.
- Produces: `POST /api/v1/academic-ops/academic-years/copy`, body `{source_academic_year_id, target_academic_year_id, copy_run_id?, items, id_map?, dry_run?}` → `{data:{results:[…]}}`.

- [ ] **Step 1: Write the failing tests** (fixture: known years source Closed / target Draft; `seed_known_grade_level` A, B in both years; source homerooms "A1"(A, cap 30, wali T1), "B1"(B, cap 28, wali T2 archived = `status='arsip'`); assignments (T1, subj S1, A1), (T2, S1, B1); one timetable slot for A1 Mon 07:00–08:00; id map `{grade_levels:{srcA:tgtA, srcB:tgtB}, subjects:{S1:S1t}}`)

`ops_copy_copies_homerooms_and_optional_parts`: items `classes, homeroom_teachers, teaching_assignments, timetable` → target homerooms A1 (tgtA, 30, wali T1) and B1 (tgtB, 28, no wali); one assignment (T1, S1t, new A1); one timetable slot; results `classes {2,0,2,0}`, `teaching_assignments {source:2, copied:1, skipped:1}`; outbox: 2 `homeroom.created`, 1 `homeroom.updated` (wali), 1 `teacher.assigned`.
`ops_copy_default_items_leave_teachers_out`: items `classes` only → homerooms without wali, no assignments.
`ops_copy_skips_archived_teachers`: covered by the first test's B1 (no wali, its assignment skipped); assert explicitly.
`ops_copy_is_idempotent`: second call → all `copied:0`.
`ops_copy_waits_for_grade_levels`: id map points at a target grade level missing from `known_grade_level` → 409 `COPY_DEPENDENCY_NOT_READY`, nothing written.
`ops_copy_rejects_non_draft_target`: target Active → 409 `ACADEMIC_YEAR_NOT_DRAFT`.
`ops_copy_dry_run_without_map`: dry run, no id map → `classes {source:2, target_existing:0, copied:2, skipped:0}`, nothing written.

- [ ] **Step 2: Run to verify they fail** — `cargo test -p academic-ops-service --test integration -- ops_copy_ --test-threads=4`.

- [ ] **Step 3: Implement `pub async fn copy_year_ops(state: &AppState, input: CopyYearOps) -> Result<Vec<CopyItemResult>, AppError>`**

One transaction. Homerooms keyed by `name` in the target year; `grade_level` text and `grade_level_id` from the mapped `known_grade_level`. Wali only with `homeroom_teachers` and only if the teacher is `status='aktif' AND NOT deleted`. Assignments keyed by the existing unique tuple; skip when subject has no mapping, homeroom has no target, or the teacher is not active. Timetable keyed by (target homeroom, day, start_time); copied only for assignments that exist in the target after this call. Events via the existing `state.outbox.enqueue` with the payloads of `create_homeroom`, `update_homeroom`, `assign_teaching`.

- [ ] **Step 4: Run to verify they pass**, `cargo check --workspace`.

- [ ] **Step 5: Commit** — `feat(academic-ops): copy classes, homeroom teachers and assignments between years`

---

### Task 5: grading — copy endpoint

**Files:**
- Create: `apps/backend/services/grading-service/src/year_copy.rs` (`pub mod year_copy;`)
- Modify: `apps/backend/services/grading-service/src/http.rs`
- Test: `apps/backend/services/grading-service/tests/integration.rs`

**Interfaces:**
- Consumes: id map `terms`.
- Produces: `POST /api/v1/grading/academic-years/copy`, same body shape → `{data:{results:[…]}}`.

- [ ] **Step 1: Write the failing tests** (fixture with `seed_year_for_report_types` / `seed_term`: source year Closed with term S2; target year Draft (`valid_year`) with term T2 in `valid_term`; source report type `SAS` "Rapor SAS" `is_promotion_source = true` on S2; evaluation templates `UH` and `PAS` on S2; formula template weights SAS×UH 40, SAS×PAS 60)

`grading_copy_copies_report_types_and_weights`: items `report_types, evaluation_weights`, id map `{terms:{S2:T2}}` → T2 has `SAS` with `is_promotion_source = true`, templates `UH`, `PAS`, weights 40/60; results `report_types {1,0,1,0}`, `evaluation_weights {source:4 …}` (2 templates + 2 weights); outbox has one `report_type.promotion_source_changed` for the new type.
`grading_copy_without_weights`: items `report_types` → no templates, no weights.
`grading_copy_is_idempotent`: second call → all `copied:0`.
`grading_copy_waits_for_terms`: id map target term not in `valid_term` → 409 `COPY_DEPENDENCY_NOT_READY`.
`grading_copy_rejects_non_draft_target`: `valid_year` Active → 409 `ACADEMIC_YEAR_NOT_DRAFT`.

- [ ] **Step 2: Run to verify they fail** — `cargo test -p grading-service --test integration -- grading_copy_ --test-threads=4`.

- [ ] **Step 3: Implement `pub async fn copy_year_grading(state: &AppState, input: CopyYearGrading) -> Result<Vec<CopyItemResult>, AppError>`**

One transaction. Report types keyed by (target term, `code`), positions appended after existing ones as `copy_report_types` does; evaluation templates keyed by (target term, `code`); weights keyed by (mapped report type, mapped template), skipped when either side was not copied or mapped. Permission: existing `require_admin` + `require_academic_config_write`.

- [ ] **Step 4: Run to verify they pass**, `cargo check --workspace`.

- [ ] **Step 5: Commit** — `feat(grading): copy report types and evaluation weights between years`

---

### Task 6: web — copy hooks and pure wizard logic

**Files:**
- Create: `apps/web/src/lib/query/mutations/use-year-copy.ts`, `apps/web/src/lib/query/queries/use-year-copy.ts`
- Create: `apps/web/src/components/features/academic-config/year-copy/checklist.ts` (+ `checklist.test.ts`)
- Create: `apps/web/src/components/features/academic-config/year-copy/run-copy.ts` (+ `run-copy.test.ts`)
- Modify: `apps/web/src/lib/errors/messages.ts`

**Interfaces:**
- Produces:
  - `type CopyItem` (the ten keys); `type CopyItemResult = { item: CopyItem; source: number; target_existing: number; copied: number; skipped: number }`; `type CopyRun` (Task 2 shape).
  - `useCurrentCopyRun(targetYearId?: string)`; mutations `useStartCopyRun(targetYearId)`, `useUpdateCopyRun()`, and plain fetchers `copyConfig`, `copyOps`, `copyGrading` (each `(body) => Promise<…>`).
  - `DEFAULT_ITEMS: CopyItem[]` = `terms, grade_levels, classes, curriculum, grading_policy, report_types, evaluation_weights`.
  - `resolveChecklist(selected: Set<CopyItem>, targetHas: Partial<Record<CopyItem, boolean>>): { item: CopyItem; checked: boolean; disabled: boolean; reason?: string }[]` — dependencies per spec §2.
  - `shiftTermDates(sourceYearStart: string, targetYearStart: string, terms: {term_id; name; start_date; end_date}[]): {source_term_id; name; start_date; end_date}[]`.
  - `runCopy(run: CopyRun, deps: { copyConfig; copyOps; copyGrading; updateRun; sleep }, onProgress: (step: "config"|"ops"|"grading", state: "running"|"done"|"waiting"|"error", result?) => void): Promise<void>` — skips steps whose result is already on the run; retries `COPY_DEPENDENCY_NOT_READY` with delays 1, 2, 4, 8, 15, 30 s, then reports `error`; marks the run `completed` after grading.

- [ ] **Step 1: Write the failing tests**

`checklist.test.ts`: "defaults leave teachers out" (`homeroom_teachers`, `teaching_assignments`, `timetable` unchecked); "unchecking classes disables homeroom teachers and assignments with a reason" (`reason` = `Butuh Kelas`); "existing target classes keep assignments enabled"; "timetable needs assignments" (`Butuh Penugasan guru`); "evaluation weights need report types".
`shiftTermDates`: "shifts by the year offset" (2025-07-01 → 2026-07-01: 2026-01-01..2026-06-30 → 2027-01-01..2027-06-30); "clamps 29 February" (source year start 2023-07-01, term end 2024-02-29, target start 2024-07-01 → 2025-02-28).
`run-copy.test.ts`: "runs config, ops, grading in order and completes"; "resumes after the config step" (run with `config_result` set → `copyConfig` not called, `id_map` from the run passed to ops); "retries not-ready then succeeds" (ops rejects once with `COPY_DEPENDENCY_NOT_READY`, `sleep` called with 1000); "stops on another error" (no `updateRun({status:"completed"})`).

- [ ] **Step 2: Run to verify they fail** — `cd apps/web && npx vitest run src/components/features/academic-config/year-copy` (module not found).

- [ ] **Step 3: Implement** hooks (query key `["academic-config","copy-run",targetYearId]`; invalidate it and the academic-years / terms / grade-levels / class-templates / curriculum keys after a run), the two pure modules and the messages: `ACADEMIC_YEAR_NOT_DRAFT: "Penyalinan hanya bisa ke tahun ajaran berstatus Draft."`, `COPY_DEPENDENCY_NOT_READY: "Data dari langkah sebelumnya belum sampai. Coba lagi sebentar lagi."`, `COPY_RUN_IN_PROGRESS: "Masih ada penyalinan yang belum selesai untuk tahun ini. Lanjutkan atau batalkan dulu."`, `COPY_RUN_NOT_IN_PROGRESS: "Penyalinan ini sudah selesai atau dibatalkan."`, `ACADEMIC_YEAR_NOT_ACTIVE: "Siswa hanya bisa didaftarkan ke kelas pada tahun ajaran Aktif."`.

- [ ] **Step 4: Run to verify they pass**, plus `npx tsc --noEmit`.

- [ ] **Step 5: Commit** — `feat(web): year copy hooks, checklist rules and copy runner`

---

### Task 7: web — wizard page

**Files:**
- Create: `apps/web/src/app/settings/academic/years/copy/page.tsx`, `apps/web/src/app/settings/academic/years/[yearId]/copy/page.tsx`
- Create: `apps/web/src/components/features/academic-config/year-copy/year-copy-wizard.tsx` (+ `year-copy-wizard.test.tsx`) and one file per step: `step-identity.tsx`, `step-source.tsx`, `step-items.tsx`, `step-term-dates.tsx`, `step-summary.tsx`

**Interfaces:**
- Consumes: Task 6 hooks and modules; existing `useAcademicYears`, `useTerms`, `useCreateAcademicYear`, academic-year Zod schema.
- Produces: `<YearCopyWizard targetYearId?: string; resumeRun?: CopyRun />`.

- [ ] **Step 1: Write the failing tests** (`year-copy-wizard.test.tsx`, hooks mocked like `execute-dialog.test.tsx`)

"new year starts at Identitas tahun and lists five steps"; "existing Draft year starts at Tahun sumber"; "source defaults to the most recent other year"; "Mulai kosong finishes after creating the year" (no copy calls); "step 3 shows source counts from the dry runs"; "term dates step is skipped when Semester is unchecked"; "resume opens Ringkasan and runs only the remaining parts".

- [ ] **Step 2: Run to verify they fail** — `npx vitest run src/components/features/academic-config/year-copy/year-copy-wizard.test.tsx`.

- [ ] **Step 3: Implement**

Layout B: left column = step list (`Identitas tahun`, `Tahun sumber`, `Data yang disalin`, `Tanggal semester`, `Ringkasan`) with done / current state and "Tujuan: … (Draft) · Sumber: …" under it; right column = step content; footer `← Kembali` / `Lanjut →`. Step 1 uses the existing academic-year form schema and creates the year on `Lanjut`. Step 3 calls the three endpoints with `dry_run: true` (ops/grading without `id_map`) and groups rows as in the mockup (Struktur sekolah, Kurikulum, Rapor, Penugasan), showing `source` as the count. Step 5 lists what will be created; `Mulai salin` → `useStartCopyRun` then `runCopy`, rendering per part `Menyalin…`, `Menunggu data…`, `X disalin, Y dilewati`, or the error with `Coba lagi`; on success a link back to the year.

- [ ] **Step 4: Run to verify they pass**, `npx tsc --noEmit`, `npm run lint`.

- [ ] **Step 5: Commit** — `feat(web): academic year copy wizard`

---

### Task 8: web — entry points and resume banner, docs

**Files:**
- Modify: `apps/web/src/app/settings/academic/years/page.tsx` (create button :159, row menu :344)
- Create: `apps/web/src/components/features/academic-config/year-copy/resume-banner.tsx` (+ `resume-banner.test.tsx`)
- Modify docs: `docs/internal/08_sequences/02_Academic_Year_Initialization.md`, `docs/internal/11_integration_contracts/apis/academic-config-api.md`, `…/academic-operations-api.md`, `…/grading-service-api.md`, `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`, `docs/superpowers/backlog.md`, `docs/manual-tests/2026-11-06-promotion-manual-test.html` (T3/T4 may use the wizard)

**Interfaces:**
- Consumes: Task 6 `useCurrentCopyRun`, `useUpdateCopyRun`; Task 7 routes.
- Produces: `<CopyRunResumeBanner targetYearId: string; targetYearName: string />`.

- [ ] **Step 1: Write the failing tests** — "shows source and parts done" (`Penyalinan dari 2025-2026 belum selesai (1 dari 3 bagian)`); "Lanjutkan links to the year's copy page"; "Batalkan cancels the run" (`updateRun({status:"cancelled"})`); "renders nothing without a run".

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** — "Tahun ajaran baru" navigates to `/settings/academic/years/copy` (the old modal stays reachable only through the wizard's step 1); Draft rows get "Salin dari tahun lain" → `/settings/academic/years/<id>/copy`; the banner renders above the table for every Draft year with a current run (one query per Draft year shown). Docs: replace the placeholder sequence with the web-orchestrated flow (Mermaid), document the five endpoints and the error codes, add the table to the ERD, close the backlog entry "target year forces closing the source year first", add the backlog item "academic-ops `create_homeroom` / teaching-assignment writes check no permission".

- [ ] **Step 4: Run to verify they pass**, `npx tsc --noEmit`, `npm run lint`, `npx vitest run src/components/features/academic-config`.

- [ ] **Step 5: Commit** — web `feat(web): open the copy wizard from the years page and resume runs`; parent `docs: academic year copy contracts, sequence and backlog`

---

### Task 9: Final gate

- [ ] **Step 1:** Full suites one at a time: `cargo test -p academic-config-service -- --test-threads=4`, then `academic-ops-service`, then `grading-service`. Judge failures by name against recorded pre-existing failures.
- [ ] **Step 2:** `cd apps/web && npx vitest run && npx tsc --noEmit && npm run lint`.
- [ ] **Step 3:** Manual check on the dev stack with the TPQ tenant: move 2026-2027 back to Draft (if allowed), run the wizard from 2025-2026 with defaults, close the tab after the config part, reopen, resume from the banner, confirm counts. Record the result.
- [ ] **Step 4:** Bump submodules in the parent (`chore: bump backend and web to academic year copy`).
