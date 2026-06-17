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

ACADEMIC_TERM {
  uuid term_id PK
  uuid academic_year_id FK
  uuid tenant_id
  string name
  date start_date
  date end_date
  string status
}

ACADEMIC_TERM_STATUS_TRANSITION {
  uuid id PK
  uuid term_id FK
  uuid tenant_id
  string from_status
  string to_status
  string reason
  uuid actor_user_id
  datetime occurred_at
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

ACADEMIC_YEAR ||--o{ ACADEMIC_TERM : "has terms"
ACADEMIC_TERM ||--o{ ACADEMIC_TERM_STATUS_TRANSITION : "records transitions"
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
| Academic Term | A child period within a year (e.g. Semester 1, Semester 2) |
| Academic Term Status Transition | Audit log for term lifecycle changes |
| Curriculum Version | Snapshot of curriculum used that year |
| Subject | Subjects taught under that curriculum |
| Grading Policy | Rules for scoring and passing |
| Class Template | Default class structure for yearly setup |

## 🔗 Important Relationships
Academic years define curriculum versions and grading policies. Each academic year has at least one term (auto-seeded on creation). Subjects belong to a curriculum version. Class templates help initialize homerooms for the year.

## Invariants
- Every `academic_year` always has ≥ 1 `academic_term` (default `"Semester 1"` is seeded on creation).
- At most one term per year may be `Active` (enforced by partial unique index `academic_term_one_active_per_year_idx`).
- Term `start_date`/`end_date` must fall within the parent year's range (app-layer).
- Terms within a year must not overlap (app-layer).
- A year cannot transition to `Closed` while any of its terms is `Active` (`TERM_STILL_ACTIVE`).
