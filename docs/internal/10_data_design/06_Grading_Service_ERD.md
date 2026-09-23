# AkademiQ ERD — Grading & Report Service

```mermaid
erDiagram
VALID_YEAR {
  uuid academic_year_id PK
  uuid tenant_id
  string status
  datetime updated_at
}

VALID_TERM {
  uuid term_id PK
  uuid tenant_id
  uuid academic_year_id
  string status
  datetime updated_at
}

EVALUATION {
  uuid evaluation_id PK
  uuid tenant_id
  uuid homeroom_id
  uuid subject_id
  uuid academic_year_id FK
  uuid term_id FK
  string code
  string name
  int position
}

GRADE {
  uuid grade_id PK
  uuid tenant_id
  uuid student_id FK
  uuid evaluation_id FK
  float score
  uuid recorded_by
}

REPORT_TYPE {
  uuid report_type_id PK
  uuid tenant_id
  uuid academic_year_id FK
  uuid term_id FK
  string code
  string name
  int position
  boolean is_promotion_source
}

REPORT_FORMULA {
  uuid report_type_id FK
  uuid subject_id
  uuid evaluation_id FK
  float weight
}

EVALUATION_TEMPLATE {
  uuid template_id PK
  uuid tenant_id
  uuid term_id FK
  string code
  string name
  int position
}

REPORT_FORMULA_TEMPLATE {
  uuid report_type_id FK
  uuid evaluation_template_id FK
  float weight
}

SUBJECT_REPORT_SCORE {
  uuid report_type_id FK
  uuid subject_id
  uuid student_id FK
  float score
}

REPORT_CARD {
  uuid report_card_id PK
  uuid tenant_id
  uuid student_id FK
  uuid academic_year_id
  uuid homeroom_id
  uuid report_type_id FK
  string status
  date published_at
}

REPORT_SUBJECT_SCORE {
  uuid report_card_id FK
  uuid subject_id
  float final_score
}

REPORT_APPROVAL {
  uuid approval_id PK
  uuid report_card_id FK
  uuid approver_id
  string role
  string action
  datetime approved_at
}

VALID_YEAR ||--o{ EVALUATION : "gates grade entry (year)"
VALID_TERM ||--o{ EVALUATION : "gates grade entry (term)"
VALID_TERM ||--o{ EVALUATION_TEMPLATE : "seeds"
EVALUATION ||--o{ GRADE : "records"
EVALUATION ||--o{ REPORT_FORMULA : "weighted in"
EVALUATION_TEMPLATE ||--o{ REPORT_FORMULA_TEMPLATE : "weighted in"
REPORT_TYPE ||--o{ REPORT_FORMULA : "defines weights"
REPORT_TYPE ||--o{ REPORT_FORMULA_TEMPLATE : "defines template weights"
REPORT_TYPE ||--o{ SUBJECT_REPORT_SCORE : "live scores"
REPORT_TYPE ||--o{ REPORT_CARD : "generates"
REPORT_CARD ||--o{ REPORT_SUBJECT_SCORE : "freezes"
REPORT_CARD ||--o{ REPORT_APPROVAL : "reviewed by"
```

## 🧠 What This Database Owns
This service manages evaluations, grading records, report types, and report card workflows. It also holds local projection tables (`valid_year`, `valid_term`) to gate operations without cross-service calls.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Valid Year | Projection of academic year status from academic-config-service |
| Valid Term | Projection of academic term status from academic-config-service |
| Evaluation | A scored activity (quiz, exam) scoped to `(homeroom, subject, year, term)` |
| Evaluation Template | Per-term master evaluation list used to seed concrete evaluations |
| Grade | Individual student score for an evaluation |
| Report Type | A report card type scoped to `(year, term)`; at most one per `(tenant, academic_year)` may carry `is_promotion_source` |
| Report Formula | Weight mapping of evaluations to a report type per subject |
| Report Formula Template | Weight mapping of template evaluations to a report type |
| Subject Report Score | Live computed score per `(report_type, subject, student)` |
| Report Card | Aggregated result per `(student, report_type)` |
| Report Subject Score | Frozen per-subject score on a report card |
| Report Approval | Multi-step approval history |

## 🔗 Important Relationships
Evaluations and report types are both scoped to a `(year, term)` pair. Report formulas link evaluations to report types; adding a formula is rejected if the evaluation's `term_id` differs from the report type's `term_id` (`EVALUATION_TERM_MISMATCH`). Grade entry is gated on both the year (`YEAR_NOT_ACTIVE`) and the term (`TERM_NOT_ACTIVE`) being `Active`.

Evaluation templates are term-scoped seeds. On `teacher.assigned`, grading materializes concrete evaluations for Draft/Active terms in the assignment's year using `ON CONFLICT DO NOTHING`; repeated event deliveries are safe. The apply endpoint performs the same materialization for assignments in a term that still have zero evaluations. Weight templates materialize into `report_formula` only when matching report types exist. Closed and Archived terms are skipped by event materialization.

## Projection Pattern
`valid_year` and `valid_term` are write-only projections consumed from outbox events (`academic_year.status_changed`, `academic_term.created`, `academic_term.status_changed`). There are no physical foreign keys to academic-config-service tables.

## Unique Constraints
- Evaluation: `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` — allows same code across terms.
- Evaluation template: `(tenant_id, term_id, code)` — one template column code per term.
- Report type: `(academic_year_id, term_id, code)` — allows same code across terms.
- Report formula template: `(report_type_id, evaluation_template_id)` — one template weight per report type/template evaluation.

## Promotion Source Flag (`report_type.is_promotion_source`)
Added in migration V12 as `BOOLEAN NOT NULL DEFAULT FALSE`. Marks which
report type decides grade promotion for its academic year. Note the scope
mismatch worth remembering: `report_type` itself is **term-scoped**
(`UNIQUE (academic_year_id, term_id, code)`), but this flag is
**year-scoped** — a year has several terms, each with its own report types,
and at most one report type across the *whole year* may carry the flag.
There is a partial index on `(tenant_id, academic_year_id) WHERE
is_promotion_source` for lookups, but it is deliberately **not** a unique
index; uniqueness is enforced in the command layer
(`REPORT_TYPE_PROMOTION_SOURCE_TAKEN` on conflict), mirroring
`grade_level.is_final` in academic-config-service. Copying report types
between terms does not propagate this flag.

## Report Card Published Event
On the `Published` transition, `grading-service` emits `report_card.published`
(see `docs/internal/11_integration_contracts/events/report-card-published.md`)
in the same transaction as the status write and the approval-audit row. The
`scores` payload is read from `report_subject_score` (frozen at generation
time), and the event carries a publish-time snapshot of
`is_promotion_source` for the card's report type. Academic Operations
Service consumes this event to populate its `known_report_score` and
`known_grading_policy` projections — see
`docs/internal/10_data_design/04_Academic_Operations_ERD.md`.
