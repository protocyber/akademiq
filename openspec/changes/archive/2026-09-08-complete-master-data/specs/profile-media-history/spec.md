## ADDED Requirements

### Requirement: Profile media SHALL support validated uploads
The system SHALL allow authorized admin sekolah to upload school logos and teacher, student, and family photos using JPG, PNG, or WebP files no larger than 2MB.

#### Scenario: Valid image upload succeeds
- **WHEN** admin sekolah uploads a JPG, PNG, or WebP image no larger than 2MB for a supported owner
- **THEN** the system stores the media asset, associates it with the owner, and marks it as the active logo or photo

#### Scenario: Invalid image upload is rejected
- **WHEN** admin sekolah uploads an unsupported file type or an image larger than 2MB
- **THEN** the system rejects the upload with a validation error and does not replace the active media

### Requirement: Profile media SHALL preserve visible history
The system SHALL preserve previous logos and photos when a new file is uploaded and SHALL allow admin sekolah to view media history for each owner.

#### Scenario: Replacing photo preserves history
- **WHEN** admin sekolah replaces a student's active photo
- **THEN** the new photo becomes active and the previous photo remains visible in the student's media history

#### Scenario: Media history is owner scoped
- **WHEN** admin sekolah views media history for a teacher, student, family profile, or school profile
- **THEN** the system returns only media assets associated with that owner in the current tenant
