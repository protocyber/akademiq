## MODIFIED Requirements

### Requirement: Gender validation SHALL accept only male and female

The `validate_student_fields` and `validate_gender` functions in
academic-ops-service MUST accept only `"male"` and `"female"`. Any other
value (including `"other"`) MUST be rejected with `VALIDATION_ERROR`.

#### Scenario: Student with male or female succeeds

- **WHEN** a student is created/updated with `gender = "male"` or `"female"`
- **THEN** the operation succeeds

#### Scenario: Student with other gender fails

- **WHEN** a student is created/updated with `gender = "other"` (or any
  non-male/female value)
- **THEN** the response is `VALIDATION_ERROR` with field `gender` indicating
  only male/female are accepted

### Requirement: The student table SHALL enforce gender CHECK constraint

The `student` table MUST have a CHECK constraint
`gender IN ('male', 'female')`. The migration MUST fail if any existing row
has a gender value outside this set, directing the operator to remediate
before retrying.

#### Scenario: Migration succeeds when no other-gender rows exist

- **WHEN** the migration runs and no student has `gender = 'other'`
- **THEN** the CHECK constraint is tightened to `IN ('male', 'female')`

#### Scenario: Migration fails when other-gender rows exist

- **WHEN** the migration runs and at least one student has `gender = 'other'`
- **THEN** the migration fails with a clear error message; no data is
  silently changed

### Requirement: The teacher table SHALL enforce gender CHECK constraint

The `teacher` table MUST have a CHECK constraint
`gender IN ('male', 'female')` on the `gender` column (which is nullable).
The constraint MUST allow NULL (gender is optional for teachers) but MUST
reject non-male/female values.

#### Scenario: Teacher with null gender succeeds

- **WHEN** a teacher is created/updated with no gender specified
- **THEN** the operation succeeds (NULL is allowed)

#### Scenario: Teacher with other gender fails

- **WHEN** a teacher is created/updated with `gender = "other"`
- **THEN** the response is `VALIDATION_ERROR`
