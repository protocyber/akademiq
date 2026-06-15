# Design — report-card-batches

> Builds on `grade-entry-evaluations` (the `evaluation` table and grades keyed by
> `evaluation_id`).

## Data model

```
report_batch (NEW)
  batch_id        UUID PK
  tenant_id       UUID
  homeroom_id     UUID
  academic_year_id UUID
  name            VARCHAR   "Rapor Tengah Semester"
  created_at / updated_at
  (admin creates several per homeroom+year)

report_formula (NEW)              one per (batch × subject) — a whole class
  batch_id        UUID  → report_batch
  subject_id      UUID
  weights         JSONB  { "<evaluation_id>": 25, "<evaluation_id>": 75 }
  updated_at
  UNIQUE (batch_id, subject_id)
  -- valid only when Σ weights == 100; else subject is skipped at compute

report_card (CHANGED)
  report_card_id  UUID PK
  tenant_id, student_id, homeroom_id, academic_year_id
  batch_id        UUID  → report_batch       (NEW)
  status          VARCHAR  (5-status, unchanged)
  summary         JSONB
  published_at, created_at, updated_at
  UNIQUE (batch_id, student_id)              (was (student, year))

report_subject_score (NEW)        frozen compute snapshot
  report_card_id  UUID  → report_card ON DELETE CASCADE
  subject_id      UUID
  final_score     DOUBLE
  computed_at     TIMESTAMPTZ
  UNIQUE (report_card_id, subject_id)
```

## Compute

```
[Hitung Nilai]  for a (batch, class):
  for each subject that has a formula:
      valid = (Σ weights == 100)         ── exactly 100, else SKIP subject
      if not valid: mark subject "belum diatur", continue
      for each enrolled student in the class:
          final = Σ_e ( score(student, e) × weights[e] / 100 )
                  with score == 0 when the grade is missing
          upsert report_subject_score(card, subject) = final, computed_at = now
```

Skip is **per subject** (formula ≠ 100%), never per student — a missing grade is
0, so every student computes once the subject's formula is valid. Results are
frozen; re-running compute overwrites the snapshot. `summary` on the card is
recomputed from the frozen `report_subject_score` rows (average of final scores,
pass/fail vs the year's `minimum_passing_score`).

## Generation vs compute

`POST /report-cards/generate` now takes `{ batch_id }` and creates **empty**
`Draft` cards (one per enrolled student, no scores). Compute is the separate
`[Hitung Nilai]` step. Re-generate still refreshes only `Draft` cards.

## Report board

```
┌ /grading/report-cards ───────────────────────────────────────┐
│ Rapor              [Tahun ▾] [Kelas ▾]        [+ Tambah Rapor]│
│ ┌───────────────────────────────────────────────────────────┐│
│ │ Nama Rapor              Status        Aksi                 ││  ← batch
│ │ Rapor Tengah Semester   12 draft   [Atur Bobot] [Buka]     ││    datatable
│ │ Rapor Akhir Semester    belum mulai [Atur Bobot] [Buka]    ││
│ └───────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
        │ [Atur Bobot] → modal                  │ [Buka] → existing
        ▼                                        ▼ approval board (per card,
┌ Bobot — Rapor Akhir / 7A ─────────────┐         filtered by batch)
│ Matematika  UH1[25] UTS[75]  =100% ✓  │
│ IPA         UH1[40] UAS[60]  =100% ✓  │
│ B.Indo      (belum diatur)   skip      │
│ Σ harus tepat 100% per mapel           │
│                    [Hitung Nilai Sekelas]│
└────────────────────────────────────────┘
```

The approval board ([Buka]) is the **current** 5-status board
(`grading/report-cards/page.tsx`) unchanged except that its card query is scoped
to the chosen `batch_id`.

## Formula modal validation

Per subject row, the weight inputs MUST sum to exactly 100 for the row to count
as configured (✓). A row that is empty or ≠ 100 is shown as "belum diatur" and
will be skipped. [Hitung Nilai] is enabled when at least one subject is valid;
it reports how many subjects were computed vs skipped.

## API (grading service)

```
GET    /api/v1/grading/report-batches?homeroom_id&academic_year_id
POST   /api/v1/grading/report-batches        { homeroom_id, academic_year_id, name }
DELETE /api/v1/grading/report-batches/{id}

GET    /api/v1/grading/report-batches/{id}/formulas
PUT    /api/v1/grading/report-batches/{id}/formulas/{subject_id}  { weights }
POST   /api/v1/grading/report-batches/{id}/compute     → { computed[], skipped[] }

POST   /api/v1/grading/report-cards/generate { batch_id }    (empty drafts)
GET    /api/v1/grading/report-cards?batch_id                 (board, scoped to batch)
```
