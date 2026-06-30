## MODIFIED Requirements

### Requirement: The importer SHALL translate Indonesian gender labels

`parse_students` and `parse_teachers` in `imports.rs` MUST translate common
Indonesian gender labels to their English backend values before passing to
validation. The mapping MUST include at minimum: `laki-laki`/`laki laki`/
`pria`/`l` → `male`; `perempuan`/`wanita`/`p` → `female`. Values that are
already `male`/`female` MUST pass through unchanged. Unknown values MUST
pass through to validation (which rejects them).

#### Scenario: Indonesian gender label in student import

- **WHEN** a student import file has `gender = "Laki-laki"` in a row
- **THEN** the importer translates it to `"male"` and the row is accepted

#### Scenario: English gender value passes through

- **WHEN** a student import file has `gender = "male"` in a row
- **THEN** the value is accepted as-is (no translation needed)

#### Scenario: Unknown gender value rejected

- **WHEN** a student import file has `gender = "xyz"` in a row
- **THEN** the translation does not match; validation rejects it with
  `VALIDATION_ERROR`

### Requirement: The template endpoint SHALL return column metadata

`GET /api/v1/academic-ops/imports/template` MUST return the column list with
Indonesian labels, required/optional flags, and format hints for both
student and teacher templates. This enables the frontend to render dynamic
guidance if needed.

#### Scenario: Template metadata response

- **WHEN** a client calls `GET /imports/template`
- **THEN** the response includes for each column: `field` (English key),
  `label` (Indonesian), `required` (boolean), and `format` (e.g. "date",
  "integer", "text")
