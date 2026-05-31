# AcademiQ ERD — Grading & Report Service

```mermaid
erDiagram
GRADE {
  uuid grade_id PK
  uuid student_id FK
  uuid subject_id
  uuid academic_year_id
  float score
}

REPORT_CARD {
  uuid report_card_id PK
  uuid student_id FK
  uuid academic_year_id
  string status
  date published_at
}

REPORT_APPROVAL {
  uuid approval_id PK
  uuid report_card_id FK
  uuid approver_id
  string role
  datetime approved_at
}

GRADE ||--o{ REPORT_CARD : aggregated_into
REPORT_CARD ||--o{ REPORT_APPROVAL : reviewed_by
```

## 🧠 What This Database Owns
This service manages grading records and report card workflows.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Grade | Individual subject score per student |
| Report Card | Aggregated yearly academic result |
| Report Approval | Approval tracking workflow |

## 🔗 Important Relationships

Grades are aggregated into report cards per academic year.  
Report cards go through multi-step approval before publication.