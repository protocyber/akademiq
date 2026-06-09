## 1. Roadmap & schema prep

- [x] 1.1 Flip Phase 4 in `16_implementation_phases.md` from ⏳ to 🚧, delivering change `mvp-tenant-user-management`
- [x] 1.2 `V3__seed_principal_role.sql`: insert `principal` role with a stable `role.code`
- [x] 1.3 Add `ROLE_PRINCIPAL` constant in `common-auth`; assert codes match the seed
- [x] 1.4 `V4__tenant_invitation.sql`: `tenant_invitation` table + index `(tenant_id, status)` + partial unique `(tenant_id, email) WHERE status='pending'`
- [x] 1.5 Add `INVITATION_TOKEN_TTL` config to `iam-service` config + `.env.example`

## 2. Domain & repos (CQRS-separated)

- [x] 2.1 Domain types: `TenantInvitation` (+ status enum), extend role enum with `principal`
- [x] 2.2 Commands: `InviteTenantUser`, `AcceptInvitation`, `ChangeUserRole`, `DisableUser`, `EnableUser`, `AdminResetPassword`, `RevokeInvitation`
- [x] 2.3 Queries: `ListInvitations`, `ListTenantUsers`
- [x] 2.4 `InvitationRepo` trait + SQLx impl; token stored as hash only

## 3. HTTP layer (`/api/v1/iam`)

- [x] 3.1 `POST /tenants/me/invitations` (tenant admin) — issue invitation, return activation link, emit `tenant_user.invited`
- [x] 3.2 `GET /tenants/me/invitations` — list
- [x] 3.3 `POST /invitations/accept` (public) — redeem token, create user + membership, return tokens, emit `tenant_user.activated`
- [x] 3.4 `GET /tenants/me/users` — list tenant users with roles
- [x] 3.5 `PATCH /tenants/me/users/{id}/role` — change role, emit `tenant_user.role_changed`
- [x] 3.6 `POST /tenants/me/users/{id}/disable` + `/enable` — emit `tenant_user.disabled`
- [x] 3.7 `POST /tenants/me/users/{id}/reset-password`
- [x] 3.8 Authorize all `/tenants/me/*` user-management routes to `tenant_admin` only

## 4. Invitation semantics

- [x] 4.1 Single-use: acceptance flips status to `accepted` in the same tx as user creation; replayed token rejected
- [x] 4.2 Expiry: tokens past `expires_at` return `INVITATION_EXPIRED`
- [x] 4.3 Revoke: `status='revoked'` blocks acceptance
- [x] 4.4 Role change reflected in the next access token via refresh rotation (no forced logout)

## 5. Integration tests

- [x] 5.1 Invite → accept → new user can log in with the assigned role
- [x] 5.2 Reused token rejected; expired token rejected; revoked token rejected
- [x] 5.3 Role change → old access token still old role until expiry → refresh issues token with new role
- [x] 5.4 Disabled account cannot log in; re-enabled can
- [x] 5.5 Non-admin cannot call user-management endpoints (403)
- [x] 5.6 `principal` role is seeded and assignable
- [x] 5.7 `tenant_user.invited`, `.activated`, `.role_changed`, `.disabled` land on RabbitMQ

## 6. Web — `/settings/users` + accept page

- [x] 6.1 Zod schemas: invite, accept-invitation, role-change
- [x] 6.2 TanStack hooks for invitations + users
- [x] 6.3 `/settings/users` — user list (skeleton), invite dialog, pending list with resend/revoke
- [x] 6.4 Role change control + disable/enable toggle (spinner)
- [x] 6.5 `/invitations/accept` public page — set password + full name, land authenticated

## 7. Docs & wrap-up

- [x] 7.1 Event contracts: `tenant_user.invited`, `.activated`, `.role_changed`, `.disabled`
- [x] 7.2 Extend `apis/iam-service-api.md` with the new endpoints
- [x] 7.3 e2e: admin invites teacher + homeroom + principal → each accepts → logs in with correct role → role change reflected → disable blocks login
- [x] 7.4 Playwright: invite + accept + role change flow
- [x] 7.5 `openspec validate mvp-tenant-user-management --strict` green
