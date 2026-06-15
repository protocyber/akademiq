# Proposal — grade-entry-evaluations

## Why

The grade-entry screen (`/grading/entry`) and the grading service model **one
score per (student, subject, year)**. Teachers cannot record the individual
assessments that actually make up a subject grade — UH1, UH2, UTS, UAS. The
`grade` table enforces `UNIQUE (tenant, student, subject, year)`
(`grading-service/migrations/V1__init.sql:15`), and the entry UI is a single
`Nilai` column with a per-row **Update** button
(`apps/web/.../grading/entry/page.tsx:93`).

This blocks weighted report cards (the follow-up change
`report-card-batches`, which depends on this one): without named assessments
there is nothing to weight.

The screen also predates the users/roles datatable standard — no per-cell
inline save, no managed assessment columns.

## What Changes

**New concept — Evaluation (assessment), scoped per (homeroom × subject ×
year):** a named column (`code` "UH1", `name` "Ulangan Harian 1", `position`).
Each class+subject defines its own list; two classes teaching the same subject
may differ.

**Grade model change (BREAKING, no migration — early/dev, data reset OK):**
a grade moves from `(student, subject, year) → score` to
`(student, evaluation_id) → score`. New uniqueness:
`UNIQUE (tenant, student, evaluation_id)`.

**Entry screen rebuild:**
- Tahun / Kelas / Mapel selectors (as today).
- A **[Kelola Evaluasi]** button — appears only once kelas **and** mapel are
  chosen — opens a modal managing the evaluation list (add/edit/delete, reorder)
  for that class+subject.
- The grid becomes **one column per evaluation**. Each cell auto-saves on blur
  (no Update button) and shows a per-cell status (idle / saving / saved / error).

## Non-goals

- Report cards, batches, weighting formulas, and compute — all in the dependent
  change `report-card-batches`.
- The report-card approval workflow is untouched here.

## Capabilities

### Modified Capabilities
- `grading-service-grade-capture`: grades are keyed by evaluation; new
  evaluation CRUD under `/api/v1/grading`.

### New Capabilities
- `web-grading-entry`: the grade-entry screen as an evaluation-column grid with
  per-cell inline auto-save and an evaluation-management modal.
