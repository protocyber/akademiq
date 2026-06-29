## 1. Backend — academic-config-service domain & constants

- [x] 1.1 Add `TermStatus` type in `services/academic-config-service/src/domain.rs` reusing the 4 variants (`Draft`, `Active`, `Closed`, `Archived`) with `as_str`/`from_str`/`default`/`can_transition_to` mirroring `YearStatus` (same matrix: `Draft↔Active`, `Active↔Closed`, `Closed→Archived`; reject skips, out-of-`Archived`, no-op).
- [x] 1.2 Add `AcademicTerm` struct (`term_id`, `academic_year_id`, `tenant_id`, `name`, `start_date`, `end_date`, `status: TermStatus`, timestamps).
- [x] 1.3 Add `pub const DEFAULT_TERM_NAME: &str = "Semester 1";` in `domain.rs`.
- [x] 1.4 Unit tests for `TermStatus::can_transition_to` (forward, backward, skips, out-of-`Archived`, no-op).

## 2. Backend — academic-config-service repo & migration

- [x] 2.1 Create migration `V4__academic_term.sql`: `academic_term` table (PK/FK cascade, `tenant_id`, `name`, dates, `status` default `Draft`, `CHECK(start_date <= end_date)`, `CHECK(status IN (...))`, `UNIQUE(tenant_id, academic_year_id, name)`); partial unique index `academic_term_one_active_per_year_idx ON academic_term (academic_year_id) WHERE status = 'Active'`; `academic_term_status_transition` table (same shape as `academic_year_status_transition`).
- [x] 2.2 In the same migration, idempotently seed one `"Semester 1"` term per existing `academic_year` (copy `start_date`/`end_date`/`status` from the year), guarded by `WHERE NOT EXISTS`.
- [x] 2.3 Add `AcademicTermRepo` to `repo.rs`: `insert`, `find_by_id`, `list_for_year` (paginated, like `AcademicYearRepo::list`), `update` (name/dates), `delete`, `update_status`, `active_exists_except` (per year), `insert_transition`, `count_active_terms_for_year`, plus an `overlaps` helper for date-range overlap checks.
- [x] 2.4 Verify migration is idempotent (re-run is a no-op once seeded).

## 3. Backend — academic-config-service commands

- [x] 3.1 Extend `create_academic_year` (`commands.rs:32`) to insert, in the same transaction, a default term (`name = DEFAULT_TERM_NAME`, year's dates, `Draft`) and enqueue `academic_term.created` alongside `academic_year.created`.
- [x] 3.2 Add `create_academic_term`: validate name/dates, fetch parent year, enforce `start_date >= year.start_date`, `end_date <= year.end_date`, no overlap with existing terms in the year (`TERM_OVERLAP`), enforce name uniqueness (`TERM_NAME_EXISTS`), insert + enqueue `academic_term.created`.
- [x] 3.3 Add `update_academic_term` (name/dates) with the same range/overlap checks; reject if term status is `Archived`.
- [x] 3.4 Add `transition_term_status`: parse target, enforce transition matrix (`INVALID_STATE_TRANSITION`), enforce one-`Active`-term-per-year (`ACTIVE_TERM_EXISTS`), persist reason (min 10 chars) to `academic_term_status_transition`, enqueue `academic_term.status_changed`.
- [x] 3.5 Add `delete_academic_term`: reject if status is `Active`/`Archived` (`TERM_NOT_DELETABLE`); (grading-side `TERM_IN_USE` is enforced by the grading DB — coordinate via projection/usage query if a cross-DB usage signal is available, otherwise rely on grading rejecting dependent deletes).
- [x] 3.6 Extend `transition_year_status` (`commands.rs:99`) to reject `→ Closed` when `count_active_terms_for_year > 0` (`TERM_STILL_ACTIVE`, HTTP 409). No new check on `→ Active`.

## 4. Backend — academic-config-service HTTP

- [x] 4.1 Add routes in `http.rs`: `GET /academic-years/{year_id}/terms` (list, paginated), `POST /academic-years/{year_id}/terms` (create), `GET|PATCH|DELETE /academic-terms/{id}`, `PATCH /academic-terms/{id}/status` (`{ status, reason }`). Gate GETs on `academic.config.read` and writes on `academic.config.write` (coordinate with `rbac-read-and-menu-restructure`).
- [x] 4.2 Return `VALIDATION_ERROR` field errors for name/dates; map repo/usage errors to `TERM_OVERLAP`/`TERM_NAME_EXISTS`/`ACTIVE_TERM_EXISTS`/`TERM_STILL_ACTIVE`/`INVALID_STATE_TRANSITION`/`TERM_NOT_DELETABLE`.

## 5. Backend — academic-config-service tests

- [x] 5.1 Integration tests: create year ⇒ default term exists; create term within/ outside range; overlap rejection; duplicate name rejection; forward/backward term transitions with reason; one-active-term-per-year; year `→ Closed` rejected with an active term.
- [x] 5.2 Tests assert both `academic_term.created` and `academic_term.status_changed` events are emitted with the documented payload.

## 6. Backend — grading-service migration & projection

- [x] 6.1 Create migration `V7__term_rework.sql`: `ALTER TABLE evaluation ADD COLUMN term_id UUID` (nullable); `ALTER TABLE report_type ADD COLUMN term_id UUID` (nullable); backfill each row using a deterministic placeholder `md5(academic_year_id::text)::uuid` (grading-service has no academic-term table to join at migration time; V8 seeds `valid_term` with the same hash; real `term_id`s arrive via `academic_term.created` events from academic-config-service); `ALTER TABLE ... SET NOT NULL`; `DROP CONSTRAINT evaluation_scope_code_unique` and `report_type_year_code_unique`; add `evaluation_scope_term_code_unique (tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` and `report_type_term_code_unique (academic_year_id, term_id, code)`. Dev-reset acceptable per `V4`/`V5` precedent.
- [x] 6.2 Create migration `V8__valid_term_projection.sql`: `valid_term` table mirroring `valid_year` (`term_id`, `tenant_id`, `academic_year_id`, `status`, `updated_at`).
- [x] 6.3 Add `valid_term` projection access on `ProjectionRepo` (`upsert_valid_term`, `get_valid_term_status`), mirroring the existing `valid_year` design (no dedicated `ValidTermRepo` struct or `ValidTerm` row mapper — both projections share `ProjectionRepo` per the service convention).

## 7. Backend — grading-service events & domain

- [x] 7.1 In `events.rs`, bind `academic_term.created` and `academic_term.status_changed`; idempotently upsert `valid_term`.
- [x] 7.2 Add `term_id` to `Evaluation` and `ReportType` in `domain.rs` and update their row mappers, insert queries, and list queries. `update_evaluation` and `update_report_type` intentionally do not mutate `term_id` — re-scoping after creation is unsafe (it could move grades into a Closed term or break `EVALUATION_TERM_MISMATCH` invariants on existing formulas); `term_id` is fixed at creation.

## 8. Backend — grading-service gates

- [x] 8.1 Evaluation create/update command: resolve `valid_term.status` for the evaluation's `term_id`; reject with `TERM_NOT_EDITABLE` (HTTP 409) unless status is `Draft` or `Active`.
- [x] 8.2 Grade-record command: additionally resolve the term status via the evaluation's `term_id` and reject with `TERM_NOT_ACTIVE` (HTTP 409) unless `Active` (keep the existing year-`Active` `YEAR_NOT_ACTIVE` gate).
- [x] 8.3 `report_formula` add command: load the report type's `term_id` and the evaluation's `term_id`; reject with `EVALUATION_TERM_MISMATCH` (HTTP 409) if they differ.
- [x] 8.4 Integration tests: cross-term formula rejected; evaluation create in `Closed` term rejected; grade entry in `Draft`/`Closed` term rejected, allowed in `Active`; `valid_term` projection upsert is idempotent.

## 9. Backend — academic-ops-service (optional projection)

- [x] 9.1 Migration `V5__known_term.sql`: `known_academic_term` table mirroring `known_academic_year`.
- [x] 9.2 Bind `academic_term.created`/`academic_term.status_changed` in `events.rs` and upsert `known_academic_term`. No changes to homeroom/enrollment/teaching (year-scoped).

## 10. Web — global scope provider

- [x] 10.1 Add `useTerms(yearId)` query hook (paginated/list) backed by `GET /academic-years/{id}/terms`.
- [x] 10.2 Extend `academic-scope-provider.tsx` with `termId` state, localStorage persistence (same tenant key, now `{academic_year_id, term_id, curriculum_version_id}`), and Context value.
- [x] 10.3 Implement default resolution: `Active` term → today-in-range term → first term; reset term when the year changes.
- [x] 10.4 Add a term `<Select>` to the header beside the year picker; disable gracefully when the year has no terms.
- [x] 10.5 Show a warning (header + management page) when the selected year is `Active` but has no `Active` term.

## 11. Web — term management UI

- [x] 11.1 Add `src/lib/schemas/academic-term.ts` Zod schemas for create/update/transition (mirror the academic-year schema incl. `reason` min 10).
- [x] 11.2 Add a term-management section/sub-page under the academic year (where report types are managed today): list, create, edit, delete.
- [x] 11.3 Wire `StatusConfirmDialog` (from `simplify-academic-year-status`) for term status transitions (type-to-confirm + cooldown for backward/`→ Archived`).
- [x] 11.4 Surface backend errors (`TERM_OVERLAP`, `TERM_NAME_EXISTS`, `ACTIVE_TERM_EXISTS`, `TERM_STILL_ACTIVE`, `TERM_NOT_EDITABLE`, `TERM_NOT_ACTIVE`, `EVALUATION_TERM_MISMATCH`, `TERM_NOT_DELETABLE`, `TERM_IN_USE`) as readable inline messages.
- [x] 11.5 Gate view on `academic.config.read` and create/edit/delete/status on `academic.config.write` (coordinate with `rbac-read-and-menu-restructure`).

## 12. Web — consume scope in grading pages

- [x] 12.1 Grade-entry and report-board pages read `termId` from the scope and pass it to the evaluation/report-type queries and mutations.
- [x] 12.2 Report-type management UI (currently inside the year form) filters/creates by the selected `termId`.

## 13. Web — tests & checks

- [x] 13.1 Playwright: term CRUD, status transition confirmation flow, header selector default resolution, warning state when no active term.
- [x] 13.2 Run web lint/typecheck and `make test` for web.

## 14. Documentation

- [x] 14.1 `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`: add `academic_term` + `academic_term_status_transition`.
- [x] 14.2 `docs/internal/10_data_design/06_Grading_Service_ERD.md`: add `term_id` to `evaluation`/`report_type`, add `valid_term` projection; refresh the stale diagram to the post-`V4`/`V5` model.
- [x] 14.3 `docs/internal/09_states/AkademiQ_State_Academic_Term_Lifecycle.md`: new 4-state machine with parent-child coordination rules.
- [x] 14.4 `docs/internal/11_integration_contracts/apis/academic-config-api.md`: term endpoints + lifecycle text.
- [x] 14.5 `docs/internal/11_integration_contracts/apis/grading-service-api.md`: `term_id` in evaluation/report-type schemas; new error codes table.
- [x] 14.6 `docs/internal/11_integration_contracts/events/academic-term-created.md` and `academic-term-status-changed.md`: new event contracts.
- [x] 14.7 `docs/internal/07_components/`: add a new academic-config-service component diagram (none exists yet), including the term entity.

## 15. Coordination with in-flight changes

- [x] 15.1 Term GET handlers gated on `academic.config.read` and writes on `academic.config.write` directly in `academic-config-service/src/http.rs:739, 759, 715, 785, 806, 831` (added under this change since terms post-date `rbac-read-and-menu-restructure`'s archive). Term management is a `Semester` tab inside the year edit modal at `apps/web/src/app/settings/academic/years/page.tsx:538`, sitting under the existing `Pengaturan → Akademik` umbrella entry — not a distinct sidebar child item. The umbrella sidebar entry remains gated on `academic.config.read` (`sidebar-layout.tsx:74`).
- [x] 15.2 `tenant-audit-log` widened to consume `academic_year.*` and `academic_term.*` events into the same `audit_log` store with `target_kind`/`target_id` discriminator (see `openspec/changes/tenant-audit-log/proposal.md`, `design.md`, and `tasks.md` sections 8–10). The local `academic_year_status_transition` and `academic_term_status_transition` tables in academic-config-service are retained as domain history.

## 16. Follow-ups landed in the post-implementation review

These items closed real gaps surfaced by the spec audit on 2026-06-17.

- [x] 16.1 Backward HTTP transition test for terms in academic-config-service (`tests/integration.rs::term_backward_transition_via_http`) — exercises `Closed→Active` and `Active→Draft` through HTTP and asserts the `academic_term_status_transition` row persists with correct `from_status`/`to_status`/`reason`. Closes the gap noted in 5.1 where backward edges were only covered by unit tests.
- [x] 16.2 Closed-term grade entry rejection test (`grading-service/tests/integration.rs::test_term_scoped_gates_and_projections`) — added the missing case where a grade entry attempt against a `Closed` term is rejected with `TERM_NOT_ACTIVE`. Previously only `Draft` was tested; complements 8.4.
- [x] 16.3 `update_evaluation` term-editable test in the same file — covers the update branch in `commands.rs:144-152` (rejection when the evaluation's term transitions to `Closed`); complements 8.1.
- [x] 16.4 Management-page warning in `TermsSection` (`apps/web/src/app/settings/academic/years/page.tsx`) — renders an amber `Alert` when the year is `Active` but no term is `Active`, mirroring the header warning shipped in 10.5.
- [x] 16.5 Status-confirm dialog routes errors through `getErrorMessage` (`years/page.tsx::TermRow.handleStatusConfirm`) — replaces the hardcoded 3-code switch so all 9 mapped term error codes surface their proper Indonesian copy. Closes the partial in 11.4.
- [x] 16.6 `ReportTypesSection` wired to `termId` (`years/page.tsx:933-1070`) — reads `useAcademicScope()`, passes `termId` to `useReportTypes` and into the create payload, gracefully empty-states when no term is selected. Closes 12.2.
- [x] 16.7 `WeightMatrix` filters report types by selected term (`apps/web/src/app/grading/entry/page.tsx:613, 736-748`) — was year-scoped only; now consistent with the rest of the grade-entry page and aligned with the `EVALUATION_TERM_MISMATCH` invariant. Closes the sub-finding in 12.1.
- [x] 16.8 Playwright: header term selector default-resolution test (`apps/web/playwright/academic-config.spec.ts::header term selector resolves default`) — three scenarios: Active wins, today-in-range wins when no Active, first-by-start_date wins as fallback. Closes the gap noted in 13.1.
- [x] 16.9 Playwright: backward + type-to-confirm + cooldown + Archived term transition test (same file) — exercises `Closed→Active` backward edge and `Closed→Archived` terminal edge with type-to-confirm and cooldown assertions. Closes the second gap in 13.1.
