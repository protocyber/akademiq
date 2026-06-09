## ADDED Requirements

### Requirement: Grades SHALL be locked once a report card leaves Draft

The service MUST treat a grade as editable only when the student has no report
card for that year or the report card is in `Draft`. The grade-capture
`can_edit_grade(student, academic_year_id)` checkpoint (introduced as an
always-true stub in `mvp-grading-grade-capture`) MUST become this real
predicate. Once the report card is in `HomeroomReview`, `PrincipalApproval`,
`Published`, or `Archived`, grade writes and updates MUST be rejected.

#### Scenario: Grade edit is rejected after submission

- **WHEN** a teacher tries to record or update a grade for a student whose report card for that year is in `HomeroomReview` or later
- **THEN** the response is HTTP 409 `GRADES_LOCKED` and the grade is unchanged

#### Scenario: Returning a card re-opens grade editing

- **WHEN** a homeroom teacher returns a card to `Draft` for correction
- **THEN** grades for that student and year become editable again and a subsequent valid grade update succeeds

#### Scenario: Grades editable before any report card exists

- **WHEN** a teacher records a grade for a student/year that has no report card yet
- **THEN** the grade is recorded normally
