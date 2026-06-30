## Purpose

Manage user profile details, read-only information, name updates, role and tenant memberships, and Indonesian localization.

## Requirements

### Requirement: Profile page is accessible to all authenticated users
The system SHALL expose a `/profile` route that is accessible to any authenticated user regardless of role or tenant membership. The page SHALL be wrapped in the existing `AuthGuard` and `SidebarLayout` components.

#### Scenario: Authenticated user navigates to /profile
- **WHEN** an authenticated user navigates to `/profile`
- **THEN** the system SHALL render the profile page within the sidebar layout showing the user's profile sections

#### Scenario: Unauthenticated user navigates to /profile
- **WHEN** an unauthenticated user navigates to `/profile`
- **THEN** the system SHALL redirect the user to the login page

### Requirement: User can view their profile information
The system SHALL display the user's current profile information in read-only format including: username, full name, email (with verification status badge), memberships (tenants and roles), and account status.

#### Scenario: User views profile page
- **WHEN** the profile page loads
- **THEN** the system SHALL display the user's username (read-only), full name, email with `EmailVerifiedBadge`, memberships with tenant names and role badges, and account status

#### Scenario: User has pending email change
- **WHEN** the user has a pending (unconsumed, unrevoked, unexpired) email change token
- **THEN** the system SHALL display the pending new email address with a "Belum Terverifikasi" badge and options to resend or cancel

### Requirement: User can edit their full name
The system SHALL allow the user to update their `full_name` field via the profile page. The field SHALL be validated as non-empty and trimmed.

#### Scenario: User updates full name successfully
- **WHEN** the user enters a valid non-empty full name and submits the profile form
- **THEN** the system SHALL send `PATCH /api/v1/iam/me` with `{ full_name }` and display a success toast "Profil berhasil diperbarui"

#### Scenario: User submits empty full name
- **WHEN** the user submits the profile form with an empty or whitespace-only full name
- **THEN** the system SHALL display a client-side validation error "Nama lengkap wajib diisi" and SHALL NOT submit the request

### Requirement: Username is read-only on profile
The system SHALL display the user's username as a non-editable field on the profile page.

#### Scenario: User views username field
- **WHEN** the profile page renders
- **THEN** the username field SHALL be displayed with a lock icon or disabled state and SHALL NOT be submittable

### Requirement: Profile page displays membership information
The system SHALL display the user's tenant memberships and roles in a read-only card section.

#### Scenario: User with single tenant views memberships
- **WHEN** a user with one tenant membership views their profile
- **THEN** the system SHALL display the tenant name, role badges, and account status

#### Scenario: User with multiple tenants views memberships
- **WHEN** a user with memberships in multiple tenants views their profile
- **THEN** the system SHALL display each tenant with its associated roles

### Requirement: MeProfile response includes avatar and pending email
The `GET /api/v1/iam/me` endpoint SHALL include `avatar_url` (nullable string) and `pending_email` (nullable string) fields in the response body.

#### Scenario: User has no avatar and no pending email
- **WHEN** `GET /api/v1/iam/me` is called for a user without avatar or pending email change
- **THEN** the response SHALL include `avatar_url: null` and `pending_email: null`

#### Scenario: User has avatar and pending email
- **WHEN** `GET /api/v1/iam/me` is called for a user with an avatar and an unconsumed email change token
- **THEN** the response SHALL include the avatar URL and the pending new email address

### Requirement: Profile page uses Indonesian labels
All user-facing labels, messages, and toasts on the profile page SHALL be in Indonesian.

#### Scenario: User views profile page labels
- **WHEN** the profile page renders
- **THEN** section headers SHALL use Indonesian labels such as "Profil Saya", "Informasi Akun", "Email", "Password", "Keanggotaan"
