## ADDED Requirements

### Requirement: Guardian access SHALL remain separate from family biodata
The system SHALL treat existing guardian links as explicit portal/report-card access grants and SHALL NOT automatically create, update, or remove guardian access links when family profiles or student-family links are created or changed.

#### Scenario: Family profile link does not grant portal access
- **WHEN** admin sekolah links a family profile with a linked IAM user to a student
- **THEN** the system does not create a `guardian` access link unless admin sekolah explicitly performs the guardian-link action

#### Scenario: Guardian access does not require family profile
- **WHEN** admin sekolah links an IAM user as guardian access for a student
- **THEN** the access link is stored even if no family profile exists for that IAM user

#### Scenario: Removing family link does not remove guardian access automatically
- **WHEN** admin sekolah marks a student-family link inactive or removes it
- **THEN** any existing guardian portal access link remains unchanged until explicitly removed
