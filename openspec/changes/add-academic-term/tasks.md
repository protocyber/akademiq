## 1. Backend — academic-config-service domain & constants

- [ ] 1.1 Add `TermStatus` type in `services/academic-config-service/src/domain.rs` reusing the 4 variants (`Draft`, `Active`, `Closed`, `Archived`) with `as_str`/`from_str`/`default`/`can_transition_to` mirroring `YearStatus` (same matrix: `Draft↔Active`, `Active↔Closed`, `Closed→Archived`; reject skips, out-of-`Archived`, no-op).
- [ ] 1.2 Add `AcademicTerm` struct (`term_id`, `academic_year_id`, `tenant_id`, `name`, `start_date`, `end_date`, `status: TermStatus`, timestamps).
- [ ] 1.3 Add `pub const DEFAULT_TERM_NAME: &str = "Semester 1";` in `domain.rs`.
- [ ] 1.4 Unit tests for `TermStatus::can_transition_to` (forward, backward, skips, out-of-`Archived`, no-op).

## 2. Backend — academic-config-service repo & migration

- [ ] 2.1 Create migration `V4__academic_term.sql`: `academic_term` table (PK/FK cascade, `tenant_id`, `name`, dates, `status` default `Draft`, `CHECK(start_date <= end_date)`, `CHECK(status IN (...))`, `UNIQUE(tenant_id, academic_year_id, name)`); partial unique index `academic_term_one_active_per_year_idx ON academic_term (academic_year_id) WHERE status = 'Active'`; `academic_term_status_transition` table (same shape as `academic_year_status_transition`).
- [ ] 2.2 In the same migration, idempotently seed one `"Semester 1"` term per existing `academic_year` (copy `start_date`/`end_date`/`status` from the year), guarded by `WHERE NOT EXISTS`.
- [ ] 2.3 Add `AcademicTermRepo` to `repo.rs`: `insert`, `find_by_id`, `list_for_year` (paginated, like `AcademicYearRepo::list`), `update` (name/dates), `delete`, `update_status`, `active_exists_except` (per year), `insert_transition`, `count_active_terms_for_year`, plus an `overlaps` helper for date-range overlap checks.
- [ ] 2.4 Verify migration is idempotent (re-run is a no-op once seeded).

## 3. Backend — academic-config-service commands

- [ ] 3.1 Extend `create_academic_year` (`commands.rs:32`) to insert, in the same transaction, a default term (`name = DEFAULT_TERM_NAME`, year's dates, `Draft`) and enqueue `academic_term.created` alongside `academic_year.created`.
- [ ] 3.2 Add `create_academic_term`: validate name/dates, fetch parent year, enforce `start_date >= year.start_date`, `end_date <= year.end_date`, no overlap with existing terms in the year (`TERM_OVERLAP`), enforce name uniqueness (`TERM_NAME_EXISTS`), insert + enqueue `academic_term.created`.
- [ ] 3.3 Add `update_academic_term` (name/dates) with the same range/overlap checks; reject if term status is `Archived`.
- [ ] 3.4 Add `transition_term_status`: parse target, enforce transition matrix (`INVALID_STATE_TRANSITION`), enforce one-`Active`-term-per-year (`ACTIVE_TERM_EXISTS`), persist reason (min 10 chars) to `academic_term_status_transition`, enqueue `academic_term.status_changed`.
- [ ] 3.5 Add `delete_academic_term`: reject if status is `Active`/`Archived` (`TERM_NOT_DELETABLE`); (grading-side `TERM_IN_USE` is enforced by the grading DB — coordinate via projection/usage query if a cross-DB usage signal is available, otherwise rely on grading rejecting dependent deletes).
- [ ] 3.6 Extend `transition_year_status` (`commands.rs:99`) to reject `→ Closed` when `count_active_terms_for_year > 0` (`TERM_STILL_ACTIVE`, HTTP 409). No new check on `→ Active`.

## 4. Backend — academic-config-service HTTP

- [ ] 4.1 Add routes in `http.rs`: `GET /academic-years/{year_id}/terms` (list, paginated), `POST /academic-years/{year_id}/terms` (create), `GET|PATCH|DELETE /academic-terms/{id}`, `PATCH /academic-terms/{id}/status` (`{ status, reason }`). Gate GETs on `academic.config.read` and writes on `academic.config.write` (coordinate with `rbac-read-and-menu-restructure`).
- [ ] 4.2 Return `VALIDATION_ERROR` field errors for name/dates; map repo/usage errors to `TERM_OVERLAP`/`TERM_NAME_EXISTS`/`ACTIVE_TERM_EXISTS`/`TERM_STILL_ACTIVE`/`INVALID_STATE_TRANSITION`/`TERM_NOT_DELETABLE`.

## 5. Backend — academic-config-service tests

- [ ] 5.1 Integration tests: create year ⇒ default term exists; create term within/ outside range; overlap rejection; duplicate name rejection; forward/backward term transitions with reason; one-active-term-per-year; year `→ Closed` rejected with an active term.
- [ ] 5.2 Tests assert both `academic_term.created` and `academic_term.status_changed` events are emitted with the documented payload.

## 6. Backend — grading-service migration & projection

- [ ] 6.1 Create migration `V7__term_rework.sql`: `ALTER TABLE evaluation ADD COLUMN term_id UUID` (nullable); `ALTER TABLE report_type ADD COLUMN term_id UUID` (nullable); backfill each from its year's default term (join via `academic_year_id`); `ALTER TABLE ... SET NOT NULL`; `DROP CONSTRAINT evaluation_scope_code_unique` and `report_type_year_code_unique`; add `evaluation_scope_term_code_unique (tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` and `report_type_term_code_unique (academic_year_id, term_id, code)`. Dev-reset acceptable per `V4`/`V5` precedent.
- [ ] 6.2 Create migration `V8__valid_term_projection.sql`: `valid_term` table mirroring `valid_year` (`term_id`, `tenant_id`, `academic_year_id`, `status`, `updated_at`).
- [ ] 6.3 Add `ValidTermRepo` and a projection row mapper.

## 7. Backend — grading-service events & domain

- [ ] 7.1 In `events.rs`, bind `academic_term.created` and `academic_term.status_changed`; idempotently upsert `valid_term`.
- [ ] 7.2 Add `term_id` to `Evaluation` and `ReportType` in `domain.rs` and update their row mappers and insert/update queries.

## 8. Backend — grading-service gates

- [ ] 8.1 Evaluation create/update command: resolve `valid_term.status` for the evaluation's `term_id`; reject with `TERM_NOT_EDITABLE` (HTTP 409) unless status is `Draft` or `Active`.
- [ ] 8.2 Grade-record command: additionally resolve the term status via the evaluation's `term_id` and reject with `TERM_NOT_ACTIVE` (HTTP 409) unless `Active` (keep the existing year-`Active` `YEAR_NOT_ACTIVE` gate).
- [ ] 8.3 `report_formula` add command: load the report type's `term_id` and the evaluation's `term_id`; reject with `EVALUATION_TERM_MISMATCH` (HTTP 409) if they differ.
- [ ] 8.4 Integration tests: cross-term formula rejected; evaluation create in `Closed` term rejected; grade entry in `Draft`/`Closed` term rejected, allowed in `Active`; `valid_term` projection upsert is idempotent.

## 9. Backend — academic-ops-service (optional projection)

- [ ] 9.1 Migration `V5__known_term.sql`: `known_academic_term` table mirroring `known_academic_year`.
- [ ] 9.2 Bind `academic_term.created`/`academic_term.status_changed` in `events.rs` and upsert `known_academic_term`. No changes to homeroom/enrollment/teaching (year-scoped).

## 10. Web — global scope provider

- [ ] 10.1 Add `useTerms(yearId)` query hook (paginated/list) backed by `GET /academic-years/{id}/terms`.
- [ ] 10.2 Extend `academic-scope-provider.tsx` with `termId` state, localStorage persistence (same tenant key, now `{academic_year_id, term_id, curriculum_version_id}`), and Context value.
- [ ] 10.3 Implement default resolution: `Active` term → today-in-range term → first term; reset term when the year changes.
- [ ] 10.4 Add a term `<Select>` to the header beside the year picker; disable gracefully when the year has no terms.
- [ ] 10.5 Show a warning (header + management page) when the selected year is `Active` but has no `Active` term.

## 11. Web — term management UI

- [ ] 11.1 Add `src/lib/schemas/academic-term.ts` Zod schemas for create/update/transition (mirror the academic-year schema incl. `reason` min 10).
- [ ] 11.2 Add a term-management section/sub-page under the academic year (where report types are managed today): list, create, edit, delete.
- [ ] 11.3 Wire `StatusConfirmDialog` (from `simplify-academic-year-status`) for term status transitions (type-to-confirm + cooldown for backward/`→ Archived`).
- [ ] 11.4 Surface backend errors (`TERM_OVERLAP`, `TERM_NAME_EXISTS`, `ACTIVE_TERM_EXISTS`, `TERM_STILL_ACTIVE`, `TERM_NOT_EDITABLE`, `TERM_NOT_ACTIVE`, `EVALUATION_TERM_MISMATCH`, `TERM_NOT_DELETABLE`, `TERM_IN_USE`) as readable inline messages.
- [ ] 11.5 Gate view on `academic.config.read` and create/edit/delete/status on `academic.config.write` (coordinate with `rbac-read-and-menu-restructure`).

## 12. Web — consume scope in grading pages

- [ ] 12.1 Grade-entry and report-board pages read `termId` from the scope and pass it to the evaluation/report-type queries and mutations.
- [ ] 12.2 Report-type management UI (currently inside the year form) filters/creates by the selected `termId`.

## 13. Web — tests & checks

- [ ] 13.1 Playwright: term CRUD, status transition confirmation flow, header selector default resolution, warning state when no active term.
- [ ] 13.2 Run web lint/typecheck and `make test` for web.

## 14. Documentation

- [ ] 14.1 `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`: add `academic_term` + `academic_term_status_transition`.
- [ ] 14.2 `docs/internal/10_data_design/06_Grading_Service_ERD.md`: add `term_id` to `evaluation`/`report_type`, add `valid_term` projection; refresh the stale diagram to the post-`V4`/`V5` model.
- [ ] 14.3 `docs/internal/09_states/AcademiQ_State_Academic_Term_Lifecycle.md`: new 4-state machine with parent-child coordination rules.
- [ ] 14.4 `docs/internal/11_integration_contracts/apis/academic-config-api.md`: term endpoints + lifecycle text.
- [ ] 14.5 `docs/internal/11_integration_contracts/apis/grading-service-api.md`: `term_id` in evaluation/report-type schemas; new error codes table.
- [ ] 14.6 `docs/internal/11_integration_contracts/events/academic-term-created.md` and `academic-term-status-changed.md`: new event contracts.
- [ ] 14.7 `docs/internal/07_components/`: add a new academic-config-service component diagram (none exists yet), including the term entity.

## 15. Coordination with in-flight changes

- [ ] 15.1 Confirm `rbac-read-and-menu-restructure` gates the new term GET endpoints on `academic.config.read` and the writes on `academic.config.write`; add a menu entry for term management under `Pengaturan → Akademik` (see handoff note).
- [ ] 15.2 Confirm `tenant-audit-log` will consume `academic_term.*` events (or accept the interim `academic_term_status_transition` store) so term transitions are audited consistently with year transitions (see handoff note).
