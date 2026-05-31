# AcademiQ ERD — Academic Operations Service

```mermaid
erDiagram
STUDENT {
  uuid student_id PK
  string nis
  string full_name
  date birth_date
  string gender
  uuid tenant_id
}

TEACHER {
  uuid teacher_id PK
  string nip
  string full_name
  uuid tenant_id
}

HOMEROOM {
  uuid homeroom_id PK
  string name
  int grade_level
  int capacity
  uuid academic_year_id
  uuid tenant_id
}

ENROLLMENT {
  uuid enrollment_id PK
  uuid student_id FK
  uuid homeroom_id FK
  uuid academic_year_id
  string status
}

TEACHING_ASSIGNMENT {
  uuid assignment_id PK
  uuid teacher_id FK
  uuid subject_id
  uuid homeroom_id FK
  uuid academic_year_id
}

TIMETABLE {
  uuid timetable_id PK
  uuid homeroom_id FK
  uuid subject_id
  uuid teacher_id FK
  string day_of_week
  string start_time
  string end_time
}

STUDENT ||--o{ ENROLLMENT : has
HOMEROOM ||--o{ ENROLLMENT : contains
TEACHER ||--o{ TEACHING_ASSIGNMENT : teaches
HOMEROOM ||--o{ TEACHING_ASSIGNMENT : scheduled_for
HOMEROOM ||--o{ TIMETABLE : has
TEACHER ||--o{ TIMETABLE : teaches
```

## 🧠 What This Database Owns
This service handles daily academic structure, not grades or billing.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Student | Master student data per tenant |
| Teacher | Teacher identity inside the school |
| Homeroom | A class in a specific academic year |
| Enrollment | Student ↔ Homeroom relationship per year |
| TeachingAssignment | Which teacher teaches which subject in which class |
| Timetable | Weekly schedule for classes |

## 🔗 Important Relationships

### Student ↔ Enrollment ↔ Homeroom
A student can be enrolled in one homeroom per academic year and have multiple historical enrollments.

### Teacher ↔ Teaching Assignment
Teachers are assigned per subject per class, supporting multiple teachers per class.

### Timetable
Links homeroom, teacher, subject, and time slot for scheduling and attendance.