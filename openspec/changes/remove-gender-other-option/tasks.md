# Tasks: remove-gender-other-option

Backend submodule `apps/backend`, web submodule `apps/web`.

## 1. Audit existing data

- [ ] 1.1 Run `SELECT count(*) FROM student WHERE gender = 'other'` on dev
      and stage environments.
- [ ] 1.2 If rows exist, decide remediation with product owner (manual fix
      vs. bulk update). Document the decision before proceeding.

## 2. Backend — migration

- [ ] 2.1 Write refinery migration that:
      - Checks for `student` rows with `gender = 'other'`; fails with a
        clear message if any exist.
      - Drops the old CHECK, adds `gender IN ('male', 'female')` on student.
      - Adds `gender IN ('male', 'female')` CHECK on teacher (nullable,
        currently unconstrained).
- [ ] 2.2 Test migration on a clean DB and on a DB with an 'other' row
      (verify failure).

## 3. Backend — validation

- [ ] 3.1 In `academic-ops-service/src/commands.rs`:
      `validate_student_fields` — change gender validation to accept only
      `"male" | "female"`.
- [ ] 3.2 `validate_gender` (teacher) — same change.
- [ ] 3.3 Update error messages to reflect the new allowed set.
- [ ] 3.4 Update/add unit tests for the validation functions.

## 4. Web — schema and UI

- [ ] 4.1 In `lib/schemas/academic-ops.ts`: change gender from
      `z.enum(["male","female","other"])` to `z.enum(["male","female"])`.
      Keep teacher gender as `.optional()` / nullable.
- [ ] 4.2 In `students-screen.tsx` (StudentDialog ~line 666-688): remove the
      `<SelectItem value="other">Lainnya</SelectItem>`.
- [ ] 4.3 In `teachers-screen.tsx` (~line 699-721): remove the same
      `<SelectItem>`.
- [ ] 4.4 Update the `genderLabel` helper if it has an "other" case.

## 5. Verification

- [ ] 5.1 `make test` (backend + web) green.
- [ ] 5.2 Create student/teacher with male → succeeds. With female →
      succeeds. "Lainnya" not offered in UI. API rejects `"other"` if sent
      directly.
