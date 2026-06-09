# Design — Tenant User Management (IAM extension)

## Context

Supplies the human actors for the report-card approval chain. Built as an
extension of the existing `iam-service` rather than a new service, because it
operates entirely on IAM's user/role/membership model.

## Key decisions

### 1. Two missing pieces: the principal role and login accounts

Two gaps block the report-card demo:

- **No `principal` role.** The report-card lifecycle needs a principal to
  approve, but only `homeroom_teacher` is seeded. We add `principal` via
  migration `V3` with a stable `role.code` and a `ROLE_PRINCIPAL` constant in
  `common-auth` (the codes MUST match, per the existing seed comment).
- **No way to create non-admin login accounts.** Registration only mints the
  tenant admin. Invitations fill this gap.

### 2. Teacher *profile* vs teacher *account* are different things

Academic-ops (phase 3) creates `teacher` rows (NIP, name) as **operational
profiles** — they exist so a teaching assignment can point at them, even if
that teacher never logs in. This phase creates **login accounts** (IAM `user`
+ `user_tenant_role`). They are linked by convention (email / an optional
`user_id` on the teacher profile), not merged.

```
academic-ops.teacher (profile, NIP)        iam.user (account, email+password)
        │                                         │
        └──── same person, linked by email ───────┘
              (grading authz uses teacher_id from teaching_assignment,
               session identity uses user_id+role from the JWT)
```

The grading service authorizes by the **teaching_assignment tuple**
(`teacher_id`), while the *session* carries `user_id` + `role`. The report-card
workflow phase resolves "is this logged-in user the homeroom teacher / a
subject teacher for this class" by joining the account to the profile. We keep
that join logic in the consuming phase; this phase just makes both sides exist.

### 3. One-time, time-bound invitations

`tenant_invitation` stores only a **hash** of the token (never the raw token).
Acceptance is single-use: redeeming flips `status` to `accepted` in the same
transaction that creates the user, so a replayed token finds a non-pending
invitation and is rejected. Tokens expire at `expires_at`; expired tokens
return `INVITATION_EXPIRED`. Revoking sets `status='revoked'`.

```
invite ─▶ pending (hash stored, expires_at set)
              │ accept (token matches, not expired, status=pending)
              ▼  ── single tx ──▶ create user + membership, status=accepted
              │ replay / expired / revoked ─▶ error
```

### 4. Role changes propagate on the next access token

Access tokens are short-lived (15 min) and carry `role`. We do **not** force
logout on role change; instead the next refresh-token rotation reissues the
access token with the new role. Optionally we bump a per-membership
`token_version` so a security-sensitive change can be made to take effect
faster by invalidating current access tokens — included as a hook but the MVP
relies on natural expiry + refresh.

### 5. Email delivery is deferred

The notification service does not exist yet. Inviting produces the token, the
`tenant_user.invited` event, and returns/logs the activation link for the
admin to share manually. When notification ships, it consumes
`tenant_user.invited` to send the email — no change to this phase's contract.

## Data model (migration `V3` + `V4`)

| Change | Detail |
|--------|--------|
| `V3__seed_principal_role.sql` | insert `principal` role with stable code |
| `V4__tenant_invitation.sql` | `tenant_invitation(invitation_id, tenant_id, email, role_id, token_hash, status, expires_at, invited_by, accepted_at)`; index `(tenant_id, status)`, unique `(tenant_id, email) WHERE status='pending'` |

## Alternatives considered

- **Reuse the registration saga for every user** — rejected: registration is a
  Billing-owned tenant-creation saga; per-user invitation is an IAM concern and
  far simpler.
- **Store raw invitation tokens** — rejected: security; we store only hashes.
- **Force logout on role change** — rejected: poor UX; short token TTL +
  refresh rotation is sufficient and matches the roadmap exit criterion.

## Risks

- **Unlinked teacher profile vs account** — a teacher account whose email does
  not match any `teacher` profile cannot be resolved for grading authz. The
  report-card phase surfaces this as a setup error; documented in its design.
- **No email yet** — admins must hand the activation link to invitees until
  notification ships. Acceptable, explicitly deferred.
