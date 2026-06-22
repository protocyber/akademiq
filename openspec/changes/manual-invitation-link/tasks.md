## 1. Backend: Decouple invitation persistence from email delivery

- [x] 1.1 In `apps/backend/services/iam-service/src/commands.rs`, modify `invite_tenant_user` (around lines 550-562) so that an `Err` from `email_client.send_invitation` emits a `tracing::warn!` (with error, invited email, and invitation id) instead of revoking the invitation and returning an error.
- [x] 1.2 Remove the `invitation_repo.revoke(...)` call and the `return Err(AppError::internal(...))` from the email-failure branch so the command continues to enqueue the `tenant_user.invited` event and returns `InvitationIssued`.
- [x] 1.3 Verify the `tenant_user.invited` outbox event is enqueued in both the email-success and email-failure paths.

## 2. Backend: Tests

- [x] 2.1 Update or add an integration test asserting that `invite_tenant_user` returns `Ok(InvitationIssued)` and the invitation remains `pending` when `send_invitation` fails.
- [x] 2.2 Add or update a test asserting the `warn!` log is emitted on email failure (or verify via the existing log-capture pattern used in iam-service integration tests).
- [x] 2.3 Verify the existing email-success path test still passes unchanged.

## 3. Verification

- [x] 3.1 Run the backend lint command for `apps/backend` (or the iam-service crate).
- [x] 3.2 Run the backend test command for `apps/backend` (or the iam-service crate).
- [ ] 3.3 Manually verify: admin invites a new email, dialog shows the activation link, link copied and opened in an incognito session accepts the invitation end-to-end.
