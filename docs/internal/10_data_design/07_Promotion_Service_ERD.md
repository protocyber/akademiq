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
  string certificate_number
  date letter_date
  string city
  string school_name
  string principal_name
  string principal_nip
}

PROMOTION_CLASS_LETTER {
  uuid letter_id PK
  uuid tenant_id
  uuid run_id
  uuid homeroom_id
  string letter_number
  date letter_date
  string city
  string school_name
  string principal_name
  string principal_nip
}

KNOWN_SCHOOL_PROFILE {
  uuid tenant_id PK
  string school_name
  string principal_name
  string principal_nip
  string city_regency
  string logo_url
  timestamp updated_at
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
KNOWN_SCHOOL_PROFILE ||--o{ PROMOTION_CLASS_LETTER : snapshot_source
KNOWN_SCHOOL_PROFILE ||--o{ GRADUATION_RECORD : snapshot_source
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
| Promotion Class Letter | SK Kenaikan Kelas, one per source homeroom of an executed run |
| Known School Profile | Projection of billing's school profile (`tenant.school_profile_updated`) for letterheads and principal snapshots |

## 🔗 Important Relationships
Promotion decisions are made based on rule snapshots. A decision may produce either a graduation or retention record.

Letters exist only for executed runs. A class letter and a graduate's Surat Keterangan Lulus (the letter columns on `graduation_record`) snapshot `school_name`, `principal_name`, `principal_nip` from `known_school_profile` when first issued; corrections change number, date and city only, and the explicit refresh-principal action re-snapshots every issued letter of the run. Letter numbers are unique per tenant (`promotion_class_letter_number_uidx`, partial `graduation_record_certificate_number_uidx`).