# Tasks — RBAC: custom roles, multi-role, permissions

## 1. Permission vocabulary & seeds (`iam-service`)

- [x] 1.1 Migration: seed `permission` with the audited v1 vocabulary — `user.invite`, `user.disable`, `user.role.assign`, `role.manage`, `billing.view`, `billing.manage`, `academic.config.write`, `report.generate`, `report.transition`, `grade.record` (see design.md "Gate audit"; list is exhaustive over current Layer-1 gates)
- [x] 1.2 Migration: seed `role_permission` for each of the 7 built-in roles so the union reproduces today's behavior (audit each existing role-name gate to derive the mapping)
- [x] 1.3 Add `role.tenant_id UUID NULL` + `role.is_builtin BOOLEAN`; built-ins are `tenant_id = NULL`; change uniqueness to `UNIQUE(tenant_id, code)`
- [x] 1.4 Change `user_tenant_role` to `UNIQUE(user_id, tenant_id, role_id)` (drop `UNIQUE(user_id, tenant_id)`); verify existing rows satisfy the new key

## 2. Token shape & dual-read (`common-auth`)

- [x] 2.1 Change `Claims`: replace `role: String` with `roles: Vec<String>` + `perms: Vec<String>` (keep `sub, tenant_id, typ, iat, exp, jti`)
- [x] 2.2 Dual-read in the extractor: accept legacy `{role}` tokens for one release — map to `roles:[role]` and resolve `perms` from that built-in role's seed
- [x] 2.3 Add `require_permission(&auth, code)` and `has_permission`; keep the report-card `role → ReportCardRole` mapping reading `roles` (built-in codes only)
- [x] 2.4 Update `JwtEncoder::issue` to take `roles` + `perms`; add unit tests for new shape and legacy acceptance

## 3. Effective-permission resolution (`iam-service`)

- [x] 3.1 Repo query: all role codes for `(user, tenant)` and the deduped permission union (the two SELECTs in design.md)
- [x] 3.2 `enter_tenant` and `refresh` mint tokens with resolved `roles` + `perms` (replace the single-role `resolve_membership` path)
- [x] 3.3 `get_me` / `/my-tenants`: return roles as a list per membership

## 4. Custom-role management (`iam-service`)

- [x] 4.1 `GET /tenants/me/permissions` — the assignable palette (gated on `role.manage`)
- [x] 4.2 `GET/POST /tenants/me/roles`, `GET/PATCH/DELETE /tenants/me/roles/{id}` — CRUD for tenant-scoped roles
- [x] 4.3 Enforce: built-in roles immutable; custom `code` ≠ any built-in code; `UNIQUE(tenant_id, code)`
- [x] 4.4 No-escalation check: reject any permission the calling admin lacks (`403 PRIVILEGE_ESCALATION`)
- [x] 4.5 Block delete of a role still assigned to users (or soft-disable); return `409`

## 5. Multi-role assignment (`iam-service`, `tenant-user-management`)

- [x] 5.1 Replace `PATCH /tenants/me/users/{id}/role` with `POST`/`DELETE /tenants/me/users/{id}/roles/{roleId}` (gated on `user.role.assign`)
- [x] 5.2 Last-admin guard: refuse a removal that leaves zero holders of `user.role.assign` (`409 LAST_ADMIN`)
- [x] 5.3 Invitations accept ≥1 role; acceptance grants all invited roles in one transaction
- [x] 5.4 `list_tenant_users` returns each user's role set

## 6. Rewrite service guards (all services)

- [x] 6.1 `iam-service/http.rs`: `require_tenant_admin` → `require_permission` per route
- [x] 6.2 `academic-config-service`: replace `ROLE_SUPER_ADMIN | ROLE_TENANT_ADMIN` gate (`http.rs:352`) with `academic.config.write`
- [x] 6.3 `grading-service`: split authority (permission gate) from workflow identity (built-in role) — `commands.rs:185,371`
- [x] 6.4 `academic-ops-service`, `billing-service`: audit and convert any role-name gates
- [x] 6.5 Invariant test per converted gate: holder of the matching built-in role allowed, non-holder denied (before == after)

## 7. Web — role catalog (`web-user-role-management`)

- [x] 7.1 `settings/roles` page: list built-in (read-only) + custom (editable) roles with their permissions
- [x] 7.2 Permission-matrix editor sourced from `GET /tenants/me/permissions`; clone-from-built-in flow
- [x] 7.3 Surface `PRIVILEGE_ESCALATION` and only offer permissions the admin holds
- [x] 7.4 Query/mutation hooks for role CRUD; route guarded on `role.manage`

## 8. Web — multi-role users (`web-user-role-management`)

- [x] 8.1 `settings/users`: render role chips per user; add/remove against the catalog (replace single Select at `page.tsx:338`)
- [x] 8.2 Multi-role invite dialog; update `tenant-user-management` Zod schemas (currently single `z.enum`)
- [x] 8.3 Gate UI affordances on `perms` from the token (not a role name); handle `LAST_ADMIN`

## 9. Migration cutover & docs

- [x] 9.1 Stage deploy: seeds → schema → dual-read shipped → IAM mints new shape → guards converted
- [ ] 9.2 Remove the `role`-claim compatibility shim one release later; delete `role: String`
- [x] 9.3 Update IAM domain model, ERD, component diagram, API contract, and engineering-standards authorization section
- [x] 9.4 Confirm the 5 Open Decisions in `proposal.md` before build starts
