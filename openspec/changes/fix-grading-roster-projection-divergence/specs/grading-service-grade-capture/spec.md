## MODIFIED Requirements

### Requirement: Grade recording SHALL be authorized by teaching assignment and enrollment

The service MUST allow a grade write only when the recording teacher is assigned
to the evaluation's subject in the student's homeroom for the year AND the
student is actively enrolled there. The subject/homeroom/year used for this
check MUST come from the referenced evaluation. The student-active-enrollment
check MUST read the grading service's own `enrolled_student` projection, and the
grade-entry roster surfaced to teachers MUST be sourced from that same
projection, so that the students shown are exactly the students for whom a grade
may be recorded.

#### Scenario: Unassigned teacher is rejected

- **WHEN** a teacher records a grade for an evaluation whose subject or class they are not assigned to
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no grade is stored

#### Scenario: Grade for a non-enrolled student is rejected

- **WHEN** a teacher records a grade for a student who is not actively enrolled in the evaluation's homeroom for the year
- **THEN** the response is HTTP 422 `STUDENT_NOT_ENROLLED`

#### Scenario: Teacher account not linked to a profile

- **WHEN** the recording user's account is not linked to any teacher profile referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ACCOUNT_NOT_LINKED`

#### Scenario: A student shown in the entry roster is always submittable

- **WHEN** a student appears in the grade-entry roster for a homeroom+year and the assigned teacher submits a grade for them
- **THEN** the grade is accepted, because the roster and the write check read the same projection

## ADDED Requirements

### Requirement: The grading service SHALL serve a roster from its own enrollment projection

The service MUST provide `GET /api/v1/grading/homerooms/{homeroom_id}/roster?academic_year_id=`,
tenant-scoped, returning the actively-enrolled students for that homeroom+year
from the `enrolled_student` projection — the same table the grade-write
authorization check reads. Each row MUST include `student_id`, `full_name`, and
`nis` (denormalized into the projection from enrollment/profile events) so the
roster is display-ready without a cross-service call. The endpoint MUST require
`grade.read`. The set of students it returns MUST equal exactly the set for
which a grade can be recorded for that scope.

#### Scenario: Roster returns active students for a class+year

- **WHEN** a client GETs the roster for a homeroom and academic year
- **THEN** the response lists the actively-enrolled students with their `student_id`, `full_name`, and `nis`, tenant-scoped

#### Scenario: Roster and write check share one source

- **WHEN** a student is present in the roster response for a scope
- **THEN** a grade submitted for that student in that scope passes the enrollment check (no `STUDENT_NOT_ENROLLED`)

#### Scenario: Roster read without grade.read is forbidden

- **WHEN** a caller without `grade.read` GETs the roster endpoint
- **THEN** the response is HTTP 403

### Requirement: The enrolled_student projection SHALL carry display fields

The `enrolled_student` projection MUST store `full_name` and `nis` alongside the
enrollment tuple, populated when a `student.enrolled` event is applied and
updated when a student's profile fields change (via the corresponding profile
event). This makes the projection self-sufficient for roster display so the
grade-entry UI does not depend on a cross-service roster read.

#### Scenario: Enrollment event populates display fields

- **WHEN** a `student.enrolled` event carrying `full_name` and `nis` is applied to the projection
- **THEN** the `enrolled_student` row stores those values and the roster endpoint returns them

#### Scenario: Profile update refreshes the projected name

- **WHEN** a student's `full_name` changes and the profile-update event is applied
- **THEN** the `enrolled_student` row's `full_name` is updated and subsequent roster reads return the new name
