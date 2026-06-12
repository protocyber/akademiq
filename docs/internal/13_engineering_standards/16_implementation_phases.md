# Implementation Phases

This document defines the phased build order for the AcademiQ backend and
web frontend. Each phase ships a vertical slice that a non-developer can
demo end-to-end. Later phases depend on earlier phases having shipped
their owned services and event contracts.

The roadmap lives in `13_engineering_standards/` because phasing is a
standing engineering rule: every new capability lands in the smallest
phase that satisfies the demo, not as a flag-day mega-PR.

## Status legend

| Symbol | Meaning |
|--------|---------|
| ✅     | Phase shipped (delivering change archived under `openspec/changes/archive/`) |
| 🚧     | Phase in flight (delivering change is `proposal` / `apply` / `archive` pending) |
| ⏳     | Phase planned, not yet started (no openspec change opened) |

## Phase 1 — Foundation: IAM + Billing 🚧

**Owning services**: `iam-service`, `billing-service`
**Delivering change**: `mvp-foundation-iam-billing`
**Demo flows that prove this phase complete:**

1. **Register tenant** — a school visits `/register`, fills the wizard,
   and submits.
2. **Select plan** — the wizard's plan-selection step lists plans from
   `GET /api/v1/billing/plans` and the chosen plan is attached to the
   tenant's first subscription.
3. **Log in** — after registration the admin lands on `/dashboard`
   already authenticated, and a fresh session can log back in via
   `/login`.
4. **Toggle entitled modules** — `/settings/modules` lets the tenant
   admin flip feature codes their plan entitles. Non-entitled modules
   render disabled with an "Upgrade plan" hint.

**Scope:**

- Cargo workspace at `apps/backend/`.
- Shared libs: `common-auth`, `common-db`, `common-logging`,
  `common-errors`, `common-testing`.
- `iam-service`: login, refresh, logout, `/me`, internal user create +
  delete, RS256 JWT, Argon2id passwords, role seed.
  > **Note**: the authentication model is extended after this phase by
  > `username-identity-login` (login by email **or** username, optional email),
  > `public-signup-tenant-tokens` (public signup + identity/tenant-scoped two-token
  > model, multi-tenant membership), and `google-oauth-login` (Login with Gmail).
  > Email-as-sole-identity and the single-`tenant_id`-in-JWT described here are
  > superseded by those changes.
- `billing-service`: tenant registration saga (with compensating delete
  on IAM failure + janitor for mid-saga crashes), plan catalog, module
  toggling with plan entitlement enforcement, RabbitMQ outbox emitting
  `tenant.registered` and `subscription.activated`.
- Web app: shadcn/ui only, TanStack Query for all data, React Hook Form
  + Zod with shared `applyServerFieldErrors`, two-tier loading
  (spinners for action-bound controls, skeletons for layout regions).
- Test pyramid: unit + per-service integration (Postgres testcontainer)
  + cross-service e2e crate + Playwright on the web flow.
- `make seed` loads three plans (`Starter`, `Standard`, `Premium`) and
  two demo tenants for clickable manual testing.

**Exit criteria:**

- The four demo flows above run green via `make test-e2e` and
  `pnpm test:e2e` without manual intervention.
- `cargo test --workspace` and `pnpm lint && pnpm test:unit` are green
  in CI on both submodules.
- `tenant.registered` and `subscription.activated` event contracts are
  documented under
  `docs/internal/11_integration_contracts/events/`.
- IAM and Billing API contracts are documented under
  `docs/internal/11_integration_contracts/apis/`.
- `make seed && make dev` brings up a browser-clickable demo.

## Phase 2 — Academic Configuration 🚧

**Owning service**: `academic-config-service`
**Delivering change**: `mvp-academic-config`
**Demo flows:**

1. **Create academic year** — a tenant admin creates a new academic
   year, sets start/end dates and status (draft → active).
2. **Configure curriculum + subjects** — the admin selects a
   curriculum version for the year and adds subjects with passing
   grades.
3. **Define grading policy + class templates** — the admin sets the
   minimum passing score, grading scale, and default class templates
   per grade level.

**Scope:**

- New service `academic-config-service` consuming
  `subscription.activated` to gate academic-year creation behind an
  active subscription.
- Tables: `academic_year`, `curriculum_version`, `subject`,
  `grading_policy`, `class_template` (per
  `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`).
- Web pages under `/settings/academic/*` for year, curriculum,
  subjects, grading policy, class templates.
- Event emitted: `academic_year.created`.

**Exit criteria:**

- Creating an academic year is gated by `subscription.status = active`.
- Phase 2 e2e walks the three demo flows above against a tenant
  registered in phase 1.
- `academic_year.created` payload is documented and consumed by the
  phase 3 service.

## Phase 3 — Academic Operations 🚧

**Owning service**: `academic-ops-service`
**Delivering change**: `mvp-academic-ops`
**Demo flows:**

1. **Add students manually** — a tenant admin creates students one by
   one with NIS, name, gender, birth date.
2. **Import students/teachers via Excel** — the admin uploads a
   spreadsheet (template provided) and the service ingests it into the
   correct tenant.
3. **Create homerooms and enroll students** — the admin creates a
   homeroom for the active academic year and enrolls students into it.
4. **Assign teachers to subjects + classes** — the admin links a
   teacher to a subject in a homeroom for the academic year.

**Scope:**

- New service `academic-ops-service` consuming `academic_year.created`
  and `subscription.activated`.
- Tables: `student`, `teacher`, `homeroom`, `enrollment`,
  `teaching_assignment`, `timetable` (per
  `docs/internal/10_data_design/04_Academic_Operations_ERD.md`).
- Excel import flow (server-side parse + validation), with a row-level
  error report returned to the web client.
- Web pages: `/students`, `/teachers`, `/homerooms`, `/import`.
- Events emitted: `student.enrolled`, `teacher.assigned`.

**Exit criteria:**

- The four demo flows pass an e2e suite against a tenant carried over
  from phase 2.
- The import flow surfaces row-level validation errors and rolls back
  on partial failure.

## Phase 4 — Grading: Grade Capture 🚧

**Owning service**: `grading-service`
**Delivering change**: `mvp-grading-grade-capture`
**Depends on**: Phase 3 (`mvp-academic-ops`) for enrollment and teaching assignments.
**Demo flows:**

1. **Capture grades** — a teacher records per-subject grades for enrolled
   students in an active academic year.
2. **Validate against policy** — grade input uses the grading policy and
   subject passing grades configured in phase 2.

**Scope:**

- New service `grading-service` storing assessment/grade capture records
  for enrolled students and assigned teachers.
- Reads academic-year, subject, and grading-policy data from Academic
  Config and enrollment/teaching-assignment data from Academic Operations.
- Events emitted: `grade.recorded`.

**Exit criteria:**

- A teacher can record and update grades only for subjects/classes they
  are assigned to teach.
- Captured grades are available to the report-card workflow.

## Phase 5 — Report Card Workflow 🚧

**Owning service**: `grading-service`
**Delivering change**: `mvp-report-card-workflow`
**Depends on**: Phase 4 (`mvp-grading-grade-capture`) for captured grades, plus Phase 3 (`mvp-academic-ops`) for enrollment and teaching assignments.
**Demo flows:**

1. **Generate report card** — a homeroom teacher generates report-card drafts from captured subject grades for all enrolled students in a class. Pass/fail is derived from the grading policy at generation time.
2. **Approve report card** — the report card moves through `Draft → HomeroomReview → PrincipalApproval → Published` before publication. Each step is role-gated and appends an audit row.

**Scope:**

- `grading-service` report-card workflow extending phase 4: `report_card` + `report_approval` tables, `grading_policy_projection` table (fed by `grading_policy.configured` event from academic-config-service), and `outbox` table for reliable event publishing.
- State-machine enforcement for `Draft`, `HomeroomReview`, `PrincipalApproval`, `Published`, and `Archived` report cards.
- Grade edit-lock: grades are locked once a report card leaves `Draft`; returning the card to `Draft` re-opens editing.
- Year-close archival: consuming `academic_year.status_changed` with `Closed`/`Archived` transitions all `Published` cards for that year to `Archived`.
- Event emitted: `report_card.approved` (via transactional outbox).
- Web workflow board (`/grading/report-cards`), detail page (`/grading/report-cards/{id}`), and parent/student read-only portal (`/portal/report-card`).

**Exit criteria:**

- A homeroom teacher can generate drafts, submit, get homeroom and principal approval, and the card is Published.
- The approval workflow rejects illegal state transitions (409) and wrong roles (403).
- Grades are locked once a card leaves Draft; returning unlocks them.
- `report_card.approved` event emitted with the correct payload on principal approval.
- Integration tests covering all state transitions; e2e tests cover the full chain and reject/return loop.

## Phase 6 — Tenant User Management 🚧

**Owning service**: `iam-service` (extension)
**Delivering change**: `mvp-tenant-user-management`
**Demo flows:**

1. **Invite tenant user** — the admin invites a teacher / homeroom /
   parent / student account by email; the invitee receives a one-time
   activation link.
2. **Accept invitation** — the invitee sets a password and lands on
   the dashboard with the assigned role.
3. **Manage roles** — the admin promotes / demotes / removes tenant
   users; permission changes take effect on next access token.
4. **Reset password / disable account** — the admin can reset a user's
   password and deactivate accounts.

**Scope:**

- IAM extension: `tenant_invitation` table, invitation issuance +
  redemption endpoints, role change endpoints, user activation lifecycle.
- Web pages: `/settings/users` (list + invite + role change + disable).
- Events emitted: `tenant_user.invited`, `tenant_user.activated`,
  `tenant_user.role_changed`, `tenant_user.disabled`.

**Exit criteria:**

- Invitation links are one-time-use and time-bound.
- Role changes propagate on next access token (no logout required;
  refresh token rotation reissues the access token with the new role).

## Deferred / Future Phases

The following capabilities are intentionally out of scope for phases
1-4 and will land in their own phases later. Each line below lists the
rationale.

- **Attendance** — depends on phase 3 timetable data; no demo value
  before students and teachers exist.
- **Promotion & graduation** — consumes finalized report cards from
  the grading phase.
- **Notification (Email / SMS / WhatsApp)** — needs a real provider
  integration; the phase 1 outbox produces the events but no consumer
  delivers messages until a notification service ships.
- **File / storage service** — needed for student photos, report-card
  PDFs, and import templates; lands when the first consumer (phase 3
  Excel import) becomes a meaningful demo bottleneck.
- **Payment provider integration** — phase 1 subscriptions activate
  without money changing hands. Real payment integration arrives with
  the billing-extension phase that adds invoicing + payment gateway.
- **Email / SMS delivery** — see notification above. The provider
  abstraction lands with the notification service.

## Cross-cutting rules every phase MUST follow

- Every new service uses the standard Makefile target list (`dev`,
  `migrate`, `test`, `build`, `up`, `down`) and ships unit +
  integration tests from day one.
- Every new event payload is documented under
  `docs/internal/11_integration_contracts/events/` *before* the
  delivering change is archived.
- Every new public API is documented under
  `docs/internal/11_integration_contracts/apis/` with request/response
  shapes.
- Every new feature code is added to the canonical `features.toml`
  source of truth and gets a `plan_feature` row for every existing plan
  in the migration that introduces it (no implicit defaults).
- No phase introduces breaking changes to events shipped by a previous
  phase. Breaking changes use `event_type_v2` per
  `04_event_standards.md`.
