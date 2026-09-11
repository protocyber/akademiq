## Why

The gender field (jenis kelamin) across all forms currently offers three
options: Laki-laki (`male`), Perempuan (`female`), and Lainnya (`other`).
The product requirement is to remove "Lainnya" — only `male` and `female`
are valid.

This touches three layers:

- **Frontend schemas**: `z.enum(["male","female","other"])` in
  `lib/schemas/academic-ops.ts:13` and the `<Select>` options in
  `students-screen.tsx:666-688` and `teachers-screen.tsx:699-721`.
- **Backend validation**: `validate_student_fields`
  (`academic-ops-service/src/commands.rs:1350-1357`) and `validate_gender`
  (`commands.rs:1380-1385`) accept `"male" | "female" | "other"`.
- **Database constraint**: student table CHECK
  `gender IN ('male', 'female', 'other')` (`V1__init.sql:12`); teacher table
  has no CHECK on gender (`V6__expand_student_teacher_profiles.sql:52`).
- **Excel import**: gender is lowercased but not translated, so
  "Laki-laki"/"Perempuan"/"Lainnya" in a cell fails validation.

Additionally, the dashboard gender breakdown query
(`repo.rs:1732-1819` `GenderBreakdown`) only counts `male` and `female` —
`other` students are silently excluded from totals.

## What Changes

- **Frontend**: remove the `"other"` / "Lainnya" `<SelectItem>` from all
  gender selects (student form, teacher form). Change the Zod schema to
  `z.enum(["male","female"])`.
- **Backend**: change `validate_student_fields` and `validate_gender` to
  accept only `"male" | "female"`. Any request with `"other"` is rejected
  with `VALIDATION_ERROR`.
- **Database migration**: change the student table CHECK constraint from
  `gender IN ('male','female','other')` to `gender IN ('male','female')`.
  Any existing rows with `gender = 'other'` must be handled (migrated or
  blocked) before the constraint is tightened.
- **Dashboard breakdown**: no change needed (already only counts male/female).

## Capabilities

### Modified Capabilities
- `academic-ops-service`: gender validation restricted to `male`/`female`;
  DB CHECK constraint tightened.
- `web-academic-ui`: gender field renders only Laki-laki / Perempuan;
  schema enforces `male`/`female` only.

## Impact

- **Backend** (`apps/backend`):
  - `services/academic-ops-service`: migration to tighten CHECK constraint;
    `commands.rs` validation changes.
  - **Data migration decision needed**: if any existing rows have
    `gender = 'other'`, they must be updated or the migration will fail.
    See Open Questions.
- **Web** (`apps/web`):
  - `lib/schemas/academic-ops.ts`: schema change.
  - `components/features/academic-ops/students-screen.tsx`,
    `teachers-screen.tsx`: remove "Lainnya" SelectItem.
- **Breaking** for any API client that sends `"other"` — will receive
  `VALIDATION_ERROR` after deployment.
