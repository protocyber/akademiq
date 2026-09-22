# Design Spec: Web Admin Phase 2 — Operator-led Onboarding

Date: 2026-09-14
Topic: `apps/web-admin` Phase 2 — creating tenants, inviting admins, resetting
passwords, and diagnosing stalled registrations
Status: approved (design)
Predecessor: `docs/superpowers/specs/2026-09-12-web-admin-roadmap-design.md` §3

## 1. Scope

Phase 2 of the operator console roadmap: the onboarding journey. Today an
operator cannot create a tenant from the UI at all — the only path is the
public self-service registration endpoint, or direct SQL.

Four items, in the order they are built:

1. Create a tenant from the UI
2. Invite the first tenant admin (and re-issue the link)
3. Reset a tenant user's password
4. Diagnose stalled registrations

**Links are copied by hand in this phase** — but the reason is narrower than
the roadmap assumed, and the correction matters.

`iam-service/src/email.rs` **does exist**: it builds activation links
(`activation_link()`, `:95`), renders HTML and text bodies, and supports two
modes — `Log` and `Resend` (`:18-21`). `invite_tenant_user` already calls
`send_invitation` (`commands.rs:715`). The Phase 1 roadmap's claim that there
is "no mail infrastructure anywhere in the backend" was wrong; it was written
from a grep for `lettre`/SMTP, and this service uses a HTTP API provider
instead.

What is true: `EMAIL_PROVIDER` defaults to `log` (`config.rs:57`), so in any
environment that has not set a Resend API key, the invitation "send" writes a
warning to the service log and no mail leaves the system.

So this phase surfaces the link in the operator UI regardless of provider —
that is the reliable path today, and it is what the operator asked for. It is
NOT a claim that delivery is impossible. Wiring `EMAIL_PROVIDER=resend` and
verifying real delivery stays Phase 4, and the roadmap's rationale for that
phase should be corrected to say "delivery is unconfigured and unverified"
rather than "no mailer exists".

## 2. Verified starting conditions

Each of these was read in the source before the design was settled. They are
recorded because two earlier design attempts in this phase rested on
assumptions that turned out to be false.

| Fact | Where | Consequence |
|---|---|---|
| `password_hash` is nullable | `iam` `V9__google_oauth.sql` | Passwordless users are already a supported state |
| `insert_user_with_roles` takes `password_hash: Option<&str>` | `iam/repo.rs:586-592` | No repo change needed |
| …and derives status from it: `Some` → `active`, `None` → **`pending`** | `iam/repo.rs:598-602` | An operator-created admin is born `pending` |
| `accept_invitation` already runs a passwordless path and issues a token | `iam/commands.rs:808-818` | The mechanism exists; it is simply not wired to operator creation |
| `invite_tenant_user`'s handler already returns `activation_link` and `token` | `iam/http.rs:585-586` | Invitation needs a platform-scoped wrapper, not new logic |
| `iam_client.create_user` has exactly ONE production caller | `billing/commands.rs:164` | Widening its signature is contained |
| The janitor deletes the IAM user, the tenant, then the row, every 60s for anything older than 5 minutes | `billing/commands.rs:485-500` | A manual "clear" button would duplicate it |
| `email.rs` exists, builds activation links, and has `Log`/`Resend` modes | `iam/email.rs:18-21, 95` | Link construction is reusable; do not rebuild it |
| `EMAIL_PROVIDER` defaults to `log` | `iam/config.rs:57` | Unconfigured environments log instead of sending |
| `issue_set_password_token` returns the RAW token; only its hash is stored | `iam/commands.rs:2614-2626` | The raw value is returnable exactly once, at creation |

### 2.1 The trap that shaped this design

`resend_set_password_token` (`iam/commands.rs:1001`) refuses to issue a token
when **either** condition holds:

```rust
if user.password_hash.is_some() || user.status != UserStatus::Active
```

and returns `Ok` with `set_password_token: None` — **not** an error.

This bit the design twice:

- An earlier plan created the admin with a generated password, then asked this
  function for an activation link. `password_hash.is_some()` → no link.
- The current plan creates the admin with no password, so the user is
  `pending`. `status != Active` → **also** no link.

Both would have produced a "tenant created" screen with no link and no
explanation. So: **anything that needs a link at creation time issues it at
the point of creation, never via `resend`.** `resend` is used only where it
genuinely fits — resetting an `Active` user who already has a password (§5).

## 3. Creating a tenant (§ item 1)

**`POST /api/v1/platform/tenants`** — operator supplies school name, admin
email, admin full name, and plan. No password field exists in the form.

Forwards to billing's existing `register_tenant` over `X-Service-Token` with
`password: None`. The saga is reused exactly as it stands — same ordering, same
compensating delete on failure. No new branch is added to it.

Three signatures relax from `String` to `Option<String>`:
`InternalCreateUserBody.password`, `RegisterUserInput.password`, and the
hashing branch inside `register_user`. `register_user` switches from
`insert_with_role` (which takes `&str`) to `insert_user_with_roles` (which
already takes `Option<&str>` and already sets the status).

When the password is absent, `register_user` issues a set-password token
immediately and returns it, mirroring `accept_invitation:818`. The link flows
back through billing and platform-service to the UI, which renders it with a
copy button.

**Protecting the public path.** `register_user` also serves public
registration. `validate_register_user:2403` enforces a minimum of 8
characters; that validation must still apply whenever a password is present,
and be skipped only when an internal caller explicitly sends `None`. A test
must prove public registration still rejects a passwordless attempt — this is
the one place where a careless change would open a hole rather than a bug.

## 4. Inviting the first admin (§ item 2)

**`POST /api/v1/platform/tenants/{tenant_id}/invitations`**

IAM's `invite_tenant_user` already produces the token and the handler already
returns `activation_link`. The only thing missing is a platform-scoped entry
point: the tenant-scoped route takes `tenant_id` from the school admin's JWT,
which an operator does not hold. The operator route passes `tenant_id` as a
path parameter, authenticated by `X-Service-Token`.

This is also the recovery path when the link from §3 is lost or expires, which
is why it remains necessary even though §3 already produces one.

`invite_tenant_user` returns `409` when the user is already a member of that
tenant (`commands.rs:682`). That message reaches the operator verbatim; it is
information, not a failure to be flattened.

## 5. Resetting a password (§ item 3)

**`POST /api/v1/platform/users/{user_id}/reset-password`**

IAM has a tenant-scoped equivalent at
`/tenants/me/users/{id}/reset-password`. The operator variant takes `user_id`
directly.

This is where `resend_set_password_token` genuinely fits: it targets an
`Active` user who already has a password, which is exactly a reset.

But it returns `Ok` with `set_password_token: None` for a user that does not
qualify. **The endpoint MUST distinguish the two outcomes**: a token means a
link to render; `None` means saying why — the user has never set a password,
or is not active — rather than a success screen with nothing on it. Per §2.1,
a silent nothing is the failure mode this whole design is guarding against.

## 6. Stalled registrations (§ item 4) — scope changed

The roadmap called for retry and clear buttons. Reading the janitor changed
that, and the change was accepted.

**"Clear" already happens.** The janitor (`billing/commands.rs:485-500`) does
precisely what the button would: deletes the IAM user, deletes the tenant,
deletes the row — every 60 seconds, for anything older than 5 minutes. A
manual button would beat it by a few minutes while duplicating compensation
logic that already exists.

**"Retry" is the wrong shape.** A stalled registration means some resources
exist and others do not — the IAM user was created, the tenant was not.
Re-running from the start fails with `EMAIL_ALREADY_EXISTS` because the user
is still there. A correct retry resumes the saga from its failure point, which
is a state machine far larger than its value for a table whose rows live five
minutes.

**What the operator actually needs is the reason.** Today the cause exists
only in service logs (`register_tenant:174`, and the janitor's own
`tracing::error!`).

So: store the last failure message on `pending_registration`, surface it on the
board, and let the janitor do the cleaning. An operator who reads "email
already registered" knows to look for an existing user; one who reads "IAM did
not respond" knows to wait.

**No "clear now" button ships in this phase.** It would beat the janitor by
minutes, and the board is read-only by the Phase 1 spec (§4.5), which an
operator has already seen and an e2e test already asserts. Revisit only if the
janitor's five-minute window proves too slow in practice.

## 7. Cross-cutting requirements

- Every new platform endpoint calls `require_platform_admin(&auth)?` as its
  first statement.
- Every mutating endpoint writes `operator_audit` **only after** a 2xx from
  the downstream service, matching suspend/reactivate.
- Errors carrying operator-meaningful codes (`409` on invitation, billing's
  validation errors) propagate intact rather than flattening to
  `DOWNSTREAM_ERROR`. Extend the allowlist in `map_downstream_error` as needed.
- Links are secrets. They are never logged, never written into `operator_audit`
  metadata, and never persisted by the frontend.

## 8. Testing

- **The passwordless path must be driven end to end**, not asserted from a
  seeded row: create a tenant through the operator endpoint and confirm a
  usable set-password token comes back and that the user is `pending`.
- **Public registration must still reject a missing password.** This guards
  the one change that touches a public code path.
- **The `None`-token branch of reset-password must be tested**, since the
  silent-success shape is the specific hazard §2.1 documents.
- For the failure-reason field: assert the message is stored on a real failed
  saga run, not written directly into the row.
- Frontend: link rendering and the copy control follow the existing
  `useCopyId` pattern; branch decisions go in pure `.ts` helpers, since there
  is still no `.vue` mount harness.

## 9. Explicitly out of scope

- Automated email delivery (Phase 4).
- Resuming a stalled saga from its failure point (§6).
- Impersonation, operator management, and searchable audit filters — these are
  Phase 3.
