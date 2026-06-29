# AkademiQ ERD — Promotion Service

```mermaid
erDiagram
PROMOTION_DECISION {
  uuid decision_id PK
  uuid student_id
  uuid academic_year_id
  string result
  string notes
}

GRADUATION_RECORD {
  uuid graduation_id PK
  uuid student_id
  uuid academic_year_id
  date graduation_date
}

RETENTION_RECORD {
  uuid retention_id PK
  uuid student_id
  uuid academic_year_id
  string reason
}

PROMOTION_RULE_SNAPSHOT {
  uuid rule_id PK
  uuid academic_year_id
  string description
  float minimum_score_required
}

PROMOTION_RULE_SNAPSHOT ||--o{ PROMOTION_DECISION : used_for
PROMOTION_DECISION ||--o| GRADUATION_RECORD : may_create
PROMOTION_DECISION ||--o| RETENTION_RECORD : may_create
```

## 🧠 What This Database Owns
This service manages end-of-year academic progression decisions.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Promotion Decision | Student advancement result |
| Graduation Record | Graduation tracking |
| Retention Record | Students repeating a grade |
| Promotion Rule Snapshot | Rules used during promotion evaluation |

## 🔗 Important Relationships
Promotion decisions are made based on rule snapshots. A decision may produce either a graduation or retention record.