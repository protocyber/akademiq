## ADDED Requirements

### Requirement: Family profiles SHALL be reusable biodata records
The system SHALL allow admin sekolah to create, view, update, archive, soft-delete, and search reusable family profiles independently from IAM login accounts.

A family profile SHALL include name, optional NIK, optional birth place, optional birth date, address, phone number, optional photo reference, email, occupation, monthly income or income range, life status, marital status, nationality, religion, education level, status, and archive reason when archived. Family profile status SHALL support `aktif`, `nonaktif`, and `arsip`. Archive reasons SHALL support `tidak_aktif`, `meninggal`, `putus_hubungan`, `duplikat`, and `lainnya`.

#### Scenario: Family profile exists without login account
- **WHEN** admin sekolah creates a valid family profile without an IAM user id
- **THEN** the system stores the family biodata and does not create a login account

#### Scenario: Family profile can link to an IAM user optionally
- **WHEN** admin sekolah links an existing family profile to an IAM user id
- **THEN** the profile stores the optional user link without changing the IAM user's email, phone, roles, or permissions

#### Scenario: Archived family profile records reason
- **WHEN** admin sekolah archives a family profile with a supported reason
- **THEN** the profile status becomes `arsip` and the archive reason is stored

### Requirement: Student-family links SHALL support many-to-many relationships
The system SHALL allow one family profile to be linked to multiple students and one student to have multiple family profiles.

Each student-family link SHALL store relationship type, primary contact flag, emergency contact flag, lives-with-student flag, financial-responsible flag, and link status `aktif` or `nonaktif`.

#### Scenario: One parent linked to siblings
- **WHEN** admin sekolah links one family profile to two students
- **THEN** both links are stored with their own relationship attributes

#### Scenario: One student has multiple family profiles
- **WHEN** admin sekolah links ayah, ibu, and wali profiles to one student
- **THEN** all active links are listed in the student's Keluarga tab

#### Scenario: Link can be made inactive without archiving profile
- **WHEN** admin sekolah marks a student-family link inactive
- **THEN** the family profile remains available for other students and the inactive link is no longer treated as an active contact for that student

### Requirement: Family creation SHALL warn about potential duplicates
The system SHALL warn admin sekolah when creating a family profile that appears to duplicate an existing profile, but SHALL allow the admin to continue.

#### Scenario: Duplicate warning does not block creation
- **WHEN** admin sekolah creates a family profile with a NIK, phone number, or identifying details that match an existing profile
- **THEN** the system shows a duplicate warning and allows the admin to either link the existing profile or continue creating a new profile
