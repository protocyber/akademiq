## Why

Academic years are today a flat, single-level construct: evaluations, report
types, grades, and report cards all attach directly to `academic_year_id`. But
real schools divide the year into sub-periods — semesters, caturwulan,
triwulan — and both evaluations ("UH1 of semester 1" ≠ "UH1 of semester 2") and
report runs ("Rapor Tengah Semester", "Rapor Akhir Semester") are scoped to
those periods, not the whole year. There is currently no concept of a period,
term, or semester anywhere in the codebase (the word "semester" appears only as
example report-type names and in two UI mockups). Without an intermediate
period level, operators are forced to encode period semantics into evaluation
codes (e.g. "S1-UH1") and into report-type names, which is brittle and does not
enforce any structure.

This change introduces an `academic_term` entity under the academic year: each
year owns one or more terms (default-seeded as "Semester 1"), and evaluations
and report types are re-scoped to `(year, term)`. The entity is named `term`
deliberately — it is a neutral label container that can hold "Semester 1",
"Caturwulan 2", or "Triwulan 3" without code changes.

## What Changes

- **NEW `academic_term` entity** (academic-config-service) owned by an academic
  year. Fields: `term_id`, `academic_year_id` (FK, cascade delete), `tenant_id`,
  `name`, `start_date`, `end_date`, `status` (`Draft`/`Active`/`Closed`/
  `Archived`), timestamps. Unique name per year; max one `Active` term per year
  via a partial unique index.
- **NEW auto-seed on year creation**: `create_academic_year` atomically creates
  one child term named `"Semester 1"` (a backend constant, editable later) with
  the year's dates and `Draft` status, and emits `academic_term.created`. Every
  academic year therefore always has at least one term.
- **NEW term lifecycle**: a 4-state machine mirroring the academic year
  (`Draft ⇄ Active ⇄ Closed → Archived`), independent but bounded by the parent:
  a term's dates must fall within its year's dates, and the year's status
  constrains aggregate transitions (see below).
- **NEW parent-child coordination rules**:
  - Transitioning a year to `Active` requires NO term invariant (the year may be
    `Active` while all its terms are still `Draft`).
  - Transitioning a year to `Closed` is rejected while any of its terms is
    `Active` (error `TERM_STILL_ACTIVE`) — the operator must close terms first.
- **NEW evaluation gate**: creating or editing an evaluation requires the
  referenced term to be `Draft` or `Active` (rejected with `TERM_NOT_EDITABLE`
  on `Closed`/`Archived`). Recording a grade additionally requires the term to
  be `Active` (error `TERM_NOT_ACTIVE`, HTTP 409) — extending the existing
  year-active grade gate.
- **BREAKING (grading-service)**: `evaluation` and `report_type` gain a
  NOT NULL `term_id` column and are re-scoped to `(year, term)`:
  - `evaluation` uniqueness becomes
    `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)`.
  - `report_type` uniqueness becomes
    `(academic_year_id, term_id, code)` and is strictly term-scoped (a report
    type belongs to exactly one term). Report-card annual aggregation across
    terms is out of scope (future change).
  - `report_formula` validation rejects an evaluation whose `term_id` differs
    from the report type's `term_id` (error `EVALUATION_TERM_MISMATCH`).
- **NEW events**: `academic_term.created` and `academic_term.status_changed`,
  produced by academic-config-service and consumed by grading-service
  (`valid_term` projection, mirroring `valid_year`) and academic-ops-service
  (`known_academic_term` projection).
- **MODIFIED global academic scope (web)**: the header scope gains a `termId`
  dimension alongside `yearId`/`curriculumId`, persisted in `localStorage` and
  exposed via the existing React Context. Default resolution: the `Active` term
  of the selected year (fallback to the term whose date range contains today,
  then the first term). A visible warning surfaces when the active year has no
  `Active` term.

## Capabilities

### New Capabilities

- `academic-term-management`: the `academic_term` entity, its CRUD + status
  lifecycle, the auto-seed on year creation, parent-child coordination rules,
  and the `academic_term.created` / `academic_term.status_changed` events.

### Modified Capabilities

- `academic-config-service`: academic-year creation now also seeds a default
  term; year-to-`Closed` gains the `TERM_STILL_ACTIVE` guard.
- `grading-service-grade-capture`: `evaluation` and `report_type` are re-scoped
  to `(year, term)`; evaluation create/edit is gated on term `Draft`/`Active`;
  grade entry is additionally gated on term `Active`; `report_formula` rejects
  cross-term evaluations; a `valid_term` projection is added.
- `web-academic-scope`: the global scope gains a `termId` dimension and a term
  selector in the header, with default-resolution and empty-state rules.
- `web-academic-config-management`: term CRUD and status-transition UI under a
  year, plus a warning when an `Active` year has no `Active` term.

## Impact

**Backend — academic-config-service**
- `domain.rs`: new `TermStatus` (alias of the 4-state model), `AcademicTerm`
  struct, `can_transition_to` for terms, and a `DEFAULT_TERM_NAME` constant
  (`"Semester 1"`).
- `repo.rs`: new `AcademicTermRepo` (insert/find/list/update_status/delete/
  active_exists_except/insert_transition/count_active_terms_for_year) plus a
  `term_status_transition` audit table mirroring the year one.
- `commands.rs`: new `create_academic_term`, `transition_term_status`,
  `update_academic_term`, `delete_academic_term`; `create_academic_year` is
  extended to seed the default term in the same transaction; `transition_year_
  status` gains the `TERM_STILL_ACTIVE` guard on `→ Closed`.
- `http.rs`: new routes under `/academic-years/{year_id}/terms` (list/create)
  and `/academic-terms/{id}` (get/update/delete/status).
- New migration `V4__academic_term.sql`: the `academic_term` table, its partial
  unique index, the `academic_term_status_transition` table, and a seed of one
  `"Semester 1"` term per existing academic year (idempotent).

**Backend — grading-service**
- New migration `V7__term_rework.sql`: adds `term_id UUID NOT NULL` to
  `evaluation` and `report_type` (nullable first, backfilled to each year's
  default term, then `NOT NULL`), drops the old unique constraints, and adds the
  new term-scoped uniqueness. Dev-reset acceptable (matches the `V4`/`V5`
  precedent).
- New migration `V8__valid_term_projection.sql`: `valid_term` projection table
  mirroring `valid_year`.
- `events.rs`: consume `academic_term.created` / `academic_term.status_changed`
  to upsert `valid_term`.
- `commands.rs`: evaluation create/edit gated on `valid_term.status` ∈
  {`Draft`,`Active`}; grade entry gated on term `Active`; `report_formula` add
  rejects `EVALUATION_TERM_MISMATCH`.
- `domain.rs`: `Evaluation` and `ReportType` gain `term_id`.

**Backend — academic-ops-service**
- Optional light projection `known_academic_term` (migration `V5__known_term`)
  and event consumer. Homeroom/enrollment/teaching remain year-scoped and are
  NOT changed by this change.

**Web frontend (`apps/web`)**
- `academic-scope-provider.tsx`: gains `termId` state, localStorage key, default
  resolution, and a `useTerms(yearId)` query to populate the selector.
- Header: a new term `<Select>` beside the year picker.
- `schemas/academic-term.ts`: new Zod schemas for term CRUD + transition.
- `app/settings/academic/years/page.tsx` (or a new terms sub-page): term
  management UI — list, create, edit, delete, status transition (reusing the
  existing `StatusConfirmDialog` from `simplify-academic-year-status`).
- Grade-entry / report-board pages consume `termId` from the scope.
- A warning banner/inline state when the active year has no `Active` term.

**Docs**
- `10_data_design/03_Academic_Config_Service_ERD.md`: add `academic_term`.
- `10_data_design/06_Grading_Service_ERD.md`: add `term_id` to
  `evaluation`/`report_type` and the `valid_term` projection (and refresh the
  stale ERD to the post-`V4`/`V5` model).
- `09_states/AcademiQ_State_Academic_Term_Lifecycle.md`: new state machine.
- `11_integration_contracts/apis/academic-config-api.md`: term endpoints.
- `11_integration_contracts/apis/grading-service-api.md`: `term_id` in
  evaluation/report-type schemas; new error codes.
- `11_integration_contracts/events/academic-term-created.md` and
  `academic-term-status-changed.md`: new event contracts.
- `07_components/`: a new academic-config component diagram (none exists yet).

**Out of scope**
- Homeroom / enrollment / teaching-assignment re-scoping to term (kept at year).
- Annual report aggregation across terms (`report_type` is strictly
  term-scoped here; a future change may introduce a year-scoped report mode).
- Per-tenant configurable default term name (hard-coded constant for now).
- Attendance module guards (module not yet implemented).
- Auto-activation of terms on year `→ Active` (operator-driven by design).

**Coordination with in-flight changes**
- `rbac-read-and-menu-restructure`: needs a menu entry for term management and
  the new GET endpoints gated on `academic.config.read`; the term transition
  endpoints reuse `academic.config.write`. See the todo in the accompanying
  handoff note.
- `tenant-audit-log`: term status transitions write to the local
  `academic_term_status_transition` table (mirroring the year interim store);
  when `tenant-audit-log` lands, the write target moves there without contract
  change. See the handoff note.
