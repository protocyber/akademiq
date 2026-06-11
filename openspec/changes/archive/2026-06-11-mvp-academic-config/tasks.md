## 1. Roadmap & workspace prep

- [x] 1.1 Flip Phase 2 in `docs/internal/13_engineering_standards/16_implementation_phases.md` from ⏳ to 🚧 and set the delivering change to `mvp-academic-config`
- [x] 1.2 Promote "grading & report cards" out of the Deferred section into numbered phases referencing `mvp-grading-grade-capture` and `mvp-report-card-workflow`
- [x] 1.3 Add `services/academic-config-service` to `apps/backend/Cargo.toml` workspace members
- [x] 1.4 Add `ACADEMIC_CONFIG_DATABASE_URL` to `apps/backend/.env.example`
- [x] 1.5 Extend `apps/backend/docker-compose.yml` and `compose.test.yml` with the new service + its Postgres DB

## 2. Schema & migrations

- [x] 2.1 `V1__init.sql`: `academic_year`, `curriculum_version`, `subject`, `grading_policy`, `class_template`, `tenant_subscription_state` per `10_data_design/03_Academic_Config_Service_ERD.md`
- [x] 2.2 Partial unique index enforcing at most one `Active` academic year per tenant
- [x] 2.3 Indexes: `academic_year(tenant_id, status)`, `curriculum_version(academic_year_id)`, `subject(curriculum_version_id)`, `class_template(academic_year_id)`
- [x] 2.4 `make migrate` / `make migrate-down` targets in `services/academic-config-service/Makefile`

## 3. Domain & repos (CQRS-separated)

- [x] 3.1 Domain types: `AcademicYear` (+ `YearStatus` enum), `CurriculumVersion`, `Subject`, `GradingPolicy`, `ClassTemplate`
- [x] 3.2 Year status transition function with validation (legal transitions only) + unit tests
- [x] 3.3 Commands under `src/commands/`: `CreateAcademicYear`, `TransitionYearStatus`, `AddCurriculumVersion`, `AddSubject`, `UpsertGradingPolicy`, `AddClassTemplate`
- [x] 3.4 Queries under `src/queries/`: `ListAcademicYears`, `GetAcademicYear`, `ListSubjects`, `GetGradingPolicy`, `ListClassTemplates`
- [x] 3.5 Repository traits + SQLx impls for each aggregate; all reads tenant-scoped from `AuthContext`

## 4. Subscription projection (event consumer)

- [x] 4.1 RabbitMQ consumer for `subscription.activated`; upserts `tenant_subscription_state`
- [x] 4.2 Year-creation command checks the projection; returns 403 `SUBSCRIPTION_INACTIVE` when no active subscription
- [x] 4.3 Integration test: tenant with no projection row cannot create a year; after consuming the event, it can

## 5. HTTP layer (`/api/v1/academic-config`)

- [x] 5.1 `POST /academic-years`, `GET /academic-years`, `GET /academic-years/{id}`
- [x] 5.2 `PATCH /academic-years/{id}/status` enforcing the lifecycle; illegal transition → 409 `INVALID_STATE_TRANSITION`
- [x] 5.3 `POST /academic-years/{id}/curriculum-versions` + list
- [x] 5.4 `POST /curriculum-versions/{id}/subjects` (validates `passing_grade` range) + list
- [x] 5.5 `PUT /academic-years/{id}/grading-policy` (upsert, validates scale enum + min score) + `GET`
- [x] 5.6 `POST /academic-years/{id}/class-templates` + list
- [x] 5.7 `GET /healthz` (DB + RabbitMQ)
- [x] 5.8 Wire `common-auth` entitlement middleware (`academic_config`) on all write routes

## 6. Event emission

- [x] 6.1 Emit `academic_year.created` to the outbox on successful year creation (envelope per `04_event_standards.md`)
- [x] 6.2 Outbox drain loop (reuse phase-1 pattern), at-least-once, `event_id` order
- [x] 6.3 Document `docs/internal/11_integration_contracts/events/academic-year-created.md` with payload (`tenant_id`, `academic_year_id`, `name`, `start_date`, `end_date`)

## 7. Integration tests

- [x] 7.1 Create year happy path; second `Active` year for same tenant rejected
- [x] 7.2 Status transition legal + illegal paths
- [x] 7.3 Add curriculum + subjects; passing-grade out of range rejected per-field
- [x] 7.4 Upsert grading policy; invalid scale rejected
- [x] 7.5 Non-entitled tenant gets 403 `FEATURE_NOT_AVAILABLE`
- [x] 7.6 `academic_year.created` lands on RabbitMQ with the documented payload

## 8. Web — `/settings/academic/*`

- [x] 8.1 `lib/schemas/` Zod schemas: academic-year, subject, grading-policy, class-template
- [x] 8.2 TanStack query/mutation hooks for each resource via `lib/api.ts`
- [x] 8.3 `/settings/academic/years` — list (skeleton) + create dialog + status transition control (spinner)
- [x] 8.4 `/settings/academic/curriculum` — curriculum + subjects editor
- [x] 8.5 `/settings/academic/grading-policy` — RHF form bound to upsert
- [x] 8.6 `/settings/academic/class-templates` — list + create
- [x] 8.7 Non-entitled tenant sees disabled controls with "Upgrade plan" tooltip

## 9. Cross-service e2e & wrap-up

- [x] 9.1 Backend e2e: register tenant (phase 1) → consume `subscription.activated` → create year → add subjects → set grading policy
- [x] 9.2 Playwright: tenant admin walks the academic-config pages end to end
- [x] 9.3 API contract doc `docs/internal/11_integration_contracts/apis/academic-config-api.md` filled with real request/response shapes
- [x] 9.4 Update `docs/internal/13_engineering_standards/01_repo_structure.md` (mark service built)
- [x] 9.5 `openspec validate mvp-academic-config --strict` green
