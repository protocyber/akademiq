# Design — Report Card Workflow

## Context

The capstone change: it makes "create a report card" real. It sits on top of
captured grades and turns them into an approved, published rapor through a
multi-actor state machine. Built as an extension of `grading-service` because a
report card is an aggregate over that service's own grade rows.

## Key decisions

### 1. The state machine is the spec

We implement exactly the lifecycle in
`09_states/AkademiQ_State_Report_Card_Lifecycle.md`:

```
            submit (teacher)        homeroom-approve (homeroom)   principal-approve (principal)
   Draft ──────────────────▶ HomeroomReview ──────────────▶ PrincipalApproval ───────────▶ Published
     ▲                            │  ▲                              │                          │
     │  return (homeroom)         │  │  reject (principal)          │                          │ year closed
     └────────────────────────────┘  └──────────────────────────────┘                          ▼
                                                                                            Archived (read-only)
```

Each transition is a distinct endpoint with a single allowed source state, a
single target state, and a required role. The transition function is pure and
unit-tested over the full cross-product of (state × action × role) so every
illegal combination is provably rejected. Illegal transition → 409
`INVALID_STATE_TRANSITION`; wrong role → 403 `WRONG_APPROVER_ROLE`.

### 2. Role → transition matrix

| From | Action | To | Allowed role |
|------|--------|----|--------------|
| Draft | submit | HomeroomReview | subject teacher or homeroom teacher of the class |
| HomeroomReview | homeroom-approve | PrincipalApproval | homeroom teacher of the class |
| HomeroomReview | return | Draft | homeroom teacher of the class |
| PrincipalApproval | principal-approve | Published | principal |
| PrincipalApproval | reject | HomeroomReview | principal |
| Published | (event) | Archived | system (year closed) |

"of the class" means the acting user resolves (via the teaching-authz / homeroom
linkage) to the homeroom that owns the report card. A principal acts
tenant-wide. These checks reuse the projections from the grade-capture change
plus a homeroom-teacher linkage (a teaching assignment flagged as homeroom, or
an explicit homeroom_teacher assignment carried on the roster).

### 3. Draft generation aggregates grades + applies policy

`POST /report-cards/generate { homeroom_id, academic_year_id }`:

```
for each actively-enrolled student in the homeroom for the year:
    grades   = grade-capture query (student, year)
    policy   = config grading_policy (year)        # min passing score + scale
    per-subject pass/fail = score >= policy.minimum_passing_score
    upsert report_card(student, year) in Draft with summary (avg, pass count)
```

Pass/fail is **derived at generation**, not stored on the grade — so if the
policy changes before generation, regeneration reflects it. Generation is
idempotent per `(student, year)`: re-running while a card is still `Draft`
refreshes it; re-running after it left `Draft` skips that student (its grades
are locked) and reports them as already in-workflow.

### 4. Edit-lock closes the loop with grade capture

The previous change left `can_edit_grade(student, year)` returning `true`. This
change makes it real: grades are editable only while the student's report card
for that year is absent or in `Draft`. Once a card is in HomeroomReview or
beyond, grade edits return 409 `GRADES_LOCKED`. The `return` transition (back
to Draft) re-opens editing — which is the whole point of "needs correction".

```
report_card.status ∈ {none, Draft}  ⟶ grades editable
report_card.status ∈ {HomeroomReview, PrincipalApproval, Published, Archived} ⟶ grades locked
```

### 5. Audit trail and the approval table

Every transition appends a `report_approval` row
(`approver_id`, `role`, `action`, `note`, `approved_at`). This gives the detail
view a full history and satisfies the "audit logging" driver called out in the
state diagram doc. `report_approval` is append-only.

### 6. Visibility model

- Staff in the workflow (teacher/homeroom/principal/admin) see report cards in
  any state for their scope.
- Student + parent see a report card **only when `Published`** (or `Archived`),
  via `GET /students/{id}/report-card`. Pre-publish access returns 404 to
  student/parent (not 403 — we don't reveal existence of an in-progress card).

### 7. Year close → archive

A consumer on the academic-year lifecycle (the year reaching `Closed`/`Archived`
per config) transitions that year's `Published` cards to `Archived`
(read-only). This is the only system-driven transition; it reuses the
`academic_year` status signal (consumed as an event or polled projection).

## Data model (refinery `V2__report_card.sql`)

| Table | Key columns | Notes |
|-------|-------------|-------|
| `report_card` | `report_card_id` PK, `tenant_id`, `student_id`, `academic_year_id`, `homeroom_id`, `status`, `summary` (jsonb: per-subject score+pass, averages), `published_at`, `created_at`, `updated_at` | unique `(tenant_id, student_id, academic_year_id)` |
| `report_approval` | `approval_id` PK, `report_card_id` FK, `approver_id`, `role`, `action`, `note`, `approved_at` | append-only audit |

Indexes: `report_card(homeroom_id, academic_year_id, status)` for the staff
board, `report_card(student_id, academic_year_id)` for the published view,
`report_approval(report_card_id)`.

## Alternatives considered

- **Store pass/fail on each grade** — rejected: couples capture to policy and
  breaks re-derivation when policy changes; derive at generation instead.
- **Single "approve" endpoint with a target-state param** — rejected: explicit
  per-transition endpoints make role gating and auditing clearer and keep the
  state machine legible.
- **Generate report cards lazily on first view** — rejected: the demo and the
  approval workflow need cards to exist as first-class rows teachers act on.
- **Render PDF in this change** — rejected: needs the file/storage service;
  in-app view satisfies the rapor target now, PDF lands with file service.

## Risks

- **Class-scope resolution** (is this user the homeroom teacher of this card's
  class?) depends on the account↔profile link from tenant-user-management. If
  unlinked, the transition is blocked with a clear error rather than a silent
  403. Documented as a setup prerequisite.
- **Partial grades at generation**: a student missing some subject grades still
  generates a Draft, flagged incomplete in the summary, so the homeroom teacher
  can return it for correction. We do not block generation on completeness —
  the review step is where completeness is enforced by a human.
- **Year-close race**: archiving published cards must not clobber an
  in-progress card; the consumer only touches `Published` rows.
