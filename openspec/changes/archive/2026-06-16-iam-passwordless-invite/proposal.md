## Why

The accept-invitation page asks the invited person to type a full name, a
password, and the token before they can join (`app/invitations/accept/page.tsx`).
We want the page to be a single **"Terima Undangan"** button: the user clicks,
the membership activates, and they land in the app. Password setup happens later,
on their own time, via a dedicated set-password flow.

Today only **half** of this is possible. `accept_invitation`
(`iam-service/src/commands.rs:563`) has two paths:

- **Existing account** (`accept_for_existing_user`) — already passwordless; it
  just attaches the membership. The button-only UX works for this case as-is.
- **New account** (`accept_with_user`) — `INSERT INTO "user"` requires a
  `password_hash` (`repo.rs:1576`), and `validate_accept_invitation` rejects a
  password shorter than 8 chars. A new invitee **cannot** be created without
  choosing a password right now.

There is also **no self-service set-password endpoint** — the only password-reset
path is `admin_reset_password` (admin-initiated). So "password belakangan"
requires new backend capability. This change delivers the backend first; the web
button-only page follows once the backend is in place.

## What Changes

- **MODIFIED account creation on invite accept** — a new account MAY be created
  **without a password**, in a state that requires the user to set one before
  password login. The membership and roles are granted exactly as today; only the
  password requirement is lifted from the accept step.
- **NEW set-password token + flow** — when a passwordless account is created (or
  on demand), the system issues a single-use, time-bound **set-password token**.
- **NEW self-service set-password endpoint** — `POST` that consumes a valid
  set-password token (or an authenticated session for a no-password account) and
  sets the password, after which password login works normally.
- **MODIFIED accept-invitation API** — `password` and `full_name` become optional
  for the new-account path; `full_name` falls back to the invitation/identity
  data when omitted. Accepting returns the same scoped token pair so the user is
  signed in immediately.
- **WEB (follow-up, gated on backend)** — `app/invitations/accept/page.tsx`
  becomes a single "Terima Undangan" button; a separate set-password screen
  consumes the set-password token.

## Capabilities

### Modified Capabilities

- `iam-service`: invitation acceptance can create a **passwordless** account that
  must set a password before password login; adds a single-use, time-bound
  set-password token and a self-service set-password endpoint. `accept` no longer
  requires a password for the new-account path.
- `tenant-user-management`: accepting an invitation no longer requires the invitee
  to choose a password up front; the invited user may set it later.
- `web-auth-onboarding`: the accept-invitation page becomes button-only, with a
  separate set-password screen (web work sequenced after the backend).

## Impact

- **Backend (`iam-service`):**
  - Allow a no-password account state (nullable `password_hash` or a
    `password_status`/flag) + migration.
  - New `accept_without_password` repo path (mirror of `accept_with_user` minus
    the hash); relax `validate_accept_invitation` for the new-account path.
  - New set-password token store (single-use, expiring) + issue/consume logic.
  - New self-service set-password handler + route; reject password login for a
    no-password account with a clear, actionable error.
  - Tests: passwordless accept, set-password happy path, token single-use/expiry,
    password-login-blocked-until-set, existing-user path unchanged.
- **Docs:** update IAM auth/invitation contracts and ERD for the new token/flag.
- **Web (`apps/web`):** button-only accept page + set-password screen — **after**
  the backend ships (tracked here, implemented in sequence).
- **Out of scope:** email delivery of the set-password link (reuse existing email
  plumbing if present; otherwise surface the link/token as today), password reset
  policy changes, and OAuth-only accounts.
