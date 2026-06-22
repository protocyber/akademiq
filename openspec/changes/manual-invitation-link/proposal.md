## Why

The iam-service invitation flow is currently blocked when the Resend email
provider cannot deliver to the invited address. Because the project uses
Resend's shared sandbox sender domain (`onboarding@resend.dev`), Resend can
only deliver to the single verified recipient on the account
(`fitrah.pro@gmail.com`). Any invitation to an unverified email address causes
the `send_invitation` call to fail, which triggers a rollback that **revokes**
the just-created invitation and returns a 500 error to the admin.

This makes the entire invitation feature unusable for real onboarding until a
public domain is verified in Resend. The admin needs a way to deliver
invitation links manually (e.g. via WhatsApp) as a temporary workaround.

The web frontend already displays the `activation_link` in the invite dialog
(`settings/users/page.tsx:1044-1048`), so the missing piece is purely
backend-side: email delivery failure must not destroy the invitation.

## What Changes

- Decouple invitation persistence from email delivery success in
  `invite_tenant_user`. When `send_invitation` fails, log a warning and keep
  the invitation in `pending` status rather than revoking it.
- Return the HTTP 201 response with `token` and `activation_link` regardless
  of whether the email was delivered, so the admin can copy and deliver the
  link manually.
- The acceptance flow (`/invitations/accept?token=...`) remains unchanged.

## Capabilities

### New Capabilities

- `iam-invitations`: Covers invitation creation, delivery, and acceptance,
  including the manual-link-delivery fallback.

### Modified Capabilities

- None.

## Impact

- Affected backend code:
  - `apps/backend/services/iam-service/src/commands.rs` — `invite_tenant_user`
    email-failure handling (around lines 550-562).
- No frontend changes required (activation link display already implemented).
- No database migration.
- No API contract change (response shape unchanged; only error behavior
  changes).
- No breaking changes.
- This change is intentionally temporary: once a public domain is verified in
  Resend, email delivery will work normally and the manual-link path remains
  as a convenience fallback.
