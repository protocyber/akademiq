# Design — grade-entry-evaluations

## Data model

```
evaluation (NEW)
  evaluation_id   UUID PK
  tenant_id       UUID
  homeroom_id     UUID        ┐ scope: one list per
  subject_id      UUID        │ (homeroom × subject × year)
  academic_year_id UUID       ┘
  code            VARCHAR   "UH1"
  name            VARCHAR   "Ulangan Harian 1"
  position        INT        column order
  created_at / updated_at
  UNIQUE (tenant_id, homeroom_id, subject_id, academic_year_id, code)

grade (CHANGED)
  grade_id        UUID PK
  tenant_id       UUID
  student_id      UUID
  evaluation_id   UUID  → evaluation        (was subject_id+year)
  score           DOUBLE  CHECK 0..100
  recorded_by     UUID
  created_at / updated_at
  UNIQUE (tenant_id, student_id, evaluation_id)   (was student+subject+year)
```

`homeroom_id`, `subject_id`, `academic_year_id` are denormalized onto
`evaluation` (not onto `grade`) so the grid query — "all evaluations + all
grades for this class+subject+year" — is two indexed reads. Authorization
(teaching assignment + enrollment) is unchanged; it keys on the evaluation's
`(subject_id, homeroom_id, academic_year_id)`.

## Grade-entry screen

```
┌ /grading/entry ──────────────────────────────────────────────┐
│ Entri Nilai                                                    │
│ [Tahun ▾] [Kelas ▾] [Mapel ▾]            [Kelola Evaluasi]    │ ← shown only
│                                            ↑ opens modal        │   when kelas
├──────────┬───────┬───────┬───────┬───────┐                     │   AND mapel set
│ Siswa    │ UH1   │ UH2   │ UTS   │ UAS   │  ← columns =         │
├──────────┼───────┼───────┼───────┼───────┤    evaluations      │
│ Andi     │ 80 ✓  │ 90 ✓  │ 75 ⟳  │  __   │                     │
│ Budi     │ 85 ✓  │  __   │ 80 ⚠  │  __   │  ⚠ retry on error   │
└──────────┴───────┴───────┴───────┴───────┘                     │
└────────────────────────────────────────────────────────────────┘
```

**Per-cell auto-save.** Each cell owns its own draft + status state. On blur (or
debounce), if the value changed and is valid (0–100), it fires the grade upsert
keyed by `(student_id, evaluation_id)`. Status badge: idle → saving (⟳) → saved
(✓), or error (⚠) with the previous value retained and a retry affordance.
Invalid input (out of range, non-numeric) shows inline and does not fire a save.

**Kelola Evaluasi modal.** A small datatable (Kode, Nama, Urutan) with
add/edit/delete and reorder, scoped to the selected class+subject+year. Deleting
an evaluation that has grades requires confirmation (its grades are removed with
it — cascade). Empty state prompts adding the first evaluation; until at least
one evaluation exists, the grid shows an empty-columns hint.

## API (grading service)

```
GET    /api/v1/grading/evaluations?homeroom_id&subject_id&academic_year_id
POST   /api/v1/grading/evaluations          { homeroom_id, subject_id,
                                              academic_year_id, code, name, position }
PATCH  /api/v1/grading/evaluations/{id}     { code?, name?, position? }
DELETE /api/v1/grading/evaluations/{id}     (cascades its grades)

POST   /api/v1/grading/grades               { student_id, evaluation_id, score }  (upsert)
GET    /api/v1/grading/grades?homeroom_id&subject_id&academic_year_id  → joined via evaluation
```

`POST /grades` is an idempotent upsert on `(tenant, student, evaluation_id)`,
replacing the old subject+year upsert. The grid read returns grades for every
evaluation of the class+subject+year so the frontend can index by
`(student_id, evaluation_id)`.

## Authorization

Unchanged in spirit: a teacher may write a grade only when assigned to the
evaluation's subject in the student's homeroom for the year, and the student is
actively enrolled. Evaluation CRUD requires the same teaching-assignment scope
(or tenant admin).

## Migration

None. Per the interview, existing grade data may be dropped. The migration
replaces the `grade` uniqueness constraint and column (`subject_id`,
`academic_year_id` → `evaluation_id`) and adds the `evaluation` table; existing
rows are not preserved.
