## Why

A report card is an aggregation of per-subject grades. Before we can build the
report-card approval workflow, those grades must exist. This change delivers
the **grade-capture half of the `grading-service`**: subject teachers record
and update scores for the students they are assigned to teach. It is the third
link in the chain to "create a report card".

```
Academic Config → Academic Ops → Grading: grade capture → Report Card workflow
   (done)            (done)         (this change)            (next change)
```

Splitting grading into two changes keeps each a demoable vertical slice: this
one proves "a teacher can enter grades for their class"; the next builds the
Draft → Review → Approval → Published state machine on top of the grades. This
is the **Grade Capture phase** promoted out of the former "deferred" section by
`mvp-academic-config`.

## What Changes

### Backend — new service `grading-service` (grade capture only)

- New crate `apps/backend/services/grading-service`, same module layout as
  `iam-service`, CQRS-separated, refinery migrations.
- Table per `docs/internal/10_data_design/06_Grading_Service_ERD.md`:
  `grade` (`grade_id`, `tenant_id`, `student_id`, `subject_id`,
  `academic_year_id`, `score`, plus `homeroom_id`, `recorded_by`, audit
  timestamps). The `report_card` / `report_approval` tables are introduced by
  the **next** change.
- **Event consumers** (build authorization + validity projections, no
  synchronous calls):
  - `teacher.assigned` (from ops) → `teaching_authz` projection: which
    `(teacher user, subject, homeroom, year)` may record grades.
  - `student.enrolled` (from ops) → `enrolled_student` projection: which
    students are gradeable in which homeroom/year.
  - `academic_year.created` (from config) → valid year + (read grading policy
    via config API when needed).
  - `subscription.activated` → subscription gating.
- **Authorization rule**: a teacher may only record a grade for a
  `(student, subject)` where (a) a teaching assignment links that teacher's
  account to that subject + the student's homeroom for the year, and (b) the
  student is actively enrolled there. Violations → 403 `NOT_ASSIGNED`.
- **Feature gate**: `grading` feature code via entitlement middleware.
- HTTP API under `/api/v1/grading`:
  - `POST /grades` — record a score `{ student_id, subject_id,
    academic_year_id, score }` (the teacher is the JWT subject; homeroom
    derived from enrollment). Idempotent upsert per
    `(student, subject, year)`.
  - `PATCH /grades/{id}` — update a score (allowed while no report card for
    that student/year is past Draft — enforced trivially here since report
    cards arrive in the next change; for now grades are freely editable).
  - `GET /grades?homeroom_id=&subject_id=&academic_year_id=` — teacher's
    grade entry grid for a class+subject.
  - `GET /students/{id}/grades?academic_year_id=` — all of a student's grades
    for a year (the raw material the report card will aggregate).
  - `GET /healthz`.
- Score validated against the subject's `passing_grade` context only for
  display; the hard bound is `score ∈ [0,100]` (configurable by grading
  scale). Pass/fail derivation lives with the report card.

### Web — grade entry

- `/grading/entry`: teacher selects their assigned homeroom + subject, sees the
  class roster (from ops) as a grade-entry grid, enters/edits scores with
  per-row inline save (spinner). Read-only for non-assigned classes.
- shadcn/ui + TanStack Query + RHF/Zod + two-tier loading.

### Tests & docs

- Unit (authorization rule, score bounds, upsert idempotency), integration
  (testcontainer with seeded projections), e2e: register → year+subjects →
  students+homeroom+enroll+assign teacher → teacher logs in → records grades →
  reads them back. Playwright on the entry grid. API contract documented;
  `grade` event(s) if any documented.

## Capabilities

### New Capabilities

- `grading-service-grade-capture`: defines grade recording and update,
  the teacher-assignment + enrollment authorization rule, the projections fed
  by `teacher.assigned` / `student.enrolled` / `academic_year.created`, score
  validation, and the per-student grade query the report card aggregates.

## Impact

- **New code**: `services/grading-service` crate (grade tables + handlers);
  web `/grading/entry`. **Depends on**: `mvp-academic-ops`
  (`teacher.assigned`, `student.enrolled`, roster), `mvp-academic-config`
  (subjects, grading policy), and ideally `mvp-tenant-user-management` (real
  teacher accounts; seeds can stand in). **Blocks**:
  `mvp-report-card-workflow`.
- **Out of scope**: report card generation, approval states, publication,
  PDF, notification — all in the next change. No grade weighting/components
  (single score per subject for MVP).
