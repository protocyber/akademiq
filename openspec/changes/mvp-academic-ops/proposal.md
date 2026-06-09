## Why

To create a report card the system needs a concrete student, enrolled in a
homeroom for an academic year, taught a set of subjects by assigned teachers.
Phase 2 (`mvp-academic-config`) created the year, subjects, and grading
policy. This change delivers the **second link**: the `academic-ops-service`
that owns the operational academic data — students, teachers, homerooms,
enrollments, and teaching assignments.

```
Academic Config → Academic Ops → Grading (grade capture) → Report Card workflow
   (done)          (this change)
```

Without enrollment there is no "which students get a report card", and without
teaching assignments there is no "which teacher may grade which subject for
which class". Both are prerequisites the grading phases consume directly. This
corresponds to **Phase 3 — Academic Operations** in
`docs/internal/13_engineering_standards/16_implementation_phases.md`.

## What Changes

### Backend — new service `academic-ops-service`

- New crate `apps/backend/services/academic-ops-service` in the workspace,
  same module layout as `iam-service`, CQRS-separated, refinery migrations.
- Tables per `docs/internal/10_data_design/04_Academic_Operations_ERD.md`:
  `student`, `teacher`, `homeroom`, `enrollment`, `teaching_assignment`,
  `timetable`. All carry `tenant_id`; all reads tenant-scoped from the JWT.
- **Event consumers**:
  - `academic_year.created` (from phase 2) → records valid academic-year ids
    so homerooms can only be created for a known, active year.
  - `subscription.activated` (from phase 1) → subscription projection gating
    writes behind an active subscription.
- **Feature-entitlement gate**: write endpoints behind the `academic_ops`
  feature code; non-entitled tenants → 403 `FEATURE_NOT_AVAILABLE`.
- HTTP API under `/api/v1/academic-ops`:
  - Students: `POST /students`, `GET /students`, `GET /students/{id}`,
    `PATCH /students/{id}` (NIS, full name, gender, birth date).
  - Teachers: `POST /teachers`, `GET /teachers`, `GET /teachers/{id}` (NIP,
    full name).
  - Homerooms: `POST /homerooms` (name, grade_level, capacity,
    academic_year_id), `GET /homerooms`, `GET /homerooms/{id}/students`.
  - Enrollment: `POST /enrollments` (student → homeroom for the year),
    `DELETE /enrollments/{id}`; one active enrollment per student per year.
  - Teaching assignments: `POST /teaching-assignments` (teacher + subject +
    homeroom + year), `GET /homerooms/{id}/teaching-assignments`.
  - `GET /healthz`.
- **Excel import** (students + teachers): `POST /imports/students` and
  `POST /imports/teachers` accept a spreadsheet, parse + validate server-side,
  and return a **row-level error report**; a partial-failure import rolls back
  (no half-imported batch), per the phase-3 exit criteria.
- **Events emitted**: `student.enrolled` (existing contract
  `events/student-enrolled.md`) and `teacher.assigned`. Both consumed by the
  grading phase to know who may be graded and who may grade.

### Web — operational pages

- `/students` (list + manual create + edit), `/teachers` (list + create),
  `/homerooms` (list + create + roster view + enroll students),
  `/teaching-assignments` (assign teacher↔subject↔homeroom), `/import`
  (upload + row-level error display). shadcn/ui + TanStack Query + RHF/Zod +
  two-tier loading per `apps/web/CONVENTIONS.md`.

### Tests & docs

- Unit (NIS/NIP validation, single-active-enrollment rule, import row
  validation), integration (testcontainer), cross-service e2e: register tenant
  → create year + subjects (phase 2) → add students/teachers → create homeroom
  → enroll → assign teacher. Playwright on the web flow, including a failing
  import that surfaces row errors and rolls back.
- API + event contracts under `docs/internal/11_integration_contracts/`;
  roadmap Phase 3 status flipped.

## Capabilities

### New Capabilities

- `academic-ops-service`: defines student & teacher master data, homerooms,
  enrollment (one active per student per year), teaching assignments, Excel
  import with row-level validation and rollback, the
  `academic_year.created` / `subscription.activated` consumption, and the
  `student.enrolled` / `teacher.assigned` events the grading phases consume.

## Impact

- **New code**: `services/academic-ops-service` crate + migrations; web pages;
  e2e additions. Excel parsing dependency added to the workspace.
- **Depends on**: `mvp-academic-config` (`academic_year.created`, subject ids,
  active-year rule) and phase 1. **Blocks**: `mvp-grading-grade-capture`.
- **Out of scope**: attendance (separate phase), grades/report cards (later
  phases), timetable automation beyond CRUD, student photos / file storage.
