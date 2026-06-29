## Why

The report card workflow is a multi-actor approval chain: a **subject
teacher** records grades, a **homeroom teacher** reviews, and a **principal**
approves before publication
(`09_states/AkademiQ_State_Report_Card_Lifecycle.md`). Today the only real
account a tenant has is the admin created during registration; there is no way
to invite the teachers, homeroom teachers, or principal who drive that chain,
and **there is no `principal` role seeded at all** — IAM seeds
`super_admin, tenant_admin, teacher, homeroom_teacher, student, parent`.

This change delivers tenant user management as an **extension of
`iam-service`**: invite, activate, and manage tenant-scoped accounts and their
roles, and it adds the missing `principal` role so the approval chain has a
real approver. This is **Phase 4 — Tenant User Management** in
`docs/internal/13_engineering_standards/16_implementation_phases.md`.

It depends only on phase 1 (IAM/Billing), so it can be built in parallel with
Academic Config/Ops. It must land before the report-card workflow phase so the
approval actors exist as real users rather than seeds.

## What Changes

### Backend — `iam-service` extension

- New table `tenant_invitation` (`invitation_id`, `tenant_id`, `email`,
  `role_id`, `token_hash`, `status`, `expires_at`, `invited_by`,
  `accepted_at`). One-time-use, time-bound tokens.
- New migration `V3__seed_principal_role.sql` inserting the `principal` role
  (`School principal / final academic approver`) with a stable `role.code`,
  and the matching `ROLE_PRINCIPAL` constant in `common-auth`.
- Endpoints under `/api/v1/iam`:
  - `POST /tenants/me/invitations` (tenant admin) — invite an email with a
    role (`teacher`, `homeroom_teacher`, `principal`, `parent`, `student`).
    Emits `tenant_user.invited`.
  - `GET /tenants/me/invitations` — list pending/accepted invitations.
  - `POST /invitations/accept` (public) — redeem `{ token, password,
    full_name }`; creates the user + `user_tenant_role`, marks the invitation
    accepted, returns access + refresh tokens. Emits `tenant_user.activated`.
  - `GET /tenants/me/users` — list tenant users with roles.
  - `PATCH /tenants/me/users/{id}/role` — change a user's role in the tenant.
    Emits `tenant_user.role_changed`.
  - `POST /tenants/me/users/{id}/disable` / `.../enable` — deactivate /
    reactivate an account. Emits `tenant_user.disabled`.
  - `POST /tenants/me/users/{id}/reset-password` — admin-initiated reset.
- Role changes take effect on the **next access token** (refresh rotation
  reissues with the new role); no forced logout.
- Invitation tokens are single-use and expire (configurable TTL); expired or
  reused tokens return a clear error.

### Web — `/settings/users`

- `/settings/users`: user list with roles, invite dialog (email + role
  select), pending-invitation list with resend/revoke, role change control,
  disable/enable toggle. An `/invitations/accept` public page where an invitee
  sets a password and lands authenticated on the dashboard.
- shadcn/ui + TanStack Query + RHF/Zod + two-tier loading per
  `apps/web/CONVENTIONS.md`.

### Tests & docs

- Unit (token hashing, single-use + expiry logic, role-change → token claim),
  integration (testcontainer), e2e: admin invites teacher/homeroom/principal →
  invitee accepts → logs in with correct role → admin changes role → new token
  reflects it → admin disables account → login blocked. Playwright on the web
  flow. Event contracts documented; roadmap Phase 4 status flipped.

## Capabilities

### New Capabilities

- `tenant-user-management`: defines tenant-scoped invitation issuance and
  one-time redemption, the `principal` role addition, role management with
  next-token propagation, account disable/enable, admin password reset, and the
  `tenant_user.*` events.

### Modified Capabilities

- `iam-service`: the seeded role set is extended with `principal`, and the
  service gains invitation/user-management endpoints alongside the existing
  auth endpoints.

## Impact

- **New code**: IAM migrations (`tenant_invitation`, principal role seed),
  invitation/user-management commands+queries+handlers; web `/settings/users`
  and `/invitations/accept`.
- **Depends on**: phase 1 only. **Blocks**: nothing hard, but
  `mvp-report-card-workflow` SHOULD land after this so real principal/teacher
  accounts drive the approval demo (seeds can stand in if it lands first).
- **Out of scope**: SSO / external IdP, email delivery (the invite produces
  the token + event; actual email send waits for the notification service —
  for now the activation link is returned to the admin / logged), bulk user
  import (covered by the academic-ops Excel import for students/teachers as
  *profiles*, distinct from login accounts).
