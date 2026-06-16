# Design — report-types-year-scoped

## Context

`report-card-batches` shipped a per-class `report_batch (homeroom × year)`, a
per-batch `report_formula (batch × subject)`, and an explicit `[Hitung Nilai]`
compute that froze `report_subject_score`. The report board
(`/grading/report-cards`) picked Tahun + Kelas, listed batches, and hosted both
the weighting modal and the approval board.

Two product realities break that model:

1. A report *type* (Rapor Tengah Semester, Rapor Akhir) is a **year-level**,
   school-wide concept; recreating it per class is wrong.
2. As a SaaS, schools fold the **same** evaluation into **different** report
   types with **different** weights — so weighting is `(report type × evaluation)`
   many-to-many, not a single per-batch formula. Teachers also want the report
   mark to update live as grades are entered.

This change is **dev/early** — migrations are rewritten and the DB reset; there
is no data migration.

## Goals / Non-Goals

**Goals:**
- Year-scoped `report_type` with `code` + `name`, managed in the Edit Tahun
  Ajaran form.
- `(report type × evaluation)` weighting summing to exactly 100% per
  `(report type × subject)`.
- Live `subject_report_score` recomputed on every grade save; frozen into the
  card at `[Generate Draft]` together with a weights snapshot.
- Rebuilt, routed report board: year + report-type list → per-class tabbed
  datatable board → detail modal. Keep the print route.
- Move weighting into Kelola Evaluasi; remove it from the report board; remove
  the explicit compute action.

**Non-Goals:**
- Changing the 5-status approval state machine or its role gates.
- Per-student weighting overrides (weights are per class via the subject's
  evaluations).
- Evaluation CRUD semantics (code/name/position/reorder) beyond surfacing the
  weight matrix; evaluations keep no inline weight field.

## Decisions

### 1. `report_type` replaces `report_batch`, owned at the academic year

```
report_type (NEW — replaces report_batch)
  report_type_id    UUID PK
  tenant_id         UUID
  academic_year_id  UUID
  code              VARCHAR   "Rapor UTS"            (column title in entry grid)
  name              VARCHAR   "Rapor Tengah Semester"
  position          INT       (display order)
  created_at / updated_at
  UNIQUE (academic_year_id, code)
```

Created/edited from the **Edit Tahun Ajaran** modal as a new section
(`§ Jenis Rapor`), beside `§ Kebijakan Nilai` and `§ Versi Kurikulum`.

**Ownership decision — keep report types in grading-service.** Although edited
from the academic-config screen, report types belong to the report-card domain
(they own formulas, scores, cards). The web form calls the grading API directly
(the year edit modal already composes multiple services). Alternative — moving
them into academic-config — was rejected: it would split report ownership across
two services and force cross-service reads at compute. The academic-year form
gates the section on a valid `academic_year_id` exactly like the policy/curriculum
sections do.

### 2. Weighting is `(report type × evaluation)`, summing to 100% per subject

```
report_formula (RE-KEYED: batch_id → report_type_id)
  report_type_id  UUID  → report_type
  evaluation_id   UUID  → evaluation
  weight          INT/NUMERIC  (percent)
  updated_at
  UNIQUE (report_type_id, evaluation_id)
```

Because `evaluation` is already scoped to `(homeroom, subject, year)`, a formula
row inherits its subject. Validity rule: for a given `(report_type, homeroom,
subject)`, the sum of weights over that subject's included evaluations MUST equal
exactly 100. A grade entry for an evaluation whose subject/report-type pair is not
yet 100% leaves that report-type score **uncomputed** (shown blank), matching the
old skip rule. Missing evaluation score counts as **0** when a formula is valid.

The weight is set via a **matrix** in the Kelola Evaluasi modal (Opsi B): rows =
this subject's evaluations, columns = the year's report types, cell = weight %.
Each report-type column must total 100% to save. The evaluation grid header shows
**no** weight number (a single header can't represent per-report-type weights).

### 3. Live scores + snapshot (no explicit compute)

```
subject_report_score (NEW — live "Nilai Rapor")
  tenant_id, academic_year_id, homeroom_id, subject_id, student_id
  report_type_id  UUID  → report_type
  score           DOUBLE
  updated_at
  UNIQUE (report_type_id, subject_id, student_id)
```

On `POST/PUT grade` (upsert), recompute affected `subject_report_score` rows:
for **every report type** whose formula (for that subject) includes the saved
evaluation and is valid (Σ = 100), recompute that student's score
`Σ_e score(e) × weight/100` (missing = 0) and upsert. One grade save can touch
several report-type scores (M:N). Invalid/incomplete formula → no row (blank).

```
report_card (CHANGED)
  report_card_id   UUID PK
  tenant_id, student_id, homeroom_id, academic_year_id
  report_type_id   UUID  → report_type        (was batch_id)
  status           VARCHAR  (5-status, unchanged)
  summary          JSONB
  weights_snapshot JSONB   { subject_id: { evaluation_id: weight } }   (NEW)
  published_at, created_at, updated_at
  UNIQUE (report_type_id, student_id)

report_subject_score (KEPT — frozen at generate, no longer at compute)
  report_card_id FK CASCADE, subject_id, final_score, computed_at
  UNIQUE (report_card_id, subject_id)
```

`[Generate Draft]` for `(report_type, homeroom)`:
```
for each actively-enrolled student in the homeroom:
    upsert empty Draft report_card (report_type, student) if absent  (idempotent)
    if still Draft:
        copy live subject_report_score(report_type, subject, student)
             → report_subject_score(card, subject), computed_at = now
        snapshot current valid weights → report_card.weights_snapshot
        recompute summary from frozen scores vs year minimum_passing_score
cards past Draft are left untouched and reported as skipped
```
Editing grades after generate updates only the **live** scores; the card stays
frozen until re-generated. The standalone compute endpoint is removed.

### 4. Routing + UI

```
/grading/report-cards
    [Tahun ▾]   list report_type rows (code · name · count)   [Buka Rapor]→
/grading/report-cards/<report_type_id>/classroom
    pick class → row [Buka]→
/grading/report-cards/<report_type_id>/classroom/<classroom_id>
    [Generate Draft]
    Tabs: Draft(n) · Review Wali(n) · Persetujuan Kepsek(n) · Terbit(n) · Arsip(n)
    each tab → DataTable(students): [✓ multiselect] | Nama | Rata-rata | [Detail⛶]
    [Detail] → large modal = former /report-cards/[id] content
              (modal keeps a link/button to /report-cards/[id]/print)
```

- The `/grading/report-cards/[id]` page is deleted; its component body is lifted
  into a reusable detail panel rendered inside the modal **and** still mounted by
  the kept `[id]/print` route.
- Multiselect enables future bulk transitions; this change wires selection + a
  bulk action bar consistent with the academic-years datatable pattern.

Grade entry grid (`/grading/entry`), per `(year, class, subject)`:
```
Siswa │ UH1 │ UH2 │ UTS │ UAS │ Rapor UTS │ Rapor UAS
      │edit │edit │edit │edit │ read-only │ read-only   ← subject_report_score
```
N read-only columns = the year's report types, titled by `code`, auto-updating.

### 5. API (grading service)

```
GET    /report-types?academic_year_id
POST   /report-types                 { academic_year_id, code, name }
PATCH  /report-types/{id}            { code?, name?, position? }
DELETE /report-types/{id}

GET    /report-types/{id}/formulas?homeroom_id&subject_id
PUT    /report-types/{id}/formulas/{evaluation_id}   { weight }   (or batch upsert per subject)
       → 400 INVALID_WEIGHTS when a (report_type × subject) total ≠ 100

GET    /subject-report-scores?report_type_id&homeroom_id&subject_id   (grid columns)

POST   /report-cards/generate { report_type_id, homeroom_id }   (empty drafts + snapshot)
GET    /report-cards?report_type_id&homeroom_id                 (board, scoped)
# transition endpoints + role gates: UNCHANGED
# REMOVED: POST /report-batches/{id}/compute and all /report-batches routes
```

## Risks / Trade-offs

- **Live recompute fan-out on grade save** → a single save may update many
  `subject_report_score` rows (one per report type including that evaluation).
  Mitigation: scope recompute to the saved evaluation's report types and the one
  student; it is a small bounded set per save.
- **M:N weighting is harder to reason about than a single formula** → Mitigation:
  the matrix shows per-report-type column totals with an explicit 100% check;
  blank score signals an incomplete formula, same mental model as before.
- **Dropping the weight from the evaluation header** loses an at-a-glance cue the
  earlier idea wanted → accepted trade-off of Opsi B (per-report-type weights
  can't collapse to one header number); the matrix is the single source.
- **Deleting `/report-cards/[id]` while keeping `[id]/print`** → Mitigation: lift
  the detail body into a shared component used by both the modal and the print
  route so there is no divergence.
- **Cross-service edit surface** (year form calling grading API) → Mitigation:
  the year modal already composes academic-config + grading-policy; the new
  section follows the same gated-on-`academic_year_id` pattern.

## Migration Plan

Dev/early: rewrite the `report-card-batches` migrations in place (rename
`report_batch`→`report_type`, drop `homeroom_id`, re-key `report_formula`, add
`subject_report_score`, swap `report_card.batch_id`→`report_type_id` + add
`weights_snapshot`) and reset the dev DB (`make migrate` on a fresh
`grading_db`). No production data exists; no rollback path needed beyond
re-running migrations.

## Open Questions

- Formula write shape: per-evaluation `PUT .../formulas/{evaluation_id}` vs a
  single per-subject batch upsert `{ weights: { evaluation_id: weight } }`. Batch
  upsert validates the 100% rule atomically and matches the matrix UI — leaning
  that way; confirm in tasks.
- Whether the report-type list on `/grading/report-cards` shows all years or only
  the picked year's types when no year is selected (default: require a year, like
  the entry screen).
