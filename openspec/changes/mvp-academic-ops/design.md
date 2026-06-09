# Design — Academic Operations Service

## Context

Second link toward "create a report card". Turns the abstract year/subjects
from config into concrete people and class structure: students, teachers,
homerooms, enrollments, teaching assignments. The grading phases read this
service's data and events to decide *who is graded* and *who may grade*.

## Key decisions

### 1. Cross-service references are by id, validated against projections

`homeroom.academic_year_id` and `teaching_assignment.subject_id` point at
rows owned by academic-config. Ops does not call config synchronously per
write. Instead it keeps two projections fed by events:

```
academic-config ──academic_year.created──▶ ops.known_academic_year (id, status)
billing         ──subscription.activated─▶ ops.tenant_subscription_state
```

`subject_id` is trickier: config does not currently emit a per-subject event.
For MVP, ops validates `subject_id` lazily — a teaching assignment stores the
id and the **grading service** is the component that enforces the subject is
real when a grade is recorded (it reads the config catalog). Ops only checks
that the referenced homeroom's `academic_year_id` is a known active year.
This keeps ops decoupled and pushes subject validation to the point of use.
(If subject drift becomes a problem we add a `subject.created` event later —
noted as a non-breaking future addition.)

### 2. Enrollment invariant: one active enrollment per student per year

The report card is "per student per academic year", so a student must resolve
to exactly one homeroom in a year. Enforced with a partial unique index on
`enrollment(student_id, academic_year_id) WHERE status='active'`. Re-enrolling
(transfer between homerooms) marks the old enrollment `transferred` and inserts
a new `active` one in a single transaction.

```
student ──enrollment(active)──▶ homeroom ──(in academic_year)
   │
   └── at most ONE active enrollment per (student, year)  ◀── unique index
```

### 3. Teaching assignment is the authorization seam for grading

`teaching_assignment(teacher_id, subject_id, homeroom_id, academic_year_id)`
is what the grading service later checks to answer *"may this teacher record a
grade for this subject in this class?"*. We emit `teacher.assigned` carrying
exactly that tuple so grading can build its own projection rather than calling
ops on every grade write. This is the most important downstream contract in
this change.

### 4. Excel import: parse → validate-all → all-or-nothing

Import is the riskiest flow. The handler:

1. Parses the sheet into rows (a fixed template; column headers validated).
2. Validates **every** row (required fields, NIS/NIP format, duplicates within
   the file, duplicates against existing rows), collecting per-row errors.
3. If **any** row fails, returns HTTP 422 with a row-indexed error report and
   writes **nothing** (single transaction, rolled back).
4. If all rows pass, inserts them in one transaction and returns a summary.

```
upload ─▶ parse ─▶ validate ALL rows ─┬─ any error ─▶ 422 { rows: [{row, errors}] }, DB untouched
                                      └─ all ok ────▶ 201 { imported: N }, single tx commit
```

We choose all-or-nothing over partial import because a half-imported roster is
hard for a school admin to reconcile; a clean re-upload after fixing the sheet
is simpler and matches the roadmap's "rolls back on partial failure" criterion.

### 5. Homeroom roster query feeds the report card batch

`GET /homerooms/{id}/students` is the query the grading phase uses to generate
report-card drafts for a whole class. We make it return the active-enrollment
roster (student id, NIS, name) so the grading service can iterate students of a
class for a year without re-deriving enrollment.

## Data model (refinery `V1__init.sql`)

| Table | Key columns | Notes |
|-------|-------------|-------|
| `student` | `student_id` PK, `tenant_id`, `nis`, `full_name`, `birth_date`, `gender` | unique `(tenant_id, nis)` |
| `teacher` | `teacher_id` PK, `tenant_id`, `nip`, `full_name` | unique `(tenant_id, nip)` |
| `homeroom` | `homeroom_id` PK, `tenant_id`, `name`, `grade_level`, `capacity`, `academic_year_id` | |
| `enrollment` | `enrollment_id` PK, `student_id` FK, `homeroom_id` FK, `academic_year_id`, `status` | partial unique active per (student, year) |
| `teaching_assignment` | `assignment_id` PK, `teacher_id` FK, `subject_id`, `homeroom_id` FK, `academic_year_id` | unique `(teacher_id, subject_id, homeroom_id, academic_year_id)` |
| `timetable` | `timetable_id` PK, `homeroom_id` FK, `subject_id`, `teacher_id` FK, `day_of_week`, `start_time`, `end_time` | plain CRUD, no automation |
| `known_academic_year` | `academic_year_id` PK, `tenant_id`, `status` | projection from `academic_year.created` |
| `tenant_subscription_state` | `tenant_id` PK, `status`, `valid_until` | projection from `subscription.activated` |

## Alternatives considered

- **Synchronous validation of subject_id against config** — rejected for MVP:
  couples ops to config uptime; subject validity is enforced where it matters
  (grade recording). Revisit with a `subject.created` event if needed.
- **Partial Excel import (skip bad rows)** — rejected: leaves the roster in an
  ambiguous state; all-or-nothing is cleaner for a non-technical admin.
- **Storing roster snapshots in grading** — rejected: ops stays the source of
  truth for enrollment; grading queries the roster instead of duplicating it.

## Risks

- **Import performance** on large sheets — bounded for MVP (single tenant
  upload, hundreds of rows). Streaming/batched import is a later optimization;
  log the row count handled.
- **Subject id drift** — if config deletes a subject after assignment, the
  grade write will fail validation downstream. Acceptable for MVP; surfaced as
  a clear error at grade time.
