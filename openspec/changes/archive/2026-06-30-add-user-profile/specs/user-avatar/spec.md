## ADDED Requirements

### Requirement: User can upload avatar photo
The system SHALL allow authenticated users to upload a profile avatar photo via the profile page. The upload SHALL use the existing `media://` URI storage pattern.

#### Scenario: User uploads a valid avatar image
- **WHEN** the user selects or drag-drops a valid image file (JPEG, PNG, or WebP, max 2MB) via the avatar upload component
- **THEN** the system SHALL validate the file type and size, generate a UUID-based media identifier, store the file using the `media://` URI scheme, update the user's `avatar_url` field, and return the new avatar URL

#### Scenario: User uploads oversized file
- **WHEN** the user attempts to upload an image file larger than 2MB
- **THEN** the system SHALL reject the upload with an error message "Ukuran file maksimal 2MB"

#### Scenario: User uploads invalid file type
- **WHEN** the user attempts to upload a non-image file (e.g., PDF, text)
- **THEN** the system SHALL reject the upload with an error message "Format file harus JPG, PNG, atau WebP"

### Requirement: Avatar upload uses existing media storage pattern
The avatar upload SHALL follow the same storage pattern as school logos and teacher/student photos: validate content-type and size, store with `media://` URI, and manage via the IAM service.

#### Scenario: Avatar is stored consistently
- **WHEN** an avatar is uploaded
- **THEN** the system SHALL store the file using the `media://{user_id}/avatar/{media_id}.{ext}` URI pattern and store the URI in the `avatar_url` column on the `user` table

#### Scenario: Previous avatar is replaced
- **WHEN** a user uploads a new avatar while already having one
- **THEN** the system SHALL update the `avatar_url` column to the new URI (the old file MAY remain in storage for garbage collection)

### Requirement: Avatar upload accepts drag-and-drop
The profile page SHALL use the existing `FileDropzone` component (or an adapted image variant) for avatar upload.

#### Scenario: User drag-drops an image
- **WHEN** the user drags an image file onto the avatar dropzone area
- **THEN** the system SHALL accept the file, display a preview, and upload on confirmation or immediately (matching existing dropzone behavior)

#### Scenario: User clicks to select file
- **WHEN** the user clicks the avatar dropzone area
- **THEN** the system SHALL open a file picker filtered to image types (JPG, PNG, WebP)

### Requirement: User can remove avatar
The system SHALL allow the user to remove their current avatar, reverting to the default avatar placeholder.

#### Scenario: User removes their avatar
- **WHEN** the user clicks the "Hapus" button while an avatar is displayed
- **THEN** the system SHALL set `avatar_url` to `NULL` in the database and the profile page SHALL display the default avatar placeholder

#### Scenario: User has no avatar
- **WHEN** the user has `avatar_url = NULL`
- **THEN** the system SHALL display a default avatar placeholder (icon or initials) and a "Ganti Foto" button (no "Hapus" button)

### Requirement: Avatar is displayed in profile header
The profile page SHALL display the user's avatar in the header section alongside their name and email.

#### Scenario: User has an avatar
- **WHEN** the profile page loads and the user has a non-null `avatar_url`
- **THEN** the system SHALL display the avatar image in a circular frame (96px x 96px)

#### Scenario: User has no avatar
- **WHEN** the profile page loads and the user has `avatar_url = NULL`
- **THEN** the system SHALL display a default placeholder with the user's initials or a generic icon

### Requirement: Avatar is displayed in sidebar
The existing sidebar user menu SHALL display the user's avatar (if available) in the avatar circle.

#### Scenario: Sidebar shows user avatar
- **WHEN** the user has an avatar and the sidebar renders
- **THEN** the sidebar SHALL display the user's avatar image instead of the default icon/initials

### Requirement: Media asset table in IAM database
The IAM service SHALL have a `media_asset` table (or reuse direct column storage) for avatar files.

#### Scenario: Avatar column exists on user table
- **WHEN** migration V20 is applied
- **THEN** the `user` table SHALL have an `avatar_url TEXT NULLABLE` column

#### Scenario: Avatar URL is returned in /me response
- **WHEN** `GET /api/v1/iam/me` is called
- **THEN** the response SHALL include `avatar_url` (the `media://` URI or a resolved HTTP URL)
