## ADDED Requirements

### Requirement: Grading service SHALL handle `student.unenrolled` event

The grading service MUST subscribe to `student.unenrolled` events from the
academic-ops event bus. Upon receiving the event, the service MUST update the
corresponding `enrolled_student` projection row, setting `status` to
`'inactive'`. If no matching row exists, the event MUST be acknowledged
without error (idempotent).

#### Scenario: Unenroll event deactivates projection

- **WHEN** the grading service receives a `student.unenrolled` event for a student with an `active` `enrolled_student` row
- **THEN** the `enrolled_student` row is updated to `status='inactive'` and the event is acknowledged

#### Scenario: Unenroll event for non-projected student is ignored

- **WHEN** the grading service receives a `student.unenrolled` event for a student that has no `enrolled_student` row
- **THEN** the event is acknowledged without error and a warning is logged

#### Scenario: Duplicate unenroll event is idempotent

- **WHEN** the grading service receives a `student.unenrolled` event for a student whose `enrolled_student` row is already `status='inactive'`
- **THEN** the row remains unchanged and the event is acknowledged
