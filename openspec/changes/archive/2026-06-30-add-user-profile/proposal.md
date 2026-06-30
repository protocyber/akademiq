## Why

Users currently have no way to view or manage their own account information. The sidebar menu includes a "Profil Saya" link that leads nowhere, and critical self-service features like changing passwords, updating profile information, or managing email addresses are missing. This forces users to rely on administrators for basic account changes and creates a poor user experience.

## What Changes

- Add a `/profile` page accessible to all authenticated users where they can view and edit their profile information
- Enable users to change their email address with a full verification flow (token-based email confirmation)
- Allow users to change their password (for users with passwords) or create a password (for Google-only users)
- Add avatar/photo upload functionality for user profiles
- Display membership information (tenants, roles) in read-only format
- Add email verification page at `/verify-email` that users land on after clicking verification links

## Capabilities

### New Capabilities
- `user-profile`: Profile page UI and backend endpoints for viewing/editing profile information (full name, avatar, membership info)
- `email-verification`: Email change flow with token-based verification, including request, verify, resend, and cancel operations
- `password-management`: Password change for existing password users and password creation for passwordless (Google-only) users, with session revocation
- `user-avatar`: Avatar upload and management using existing media storage patterns

### Modified Capabilities
<!-- No existing capabilities are being modified - this is entirely new functionality -->

## Impact

**Backend (IAM Service)**:
- New database migration (V20): `email_change_token` table, `avatar_url` column on `user` table
- 5 new API endpoints in IAM service for profile management
- New email template for email verification
- Updated `GET /me` endpoint to include `avatar_url` and `pending_email` fields

**Frontend (Web)**:
- 2 new pages: `/profile` and `/verify-email`
- 5 new React components for profile sections
- 5 new TanStack Query mutations for profile operations
- 1 new Zod schema file for validation
- Updated `MeView` type to include new fields

**Database**:
- New table: `email_change_token` (follows existing token patterns)
- New columns: `avatar_url` (nullable text), `pending_email` (nullable varchar) on `user` table

**Security**:
- Password changes revoke all refresh tokens across all tenants (credential-level security)
- Email verification revokes all refresh tokens after successful verification (identity-level security)
- Token-based email verification follows existing patterns (set_password_token, tenant_invitation)

**User Experience**:
- Users gain full control over their profile without admin intervention
- Clear feedback on email verification status and pending changes
- Adaptive password section (create vs. change) based on user type
- Logout from all devices after sensitive operations (password change, email verification)
