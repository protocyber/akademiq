# Design — Grading Service: Grade Capture

## Context

Third link toward "create a report card". Produces the raw `grade` rows the
report card aggregates. Deliberately scoped to *capture only* — the report-card
state machine is the next change — so this ships as a small, demoable slice.

## Key decisions

### 1. Authorization by projection, not synchronous calls

The core rule: *a teacher may record a grade only for a subject + student they
are assigned to teach this year.* That fact lives in academic-ops
(`teaching_assignment`) and is announced via `teacher.assigned`. The grading
service consumes that event into a local `teaching_authz` projection and
consumes `student.enrolled` into an `enrolled_student` projection, then
authorizes writes locally:

```
ops.teaching_assignment ──teacher.assigned──▶ grading.teaching_authz
ops.enrollment          ──student.enrolled──▶ grading.enrolled_student
config.academic_year    ─academic_year.created▶ grading.valid_year

record grade(student, subject, year) is allowed IFF
   ∃ teaching_authz(teacher_user, subject, homeroom, year)
   ∧ enrolled_student(student, homeroom, year, active)
```

This keeps grading independent of ops/config uptime and makes the
authorization check a single indexed lookup.

### 2. Teacher account ↔ teacher profile resolution

The JWT identifies a `user_id` + `role`, but `teaching_assignment` references a
`teacher_id` (the ops profile). `teacher.assigned` carries `teacher_id`; we
need to map the logged-in `user_id` to that `teacher_id`. For MVP we resolve by
the email/identity link established in tenant-user-management (the teacher
account's email matches the teacher profile). The projection therefore stores
the resolved `teacher_user_id` when available; if a teaching assignment has no
matching login account yet, grade entry for it is blocked with a clear
`TEACHER_ACCOUNT_NOT_LINKED` error rather than a silent 403.

### 3. One score per (student, subject, year) — upsert

MVP grading is a single final score per subject (no weighted components,
quizzes, etc.). `POST /grades` is an idempotent upsert keyed by
`(tenant_id, student_id, subject_id, academic_year_id)`. Re-posting updates the
score and bumps `updated_at` + `recorded_by`. This makes the entry grid's
per-row save trivial and avoids duplicate-grade bugs.

### 4. Score bounds now, pass/fail later

This change validates `score ∈ [0,100]` (or the range implied by the year's
`grading_scale`, read from config). It does **not** compute pass/fail — that is
a report-card concern that reads `grading_policy.minimum_passing_score` when
the draft is generated in the next change. Keeping derivation out of capture
means changing the policy later re-derives correctly from stored scores.

### 5. Editability window is trivial here, real next change

The report-card lifecycle locks grades once a card leaves Draft. Since report
cards don't exist yet, grades are freely editable in this change. We still
route edits through a `can_edit_grade(student, year)` checkpoint that currently
always returns true, so the next change only has to implement the predicate —
the call site already exists. (This is the one forward-looking seam we allow,
because it's a single function the next change fills in.)

## Data model (refinery `V1__init.sql`)

| Table | Key columns | Notes |
|-------|-------------|-------|
| `grade` | `grade_id` PK, `tenant_id`, `student_id`, `subject_id`, `academic_year_id`, `homeroom_id`, `score`, `recorded_by`, `created_at`, `updated_at` | unique `(tenant_id, student_id, subject_id, academic_year_id)` |
| `teaching_authz` | `(teacher_user_id, teacher_id, subject_id, homeroom_id, academic_year_id)` | projection from `teacher.assigned` |
| `enrolled_student` | `(student_id, homeroom_id, academic_year_id, status)` | projection from `student.enrolled` |
| `valid_year` | `academic_year_id`, `tenant_id`, `status` | projection from `academic_year.created` |
| `tenant_subscription_state` | `tenant_id`, `status`, `valid_until` | projection from `subscription.activated` |

Indexes: `grade(homeroom_id, subject_id, academic_year_id)` for the entry grid,
`grade(student_id, academic_year_id)` for the report-card aggregation,
`teaching_authz(teacher_user_id, subject_id, homeroom_id, academic_year_id)`.

## Alternatives considered

- **Weighted grade components (quiz/mid/final)** — rejected for MVP: the ERD
  models a single `score`; richer grading is a later enhancement.
- **Synchronous authz call to ops per write** — rejected: couples services;
  projections are cheap and already idiomatic.
- **Compute pass/fail at capture** — rejected: belongs to the report card so
  policy changes re-derive correctly.

## Risks

- **Projection lag**: a freshly assigned teacher might briefly be unable to
  grade until `teacher.assigned` is consumed. The e2e waits for the projection;
  the UI shows "syncing assignments".
- **Unlinked teacher account** → blocked grade entry. Surfaced explicitly;
  resolved by linking the account (tenant-user-management) to the profile.
