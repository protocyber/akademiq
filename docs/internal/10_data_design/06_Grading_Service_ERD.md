# AcademiQ ERD — Grading & Report Service

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
}

REPORT_FORMULA {
  uuid report_type_id FK
  uuid subject_id
  uuid evaluation_id FK
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
EVALUATION ||--o{ GRADE : "records"
EVALUATION ||--o{ REPORT_FORMULA : "weighted in"
REPORT_TYPE ||--o{ REPORT_FORMULA : "defines weights"
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
| Grade | Individual student score for an evaluation |
| Report Type | A report card type scoped to `(year, term)` |
| Report Formula | Weight mapping of evaluations to a report type per subject |
| Subject Report Score | Live computed score per `(report_type, subject, student)` |
| Report Card | Aggregated result per `(student, report_type)` |
| Report Subject Score | Frozen per-subject score on a report card |
| Report Approval | Multi-step approval history |

## 🔗 Important Relationships
Evaluations and report types are both scoped to a `(year, term)` pair. Report formulas link evaluations to report types; adding a formula is rejected if the evaluation's `term_id` differs from the report type's `term_id` (`EVALUATION_TERM_MISMATCH`). Grade entry is gated on both the year (`YEAR_NOT_ACTIVE`) and the term (`TERM_NOT_ACTIVE`) being `Active`.

## Projection Pattern
`valid_year` and `valid_term` are write-only projections consumed from outbox events (`academic_year.status_changed`, `academic_term.created`, `academic_term.status_changed`). There are no physical foreign keys to academic-config-service tables.

## Unique Constraints
- Evaluation: `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` — allows same code across terms.
- Report type: `(academic_year_id, term_id, code)` — allows same code across terms.
