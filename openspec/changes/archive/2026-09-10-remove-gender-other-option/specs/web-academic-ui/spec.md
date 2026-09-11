## MODIFIED Requirements

### Requirement: Gender selects SHALL offer only male and female

All gender `<Select>` components (student form, teacher form) MUST render
exactly two options: "Laki-laki" (`male`) and "Perempuan" (`female`). The
"Lainnya" / `"other"` option MUST NOT appear.

#### Scenario: Student form gender field

- **WHEN** a user opens the student creation/edit form
- **THEN** the gender select shows only "Laki-laki" and "Perempuan"; no
  "Lainnya" option is available

#### Scenario: Teacher form gender field

- **WHEN** a user opens the teacher creation/edit form
- **THEN** the gender select shows only "Laki-laki" and "Perempuan" (plus an
  optional empty/none state since gender is nullable for teachers)

### Requirement: Gender schema SHALL enforce male or female only

The Zod schema for student and teacher gender MUST be
`z.enum(["male", "female"])` (for students, required; for teachers,
`.optional()` or nullable). The value `"other"` MUST be rejected by the
schema.

#### Scenario: Schema rejects other

- **WHEN** a form submits with `gender = "other"`
- **THEN** client-side Zod validation rejects the value before the API call
