## 1. Backend Database & Models

- [x] 1.1 Create migration V20_add_profile_fields.sql with email_change_token table, avatar_url and pending_email columns on user table
- [x] 1.2 Add email_change_token model struct with token_hash, expires_at, consumed_at, revoked_at, created_at fields
- [x] 1.3 Add EmailChangeTokenRepository trait and PostgreSQL implementation with insert, find_by_user, mark_consumed, mark_revoked methods
- [x] 1.4 Update User model to include avatar_url: Option<String> and pending_email tracking
- [x] 1.5 Add database indexes: user_id on email_change_token, unique constraint on token_hash

## 2. Backend Email Verification Service

- [x] 2.1 Create email verification token generation function (32 random bytes → base64url → Argon2 hash)
- [x] 2.2 Implement request_email_change handler: validate new email, check uniqueness, revoke old tokens, generate new token, insert into email_change_token
- [x] 2.3 Add email template for verification email with Indonesian text and verification link
- [x] 2.4 Implement verify_email handler: validate token, check expiry, update user email, revoke all refresh tokens, mark token consumed
- [x] 2.5 Implement resend_email_verification handler: revoke current token, generate new token, send new email
- [x] 2.6 Implement cancel_email_change handler: mark pending token as revoked
- [x] 2.7 Update /me endpoint to include pending_email field from unconsumed email_change_token

## 3. Backend Password Management

- [x] 3.1 Create change_password handler: verify current password (Argon2), validate new password (min 8 chars), hash new password, update user, revoke all refresh tokens
- [x] 3.2 Add password validation: minimum 8 characters, return field error if invalid
- [x] 3.3 Implement refresh token revocation across all tenants for user
- [x] 3.4 Return PASSWORD_NOT_SET error if user has no current password

## 4. Backend Profile Management

- [x] 4.1 Create PATCH /api/v1/iam/me endpoint for updating full_name (validate non-empty, trimmed)
- [x] 4.2 Create POST /api/v1/iam/me/avatar endpoint: validate image (JPG/PNG/WebP, max 2MB), generate UUID, store as media:// URI, update avatar_url
- [x] 4.3 Create DELETE /api/v1/iam/me/avatar endpoint: set avatar_url to NULL
- [x] 4.4 Update GET /api/v1/iam/me to return avatar_url field
- [x] 4.5 Add file validation helpers for image type and size checking

## 5. Backend Route Registration

- [x] 5.1 Register POST /api/v1/iam/auth/request-email-change route
- [x] 5.2 Register POST /api/v1/iam/auth/verify-email route (public, no auth required)
- [x] 5.3 Register POST /api/v1/iam/auth/resend-email-verification route
- [x] 5.4 Register POST /api/v1/iam/auth/cancel-email-change route
- [x] 5.5 Register POST /api/v1/iam/auth/change-password route
- [x] 5.6 Register PATCH /api/v1/iam/me route
- [x] 5.7 Register POST /api/v1/iam/me/avatar route
- [x] 5.8 Register DELETE /api/v1/iam/me/avatar route

## 6. Frontend API Layer

- [x] 6.1 Create requestEmailChange API function with error handling for EMAIL_ALREADY_EXISTS and validation errors
- [x] 6.2 Create verifyEmail API function (public endpoint, no auth)
- [x] 6.3 Create resendEmailVerification API function
- [x] 6.4 Create cancelEmailChange API function
- [x] 6.5 Create changePassword API function with error handling for INVALID_CURRENT_PASSWORD and PASSWORD_NOT_SET
- [x] 6.6 Create updateProfile API function for PATCH /me
- [x] 6.7 Create uploadAvatar API function with multipart form data
- [x] 6.8 Create deleteAvatar API function

## 7. Frontend Hooks & State

- [x] 7.1 Create useRequestEmailChange hook with invalidation of /me query
- [x] 7.2 Create useVerifyEmail hook (no auth, standalone)
- [x] 7.3 Create useResendEmailVerification hook
- [x] 7.4 Create useCancelEmailChange hook with invalidation of /me query
- [x] 7.5 Create useChangePassword hook with token clearing and redirect logic
- [x] 7.6 Create useUpdateProfile hook with form state management
- [x] 7.7 Create useUploadAvatar hook with file handling
- [x] 7.8 Create useDeleteAvatar hook
- [x] 7.9 Update MeView type to include avatar_url and pending_email fields

## 8. Frontend Profile Page Components

- [x] 8.1 Create ProfileHeader component with avatar display (96px circle), user name, email with verification badge
- [x] 8.2 Create ProfileInfoForm component with editable full_name field (react-hook-form + zod)
- [x] 8.3 Create MembershipInfo component displaying tenant memberships and roles (read-only)
- [x] 8.4 Create EmailSection component with current email, pending email alert, change/resend/cancel actions
- [x] 8.5 Create PasswordSection component with conditional rendering: "Ganti Password" for password users, "Buat Password" for passwordless users
- [x] 8.6 Create AvatarUpload component using FileDropzone adapted for images with preview and delete option

## 9. Frontend Profile Page

- [x] 9.1 Create /profile/page.tsx with AuthGuard wrapper and SidebarLayout
- [x] 9.2 Integrate all profile components (ProfileHeader, ProfileInfoForm, EmailSection, PasswordSection, MembershipInfo, AvatarUpload)
- [x] 9.3 Add loading and error states for profile data fetching
- [x] 9.4 Implement form validation with Indonesian error messages using zod schemas
- [x] 9.5 Add toast notifications for all mutations (success and error)
- [x] 9.6 Implement conditional password section rendering based on password_set field

## 10. Frontend Verify Email Page

- [x] 10.1 Create /verify-email/page.tsx as public page (no AuthGuard)
- [x] 10.2 Extract token from query parameters
- [x] 10.3 Display loading spinner with "Memverifikasi email..." message
- [x] 10.4 Call verifyEmail API on mount
- [x] 10.5 Handle success: show success message, clear tokens, redirect to /login after 3 seconds
- [x] 10.6 Handle errors: display appropriate error messages (expired token, invalid token)
- [x] 10.7 Add "Kembali ke Profil" link for error states

## 11. Frontend Integration & Polish

- [x] 11.1 Update sidebar user menu to display avatar from MeView data
- [x] 11.2 Ensure all Indonesian translations are in place (labels, messages, placeholders)
- [x] 11.3 Test password section conditional rendering for all three user types (A, B, C)
- [ ] 11.4 Verify email verification flow end-to-end (request → email → verify → login with new email)
- [ ] 11.5 Verify password change flow (change password → logout → login with new password)
- [ ] 11.6 Verify password creation flow for passwordless users (create password → stay logged in)
- [x] 11.7 Test avatar upload and display in profile page and sidebar
- [x] 11.8 Test form validation and error handling for all profile sections
- [x] 11.9 Run typecheck and lint on all new code
- [ ] 11.10 Verify token revocation behavior (all refresh tokens revoked after password change or email verification)
