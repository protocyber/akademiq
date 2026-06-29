# AkademiQ ERD — Attendance Service

```mermaid
erDiagram
ATTENDANCE_SESSION {
  uuid session_id PK
  uuid homeroom_id
  uuid subject_id
  uuid teacher_id
  datetime session_date
}

ATTENDANCE_RECORD {
  uuid record_id PK
  uuid session_id FK
  uuid student_id FK
  string status
  datetime recorded_at
}

ATTENDANCE_SESSION ||--o{ ATTENDANCE_RECORD : contains
```

## 🧠 What This Database Owns
This service records class attendance per session.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Attendance Session | One teaching session instance |
| Attendance Record | Presence status per student |

## 🔗 Important Relationships
Each session contains many attendance records, one per student.