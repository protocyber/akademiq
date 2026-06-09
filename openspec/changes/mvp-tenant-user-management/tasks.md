## 1. Roadmap & schema prep

- [ ] 1.1 Flip Phase 4 in `16_implementation_phases.md` from ⏳ to 🚧, delivering change `mvp-tenant-user-management`
- [ ] 1.2 `V3__seed_principal_role.sql`: insert `principal` role with a stable `role.code`
- [ ] 1.3 Add `ROLE_PRINCIPAL` constant in `common-auth`; assert codes match the seed
- [ ] 1.4 `V4__tenant_invitation.sql`: `tenant_invitation` table + index `(tenant_id, status)` + partial unique `(tenant_id, email) WHERE status='pending'`
- [ ] 1.5 Add `INVITATION_TOKEN_TTL` config to `iam-service` config + `.env.example`

## 2. Domain & repos (CQRS-separated)

- [ ] 2.1 Domain types: `TenantInvitation` (+ status enum), extend role enum with `principal`
- [ ] 2.2 Commands: `InviteTenantUser`, `AcceptInvitation`, `ChangeUserRole`, `DisableUser`, `EnableUser`, `AdminResetPassword`, `RevokeInvitation`
- [ ] 2.3 Queries: `ListInvitations`, `ListTenantUsers`
- [ ] 2.4 `InvitationRepo` trait + SQLx impl; token stored as hash only

## 3. HTTP layer (`/api/v1/iam`)

- [ ] 3.1 `POST /tenants/me/invitations` (tenant admin) — issue invitation, return activation link, emit `tenant_user.invited`
- [ ] 3.2 `GET /tenants/me/invitations` — list
- [ ] 3.3 `POST /invitations/accept` (public) — redeem token, create user + membership, return tokens, emit `tenant_user.activated`
- [ ] 3.4 `GET /tenants/me/users` — list tenant users with roles
- [ ] 3.5 `PATCH /tenants/me/users/{id}/role` — change role, emit `tenant_user.role_changed`
- [ ] 3.6 `POST /tenants/me/users/{id}/disable` + `/enable` — emit `tenant_user.disabled`
- [ ] 3.7 `POST /tenants/me/users/{id}/reset-password`
- [ ] 3.8 Authorize all `/tenants/me/*` user-management routes to `tenant_admin` only

## 4. Invitation semantics

- [ ] 4.1 Single-use: acceptance flips status to `accepted` in the same tx as user creation; replayed token rejected
- [ ] 4.2 Expiry: tokens past `expires_at` return `INVITATION_EXPIRED`
- [ ] 4.3 Revoke: `status='revoked'` blocks acceptance
- [ ] 4.4 Role change reflected in the next access token via refresh rotation (no forced logout)

## 5. Integration tests

- [ ] 5.1 Invite → accept → new user can log in with the assigned role
- [ ] 5.2 Reused token rejected; expired token rejected; revoked token rejected
- [ ] 5.3 Role change → old access token still old role until expiry → refresh issues token with new role
- [ ] 5.4 Disabled account cannot log in; re-enabled can
- [ ] 5.5 Non-admin cannot call user-management endpoints (403)
- [ ] 5.6 `principal` role is seeded and assignable
- [ ] 5.7 `tenant_user.invited`, `.activated`, `.role_changed`, `.disabled` land on RabbitMQ

## 6. Web — `/settings/users` + accept page

- [ ] 6.1 Zod schemas: invite, accept-invitation, role-change
- [ ] 6.2 TanStack hooks for invitations + users
- [ ] 6.3 `/settings/users` — user list (skeleton), invite dialog, pending list with resend/revoke
- [ ] 6.4 Role change control + disable/enable toggle (spinner)
- [ ] 6.5 `/invitations/accept` public page — set password + full name, land authenticated

## 7. Docs & wrap-up

- [ ] 7.1 Event contracts: `tenant_user.invited`, `.activated`, `.role_changed`, `.disabled`
- [ ] 7.2 Extend `apis/iam-service-api.md` with the new endpoints
- [ ] 7.3 e2e: admin invites teacher + homeroom + principal → each accepts → logs in with correct role → role change reflected → disable blocks login
- [ ] 7.4 Playwright: invite + accept + role change flow
- [ ] 7.5 `openspec validate mvp-tenant-user-management --strict` green
