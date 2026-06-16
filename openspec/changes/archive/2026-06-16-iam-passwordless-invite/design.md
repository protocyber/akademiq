# Design — iam-passwordless-invite

## Context

`accept_invitation` (`commands.rs:563`) branches on whether the invited email
already has an account:

```
accept_invitation(token, [password], [full_name])
  │  find_invitation_by_token → validate status/expiry
  │
  ├─ user exists for invitation.email?
  │    └─ YES → accept_for_existing_user(invitation_id, user_id)
  │             (membership only — ALREADY passwordless ✓)
  │
  │    └─ NO  → accept_with_user(invitation_id, user_id,
  │                              username, password_hash, full_name)
  │             INSERT "user" (... password_hash NOT NULL ...) ✗
  │
  └─ issue_scoped_tokens(...) → TokenPair  (signed in immediately)
```

The blocker is the new-account path: the `user` row needs a `password_hash`, and
`validate_accept_invitation` enforces `password.len() >= 8`. We want the invitee
to click one button, get a usable session, and set a password later.

## Goals

- Accept-by-button works for **both** existing and new accounts.
- A new account can exist **without** a password and still hold a valid session.
- The user can set a password later via a **single-use, time-bound** token (or
  while authenticated), after which password login behaves normally.
- Existing-account accept path is unchanged.

## Decision 1 — How to represent "no password yet"

Options:

| Option | Representation | Pros | Cons |
|--------|----------------|------|------|
| A | `password_hash` NULLable | minimal schema; absence = not set | every password-login query must guard NULL |
| B | `password_status` enum (`set`/`unset`) + keep hash NULL when unset | explicit, queryable, future-proof (e.g. `reset_required`) | extra column + migration |
| C | sentinel hash value | no schema change | fragile, easy to misread as a real hash |

**Choice: A, with a guarded login path** (promote to B only if we later need more
password states). `password_hash` becomes nullable; password login MUST reject a
NULL-hash account with an actionable code (e.g. `PASSWORD_NOT_SET`) rather than a
generic "invalid credentials", so the UI can route the user to set-password.
OAuth login is unaffected.

> Rationale: the only state we need today is "set vs not set", and NULL already
> encodes that. A dedicated enum is easy to add later if reset-required or
> must-rotate states appear.

## Decision 2 — Set-password token vs authenticated-only

Accepting returns a scoped token pair, so a freshly-accepted user is already
signed in and could set a password from an authenticated screen with no separate
token. But we also want the link to work if the session is lost (new device,
closed tab). 

**Choice: support both.** Issue a single-use, time-bound **set-password token**
on passwordless accept, AND allow an authenticated no-password user to set their
password from session. The set-password endpoint accepts either proof:

```
POST /api/v1/iam/auth/set-password
  body: { password, token? }     // token OR a valid access session
  → consumes token (single-use) / verifies session targets a NULL-hash account
  → hash_password + persist, mark password set
  → 204 (or refreshed tokens)
```

Token storage mirrors the invitation token: a row with `user_id`, hashed token,
`expires_at`, `consumed_at`. Consumption is single-use (guard like the
invitation accept).

## Decision 3 — `full_name` when the button carries no form

`accept_with_user` currently requires `full_name`. With a button-only UI there is
no name input. Source order:

1. invitation record (if the admin supplied a name at invite time), else
2. identity/email local-part as a placeholder the user can edit later in profile.

`full_name` and `password` become **optional** on the accept request for the
new-account path; `validate_accept_invitation` is relaxed accordingly (existing
path that *does* send a password still validates length).

## Flow after change

```
NEW account, button-only:
  click "Terima Undangan"
    → accept_invitation(token)            // no password, no name required
    → accept_without_password(...)        // INSERT user, password_hash NULL
    → issue set-password token
    → issue_scoped_tokens → signed in
    → land in app  (banner/CTA: "Set a password to enable password login")

  later:
    set-password screen (token or session)
    → POST /auth/set-password
    → password login now works

PASSWORD login on a NULL-hash account:
    → 4xx PASSWORD_NOT_SET  → UI routes to set-password
```

## Risks / open questions

- **Security:** a passwordless account is reachable only via the OAuth path or
  the scoped session minted at accept; ensure no flow lets a NULL-hash account be
  password-authenticated. Set-password token must be single-use + short-lived.
- **Email delivery** of the set-password link reuses existing invitation email
  plumbing if available; otherwise the link/token is surfaced inline as the
  invitation flow does today (out of scope to build new email infra here).
- **Sequencing:** backend lands first; the web button-only page + set-password
  screen follow once the endpoints exist.
