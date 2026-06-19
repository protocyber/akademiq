# AcademiQ ERD — Academic Operations Service

```mermaid
erDiagram
STUDENT {
  uuid student_id PK
  uuid tenant_id
  uuid user_id
  string nis
  string nisn
  string nik
  string full_name
  string gender
  date birth_date
  string birth_place
  string address_line
  string phone_number
  string photo_media_id
  string religion
  string nationality
  int child_order
  int sibling_count
  date entry_date
  string origin_school
  string status
  string archive_reason
  boolean deleted
  datetime deleted_at
  datetime created_at
  datetime updated_at
}

TEACHER {
  uuid teacher_id PK
  uuid tenant_id
  uuid user_id
  string nip
  string nik
  string full_name
  string education_level
  string gender
  date birth_date
  string birth_place
  string address_line
  string phone_number
  string photo_media_id
  string email
  string employment_status
  string role_position
  date start_date
  date end_date
  string primary_subject_area
  string nuptk
  string certification_number
  string status
  string archive_reason
  boolean deleted
  datetime deleted_at
  datetime created_at
  datetime updated_at
}

FAMILY_PROFILE {
  uuid family_id PK
  uuid tenant_id
  uuid user_id
  string full_name
  string nik
  string birth_place
  date birth_date
  string address_line
  string phone_number
  string photo_media_id
  string email
  string occupation
  string income_range
  string life_status
  string marital_status
  string nationality
  string religion
  string education_level
  string status
  string archive_reason
  boolean deleted
  datetime deleted_at
  datetime created_at
  datetime updated_at
}

STUDENT_FAMILY_LINK {
  uuid link_id PK
  uuid tenant_id
  uuid student_id FK
  uuid family_id FK
  string relationship_type
  boolean primary_contact
  boolean emergency_contact
  boolean lives_with_student
  boolean financial_responsible
  string status
  datetime created_at
  datetime updated_at
}

GUARDIAN {
  uuid tenant_id PK
  uuid user_id PK
  uuid student_id PK
  datetime created_at
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

MEDIA_ASSET {
  uuid media_id PK
  uuid tenant_id
  string owner_type
  uuid owner_id
  string file_url
  string content_type
  int size_bytes
  boolean is_active
  datetime uploaded_at
}

STUDENT ||--o{ ENROLLMENT : has
HOMEROOM ||--o{ ENROLLMENT : contains
TEACHER ||--o{ TEACHING_ASSIGNMENT : teaches
HOMEROOM ||--o{ TEACHING_ASSIGNMENT : scheduled_for
HOMEROOM ||--o{ TIMETABLE : has
TEACHER ||--o{ TIMETABLE : teaches
STUDENT ||--o{ STUDENT_FAMILY_LINK : "linked to"
FAMILY_PROFILE ||--o{ STUDENT_FAMILY_LINK : "linked to"
GUARDIAN }o--|| STUDENT : "portal access for"
```

## 🧠 What This Database Owns
This service handles daily academic structure, not grades or billing. It owns the
complete operational master data: students, teachers, family profiles, and their
media/photo history.

### Main Entities
| Entity | Purpose |
|-------|---------|
| Student | Master student data per tenant (complete Indonesian school biodata) |
| Teacher | Teacher identity inside the school (complete biodata + employment) |
| FamilyProfile | Reusable family/guardian biodata (ayah/ibu/wali), many-to-many with students |
| StudentFamilyLink | Relationship link between a student and a family profile |
| Guardian | Explicit portal/report-card access link (separate from family biodata) |
| Homeroom | A class in a specific academic year |
| Enrollment | Student ↔ Homeroom relationship per year |
| TeachingAssignment | Which teacher teaches which subject in which class |
| Timetable | Weekly schedule for classes |
| MediaAsset | Photo upload history for teacher/student/family owners |

## 🔗 Important Relationships

### Student ↔ Enrollment ↔ Homeroom
A student can be enrolled in one homeroom per academic year and have multiple historical
enrollments. Student master data does **not** store current class as authoritative state;
class placement is always represented by enrollment records.

### Family profiles ↔ students (many-to-many)
A family profile is reusable biodata that can be linked to multiple students (siblings),
and a student can have multiple family profiles (ayah, ibu, wali). Each link carries
relationship attributes (relationship type, primary/emergency/financial flags,
lives-with-student, active/inactive status).

### Family profiles vs guardian access (critical separation)
- **FamilyProfile + StudentFamilyLink** = administrative biodata for family members.
  Optionally stores a linked IAM `user_id` but does **not** grant portal access.
- **Guardian** = explicit portal/report-card authorization grant for an IAM user to a
  student. Managed independently; creating/removing a family link must never mutate
  guardian access rows.

### Media history
Logo and photo uploads use file-backed assets. Replacing a photo creates a new active
asset and keeps previous assets visible in history. Media is tenant+owner scoped.

### Profile vs IAM contact data
Student, teacher, and family profile email/phone fields are administrative contact data.
Linked IAM user email and membership data remain login/access data and are not
synchronized automatically.