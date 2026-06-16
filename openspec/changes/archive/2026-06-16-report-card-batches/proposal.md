# Proposal — report-card-batches

> **Depends on `grade-entry-evaluations`.** This change weights the per-evaluation
> grades that change introduces. It cannot be implemented until evaluations exist.

## Why

Report cards today are **one card per (student, year)**
(`grading-service/migrations/V2__report_card.sql:15`), and `generate` derives the
summary as a flat **average of every subject's single grade**
(`derive_report_summary`, `domain.rs:197`). A school actually issues **multiple
report cards per year** — rapor sisipan (tengah semester), rapor akhir — and a
subject's mark is a **weighted combination of its evaluations** (UH1 25% +
UTS 75%), with weights chosen per subject by the teacher.

Neither exists: there is no batch concept, no weighting, and the report board
(`grading/report-cards/page.tsx`) is hard-wired to a single set of cards per
class+year.

## What Changes

**New concept — Report batch:** an admin creates multiple named report runs per
`(homeroom, year)` — "Rapor Tengah Semester", "Rapor Akhir". `report_card`
uniqueness moves from `(student, year)` to `(batch, student)`.

**New concept — Weighting formula, per (batch × subject):** a teacher sets the
percentage each evaluation contributes for a subject within a batch. The weights
**MUST total exactly 100%** or the subject is treated as not-yet-configured and
**skipped** at compute. One formula per class, applied to all students.

**Compute = snapshot:** a **[Hitung Nilai]** action computes, for every
configured subject, each student's final subject score as
`Σ score(evaluation) × weight/100` where a **missing evaluation score counts as
0**. Results are **frozen** into a new `report_subject_score` table; editing
grades afterward does not change a computed card until compute is re-run.

**Flow:** admin creates batch → empty `Draft` cards per enrolled student →
teacher sets per-subject formula → [Hitung Nilai] fills frozen scores →
existing 5-status approval workflow runs **per card**, filtered by batch.

**Report board rebuild:** `/grading/report-cards` becomes a batch datatable
([+ Tambah Rapor]) with per-batch [Atur Bobot] (formula modal + compute) and
[Buka] (the existing approval board, scoped to that batch).

## Non-goals

- Evaluations and per-evaluation grades — delivered by `grade-entry-evaluations`.
- Changing the approval state machine or its role gates.
- Per-student formula overrides (formula is per class).

## Capabilities

### Modified Capabilities
- `report-card-workflow`: cards belong to a batch; generation creates empty
  drafts; per-subject weighted compute replaces average-based summary.

### New Capabilities
- `web-report-cards`: batch datatable, per-subject weighting modal with the
  exactly-100% rule, and the compute action, fronting the existing approval board.
