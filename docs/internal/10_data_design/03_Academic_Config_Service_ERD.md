# AcademiQ ERD — Academic Configuration Service

```mermaid
erDiagram
ACADEMIC_YEAR {
  uuid academic_year_id PK
  uuid tenant_id
  string name
  date start_date
  date end_date
  string status
}

CURRICULUM_VERSION {
  uuid curriculum_version_id PK
  uuid academic_year_id FK
  string name
  string description
}

SUBJECT {
  uuid subject_id PK
  uuid curriculum_version_id FK
  string name
  int passing_grade
}

GRADING_POLICY {
  uuid policy_id PK
  uuid academic_year_id FK
  float minimum_passing_score
  string grading_scale
}

CLASS_TEMPLATE {
  uuid template_id PK
  uuid academic_year_id FK
  string grade_level
  int default_capacity
}

ACADEMIC_YEAR ||--o{ CURRICULUM_VERSION : defines
CURRICULUM_VERSION ||--o{ SUBJECT : includes
ACADEMIC_YEAR ||--o{ GRADING_POLICY : applies
ACADEMIC_YEAR ||--o{ CLASS_TEMPLATE : provides
```

## 🧠 What This Database Owns
This service stores year-based academic structure and rules. It defines how the school operates in a given academic year.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Academic Year | Defines a school year period |
| Curriculum Version | Snapshot of curriculum used that year |
| Subject | Subjects taught under that curriculum |
| Grading Policy | Rules for scoring and passing |
| Class Template | Default class structure for yearly setup |

## 🔗 Important Relationships
Academic years define curriculum versions and grading policies. Subjects belong to a curriculum version. Class templates help initialize homerooms for the year.