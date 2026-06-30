## Context

The Akademiq platform is a multi-tenant school management system built as a Rust/Axum microservices monorepo with a Next.js frontend. The IAM service manages user identity, authentication, and authorization using Argon2id password hashing, RS256 JWT tokens (identity + access), and opaque Argon2-hashed tokens for invitations and password resets.

Currently, users have no self-service profile management. The sidebar already links to `/profile` but the page does not exist. Three user archetypes exist:

- **Type A**: Password-only users (registered via public signup or created by admin with password)
- **Type B**: Google-only users (registered via Google OAuth, `password_hash = NULL`)
- **Type C**: Hybrid users (have both password and Google OAuth linked)

Password is optional — `password_hash` is nullable. Users created by admin without a password are in `pending` status until they set one. The existing `POST /api/v1/iam/auth/set-password` endpoint already supports two paths: token-based (from invitation links) and session-based (for authenticated passwordless users).

Email services use the Resend HTTP API (or log-only in dev). The existing `email.rs` module has one template (invitation email). No email verification flow exists — `email_verified` is only set `true` via Google OAuth claims.

Media storage follows a local `media://` URI pattern in `media_asset` tables within each service's database. No Cloudinary integration exists.

## Goals / Non-Goals

**Goals:**
- Provide all authenticated users a `/profile` page to view and manage their account
- Allow users to edit their `full_name` (single field)
- Allow users to change their email with full verification flow (token-based)
- Allow password users to change their password (with session revocation across all tenants)
- Allow passwordless (Google-only) users to create a password
- Allow all users to upload/manage a profile avatar photo
- Display membership information (tenants, roles) as read-only context
- Use Indonesian for all UI labels and messages, English for code

**Non-Goals:**
- Username editing (read-only on profile page)
- Admin-initiated email changes (only self-service)
- Two-factor authentication or MFA
- Account deletion / deactivation from profile
- Password complexity rules beyond min 8 characters
- Social account linking/unlinking from profile (Google connect/disconnect)
- Multi-language support (only Indonesian UI)

## Decisions

### D1: Email stored in separate `email_change_token` table (not columns on `user`)

**Decision**: Create a dedicated `email_change_token` table following the existing `set_password_token` pattern.

**Rationale**: The `user` table is already lean with clear separation of concerns. Token-based flows (invitation, set-password) consistently use separate tables with `token_hash`, `expires_at`, `consumed_at`, and `revoked_at` columns. This pattern supports audit trails, multiple pending changes (if needed later), and clean revocation.

**Alternative considered**: Adding `pending_email`, `pending_email_token_hash`, `pending_email_expires_at` columns directly to the `user` table. Rejected because it bloats the user table, limits to one pending change, provides no history, and stores security tokens alongside identity data.

### D2: Avatar stored as `avatar_url` column on `user` table (not `media_asset` table)

**Decision**: Add a single `avatar_url TEXT NULLABLE` column to the `user` table.

**Rationale**: Each user has exactly one avatar. The `media_asset` pattern (with insert/deactivate/activate cycles) used in billing and academic-ops is designed for entities that may have multiple media assets with versioning. For a single photo per user, a direct column is pragmatic. Avatar is cross-tenant (belongs to the user identity, not a tenant membership), so it lives in IAM.

**Alternative considered**: Creating a `media_asset` table in IAM. Rejected as overkill for one photo per user with no versioning needs. If avatar history/versioning is needed later, a migration to `media_asset` can be done.

### D3: Reuse existing `set-password` endpoint for passwordless users

**Decision**: Google-only users (Type B) use the existing `POST /api/v1/iam/auth/set-password` endpoint (session-based path) to create their first password. A new `POST /api/v1/iam/auth/change-password` endpoint is created for users who already have a password (Types A & C).

**Rationale**: The `set-password` endpoint already supports authenticated sessions without tokens — it resolves the user from the access token and sets the password directly. Creating a separate "first password" endpoint would duplicate existing functionality. The `change-password` endpoint is distinct because it requires verifying the current password and revoking sessions.

**Alternative considered**: A single unified endpoint that auto-detects whether the user has a password. Rejected because the security requirements differ fundamentally: change-password requires current password verification and session revocation, while set-password does not.

### D4: Revoke ALL refresh tokens across all tenants after password change

**Decision**: Both `change-password` and `verify-email` operations revoke all refresh tokens for the user across all tenants.

**Rationale**: Password is a global credential (not per-tenant). If a password is compromised, the attacker could obtain tokens for any tenant the user belongs to. The majority of users have only one tenant, so the UX impact is minimal. This follows industry standard (Google, GitHub) for credential-level changes.

**Alternative considered**: Revoke only tokens for the current tenant. Rejected because password is global — an attacker with the old password could still obtain new tokens for other tenants.

### D5: Email verification uses Flow B (frontend-controlled, POST with token)

**Decision**: The verification link in the email points to `/verify-email?token=xxx`. The frontend page shows a spinner, POSTs the token to a backend endpoint, and displays success/error based on the response.

**Rationale**: This gives the frontend full control over UX (loading states, error messages, retry options). A backend GET redirect (Flow A) would work but provides less feedback to the user and makes error handling harder.

**Alternative considered**: Backend GET endpoint that verifies the token and redirects to `/profile?verified=true`. Rejected because it provides no error feedback on the verification page itself and makes retry/cancel flows harder to implement.

### D6: Resend generates new token (Opsi A)

**Decision**: Each "resend verification" request revokes the previous token and generates a new one with a fresh 24-hour expiry.

**Rationale**: Follows the existing `set_password_token` pattern. Old tokens are invalidated, reducing the window of exposure if a token is intercepted. Fresh expiry prevents tokens from accumulating long lifetimes through repeated resends.

### D7: Password validation — min 8 characters only

**Decision**: The password policy is "minimum 8 characters" with no complexity requirements (uppercase, digits, symbols).

**Rationale**: This is consistent with all existing password validation in the codebase (register, set-password, admin create-user). Adding complexity rules only for change-password would be inconsistent and confusing.

### D8: Media storage for avatar — local storage following existing pattern

**Decision**: Avatar upload follows the same pattern as school logos and teacher/student photos: validate content-type and size, generate a UUID-based `media://` URI, store the URI in the database.

**Rationale**: Consistency with existing media handling across billing-service and academic-ops-service. The `media://` URI scheme is the established pattern. No external CDN dependency.

## Risks / Trade-offs

**[Risk] Linear scan for email_change_token verification** → Mitigation: The existing `set_password_token` and `tenant_invitation` patterns use the same linear scan with Argon2 verify. The number of unconsumed tokens per user is expected to be very small (typically 0-1). If this becomes a concern at scale, a token prefix index can be added later.

**[Risk] Token revocation on email verification causes forced logout** → Mitigation: The verification page clearly informs the user that they will need to log in again. The frontend shows a countdown/redirect to the login page after successful verification.

**[Risk] Avatar stored on `user` table instead of `media_asset`** → Mitigation: This is a deliberate simplification. If avatar versioning or history is needed later, a migration to `media_asset` can be done in a separate change. The column stores a URI string, making migration straightforward.

**[Risk] Email change during active session** → Mitigation: During the pending state (before verification), the user continues to use their current email for login. Only after successful verification does the email change take effect, at which point all sessions are revoked.

**[Risk] Google-only user creates password, then changes email** → Mitigation: These are independent operations. The password creation does not affect email verification, and vice versa. Both operations are self-contained.
