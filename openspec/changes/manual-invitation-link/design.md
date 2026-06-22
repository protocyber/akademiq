## Context

The iam-service `invite_tenant_user` command (`commands.rs:520-581`) creates a
tenant invitation and then synchronously sends an invitation email via the
configured `EmailClient`. The current implementation treats email delivery as
a hard dependency: if `send_invitation` returns an error, the command revokes
the just-created invitation row and returns a 500 to the caller.

In the current deployment, `EMAIL_PROVIDER=resend` with the Resend shared
sandbox sender domain (`onboarding@resend.dev`). Resend only permits delivery
to the single verified recipient on the account. Any invitation to an
arbitrary email address (e.g. a new teacher) is rejected by Resend, which
triggers the revoke-and-fail path, making the entire invitation feature
unusable for real onboarding.

The raw invitation `token` and `activation_link` are already generated and
returned in the HTTP 201 response body (`http.rs:563-569`), and the web
frontend already renders the link in the invite dialog
(`settings/users/page.tsx:1044-1048`) with a description telling the admin to
"share the activation link manually." The activation link is therefore
available for manual delivery — the only blocker is the backend revoking the
invitation on email failure.

## Goals / Non-Goals

**Goals:**

- Allow invitations to be created and accepted even when email delivery fails.
- Preserve the existing invitation token, acceptance flow, and API response
  shape so the frontend needs no changes.
- Keep email delivery as a best-effort side effect: when it works (e.g. after
  a public domain is configured), it works; when it fails, the invitation is
  still usable via manual link delivery.

**Non-Goals:**

- Add a "delivery method" parameter or WA-specific API endpoint.
- Change token storage, token format, or token lookup.
- Build a notification queue or outbox-based email delivery.
- Change the acceptance page UI or the set-password flow.
- Verify a public Resend domain (that is the eventual permanent fix, outside
  this change).

## Decisions

1. **Downgrade email failure from fatal to warning in `invite_tenant_user`.**

   Replace the revoke-and-return-error block (`commands.rs:550-562`) with a
   best-effort send: on `Err`, emit a `tracing::warn!` with the error, the
   invitation email, and the invitation id, then continue to enqueue the
   `tenant_user.invited` event and return the `InvitationIssued` success.

   The activation link remains available to the admin via the existing 201
   response and the existing frontend dialog.

   Alternative considered: add a `delivery_method` enum to the invite request
   (`"email"` vs `"link_only"`) so the admin can explicitly skip email.
   Rejected because it adds API surface and UI complexity for a temporary
   workaround; the always-show-link frontend behavior already covers the
   manual-delivery case.

2. **Do not revoke the invitation on email failure.**

   The current revoke call (`invitation_repo.revoke`) exists solely to free
   the `pending_email_unique` slot so the same email can be re-invited. Once
   email failure is non-fatal, the invitation stays `pending` and the slot
   remains occupied — which is correct, because the invitation is still valid
   and usable. If the admin wants to re-invite, they revoke manually via the
   existing `POST /tenants/me/invitations/:id/revoke` endpoint.

3. **Keep the outbox event enqueue after the email attempt.**

   The `tenant_user.invited` event should still be enqueued regardless of
   email outcome. The event represents "an invitation was created," not "an
   email was sent." Downstream consumers (if any) should see the invitation
   as created either way.

4. **Do not add an email-status field to the API response.**

   Whether the email was sent, failed, or skipped (log mode) is an operational
   detail. The admin's actionable information is the activation link, which is
   always present. Adding `email_sent: bool` would invite UI branching for no
   user benefit in the current temporary setup.

   Alternative considered: return `email_sent: bool` so the frontend can show
   "Email terkirim" vs "Email gagal, salin link manual." Rejected because the
   frontend already instructs the admin to share the link manually regardless,
   and the distinction adds complexity without changing the admin's action.

## Risks / Trade-offs

- **Silent email failures in Resend mode.** When a public domain is eventually
  configured, a transient Resend outage would no longer surface as a user
  error — the admin would see "invitation created" but the email never
  arrives. Mitigation: the `warn!` log carries `error`, `email`, and
  `invitation_id`; operator dashboards should alert on this log line. This is
  an acceptable trade-off because the admin can always deliver the link
  manually, and the log is the source of truth for delivery health.

- **Pending invitations accumulate if email is the intended primary delivery.**
  If the admin expects email and does not notice the link in the dialog, an
  invitation could sit `pending` without the invitee ever receiving it.
  Mitigation: the frontend dialog already shows the link with manual-share
  guidance; no additional UX work is required for this change.

- **No automatic retry.** A failed email is not retried. This is consistent
  with the current architecture (no email queue). If retry becomes needed, it
  should be addressed via a proper outbox/queue pattern in a separate change,
  not bolted onto this temporary fix.

- **Security of the activation link in the API response.** The raw token and
  link are returned in the 201 body. This is pre-existing behavior and is
  acceptable because the admin has `PERM_USER_INVITE`, the token is
  single-use, and the link is the intended manual-delivery vehicle. This
  change does not alter the exposure surface.
