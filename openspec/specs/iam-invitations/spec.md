## Requirement: Invitation creation SHALL succeed regardless of email delivery outcome

The `invite_tenant_user` command MUST persist the invitation in `pending`
status, generate the token and activation link, and return an
`InvitationIssued` success result regardless of whether the email delivery
attempt succeeds or fails. When `send_invitation` returns an error, the
command MUST log a warning (including the error, the invited email, and the
invitation id) and MUST NOT revoke the invitation or return an error to the
caller. The `tenant_user.invited` outbox event MUST be enqueued in both the
success and failure cases.

#### Scenario: Email delivery fails — invitation remains valid

- **WHEN** an admin invites `guru@baru.com` and the email provider rejects the
  recipient (e.g. Resend sandbox domain limitation)
- **THEN** the invitation is persisted with status `pending`, the command
  returns `InvitationIssued` with `token` and `activation_link`, and the HTTP
  response is 201

#### Scenario: Email delivery fails — invitation is not revoked

- **WHEN** `send_invitation` returns `Err` during `invite_tenant_user`
- **THEN** the invitation row MUST NOT be revoked and MUST remain in a state
  that allows `accept_invitation` to succeed with the same token

#### Scenario: Email delivery succeeds — behavior unchanged

- **WHEN** `send_invitation` returns `Ok` (either delivered or log mode)
- **THEN** the command proceeds to enqueue the event and return success, identical
  to the pre-change behavior

#### Scenario: Warning is logged on email failure

- **WHEN** `send_invitation` returns `Err`
- **THEN** a `tracing::warn!` entry is emitted that includes the error, the invited
  email, and the invitation id, so operators can diagnose delivery health

## Requirement: The invitation activation link SHALL be available to the admin

The HTTP response of `POST /api/v1/iam/tenants/me/invitations` MUST include
the `token` and `activation_link` fields in the 201 body for every
successfully created invitation, regardless of email delivery outcome. The
activation link MUST be usable by an unauthenticated visitor to accept the
invitation via the public acceptance endpoint.

#### Scenario: Admin can copy the activation link after creation

- **WHEN** an admin creates an invitation and the response is 201
- **THEN** the response body contains `activation_link` pointing to
  `{public_web_base_url}/invitations/accept?token={token}`, and the admin can
  copy and deliver it manually

#### Scenario: Manually delivered link works end-to-end

- **WHEN** an admin creates an invitation, copies the `activation_link` from the
  response, and delivers it to the invitee via an out-of-band channel
- **AND** the invitee opens the link and accepts the invitation
- **THEN** the invitation is accepted, an account is created (or membership
  attached), and the invitee is signed in — identical to the email-delivered
  flow
