## Why

The product target is **"a tenant user can create a report card (rapor)"**. A
report card aggregates per-subject grades for an enrolled student under a
grading policy, scoped to one academic year. None of those upstream concepts
exist yet: the backend (`init-backend-frontend-submodules` +
`mvp-foundation-iam-billing`) only ships IAM and Billing. The rapor goal
therefore depends on a four-link chain that must be built in order:

```
Academic Config → Academic Ops → Grading (grade capture) → Report Card workflow
  (this change)
```

This change delivers the **first link**: the `academic-config-service` that
owns the year-based academic structure every later phase references — the
academic year, curriculum versions, subjects (with passing grades), the
grading policy (minimum passing score + grading scale), and class templates.
Without an academic year and subjects, students cannot be enrolled and grades
cannot be recorded, so the report card has nothing to aggregate.

This corresponds to **Phase 2 — Academic Configuration** in
`docs/internal/13_engineering_standards/16_implementation_phases.md`.

## What Changes

### Backend — new service `academic-config-service`

- New Cargo crate `apps/backend/services/academic-config-service` added to the
  workspace, following the exact module layout of `iam-service`
  (`config`, `domain`, `repo`, `commands`, `queries`, `http`, `state`,
  `lib.rs`) with refinery migrations and the CQRS split from
  `13_engineering_standards/10_cqrs_pattern.md`.
- Tables (refinery `V1__init.sql`), per
  `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`:
  `academic_year`, `curriculum_version`, `subject`, `grading_policy`,
  `class_template`. Every table carries `tenant_id`; all queries are
  tenant-scoped from the JWT, never from the request body.
- **Event consumer**: subscribes to `subscription.activated` (emitted by
  Billing in phase 1) and records the tenant's active-subscription state so
  academic-year creation can be gated behind an active subscription.
- **Feature-entitlement gate**: all write endpoints sit behind the
  `common-auth` entitlement middleware for the `academic_config` feature
  code; non-entitled tenants get HTTP 403 `FEATURE_NOT_AVAILABLE`
  (`13_engineering_standards/15_feature_entitlement.md`).
- HTTP API under `/api/v1/academic-config`:
  - `POST /academic-years`, `GET /academic-years`, `GET /academic-years/{id}`,
    `PATCH /academic-years/{id}/status` (Planning → Configuration → Active …
    per `09_states/AcademiQ_State_Academic_Year_Lifecycle.md`).
  - `POST /academic-years/{id}/curriculum-versions`, list under a year.
  - `POST /curriculum-versions/{id}/subjects`, list; each subject carries a
    `passing_grade`.
  - `PUT /academic-years/{id}/grading-policy` (minimum passing score +
    grading scale), `GET` the same.
  - `POST /academic-years/{id}/class-templates`, list.
  - `GET /healthz`.
- **Event emitted**: `academic_year.created` (consumed by the phase-3
  academic-ops service to allow homeroom creation for that year), documented
  under `docs/internal/11_integration_contracts/events/` before archive.
- RabbitMQ wiring reuses the phase-1 outbox pattern (produce + drain in
  `event_id` order, at-least-once).

### Web — `/settings/academic/*`

- Pages under `/settings/academic`: academic year list + create + status
  transition, curriculum + subjects editor, grading policy form, class
  templates. shadcn/ui only, TanStack Query for all data, React Hook Form +
  Zod with `applyServerFieldErrors`, two-tier loading (spinner for
  action-bound controls, skeleton for layout regions), per
  `apps/web/CONVENTIONS.md`.

### Tests & docs

- Unit tests on domain rules (year status transitions, passing-grade
  validation). Per-service integration tests against a Postgres testcontainer.
  Cross-service e2e: register tenant (phase 1) → create academic year → add
  subjects → set grading policy. Playwright on the web flow.
- API contract under `docs/internal/11_integration_contracts/apis/`, event
  contract for `academic_year.created`, and the roadmap entry flipped from ⏳
  to 🚧/✅.

## Capabilities

### New Capabilities

- `academic-config-service`: defines the academic-year lifecycle, curriculum
  versions, subjects with passing grades, grading policy, class templates, the
  `subscription.activated` consumption that gates year creation, and the
  `academic_year.created` event other services consume.

### Modified Capabilities

- `implementation-roadmap`: Phase 2 status moves from planned to in-flight;
  the deferred "grading & report cards" line is promoted into numbered phases
  (delivered by the sibling changes in this batch).

## Impact

- **New code**: `services/academic-config-service` crate + migrations; web
  pages under `/settings/academic`; e2e additions; `academic_config` feature
  code already exists in the phase-1 `features.toml` matrix.
- **Modified docs**: API + event contracts, roadmap status, `01_repo_structure`.
- **Depends on**: phase 1 (`subscription.activated`, `common-*` libs,
  entitlement middleware, web conventions). **Blocks**: `mvp-academic-ops`.
- **Out of scope**: students/teachers/homerooms (phase 3), any grade or report
  card concept (later phases), curriculum import.
