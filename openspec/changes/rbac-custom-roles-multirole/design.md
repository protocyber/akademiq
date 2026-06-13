# Design — RBAC: custom roles, multi-role, permission-based authorization

## Context

The codebase advertises RBAC (a `permission` table, a `role_permission` join,
seven seeded roles) but implements **role-name authorization**: every gate is a
string compare against a `ROLE_*` constant, the permission tables are never
populated or read, and both the JWT (`role: String`) and the membership table
(`UNIQUE(user_id, tenant_id)`) hard-limit a user to one role per tenant.

This design activates the permission layer, opens the role catalog to tenants,
and lifts the one-role limit — while keeping the JWT stateless and the
report-card workflow (which depends on role *identity*) intact.

## Goals / Non-goals

**Goals**
- Permissions are the unit of authorization; roles are named permission bundles.
- Tenant admins define custom roles from a fixed permission palette.
- A user holds ≥1 role per tenant; effective permission = union.
- The access token answers both "what may you do?" (perms) and "which role are
  you acting as?" (roles) without a per-request DB lookup.

**Non-goals (v1)**
- Direct permissions on a user (decided out — see Decision 1).
- Object-scoped permissions like `grade.edit:class-7a` (Decision 4).
- Cross-tenant / platform-level custom roles (built-ins stay global; custom
  roles are tenant-scoped only).
- Time-boxed break-glass exceptions (possible phase 2).

## Decision 1 — Permissions attach to roles only, never to users

**Decision:** A permission can be granted to a role. It cannot be granted to a
user. A user's authority is exactly the union of their roles' permissions.

**Why (the proposal was challenged and rejected):**

- **Auditability is the whole point.** "Who can approve report cards?" must be
  answerable by scanning the role catalog — O(roles). The moment a permission can
  live on a user, every audit becomes O(users) and is never truly complete.
- **Permission creep is empirical.** Per-user grants get added ("just for now")
  and never revoked; they are where stale privilege accumulates. Roles get
  reviewed; user exceptions don't.
- **Schools are positions, not people.** Every bespoke authority in a school is a
  *named position* (Wakil Kepala, Bendahara, Plt. Kepala Sekolah) — i.e. a role,
  even with one holder. The canonical reason for direct grants ("a unique set for
  one person") is fully served by a **single-member custom role**, which is free.
- **In a JWT model it buys nothing.** Both paths are computed into the token at
  mint time; a direct grant adds a second authority path to merge/display/audit
  forever and saves zero request-time work.

**The real need underneath** — temporary cover, break-glass — wants the opposite
properties of a silent permanent grant (visible, expiring, reasoned, audited).
If it materializes, model it as a distinct **exception** concept in phase 2, not
as "a permission on a user."

## Decision 2 — Token carries roles[] AND perms[]

**Decision:** Access-token claims become
`{ sub, tenant_id, roles: [code…], perms: [code…], typ, iat, exp, jti }`.

| Option | Token | Guard check | Workflow identity | Stateless? |
|---|---|---|---|---|
| A roles only | `roles:[]` | resolve perms per request | ✓ from roles | ✗ needs map/DB |
| **B roles+perms** | `roles:[]` `perms:[]` | read `perms` | ✓ from roles | ✓ |
| C perms only | `perms:[]` | read `perms` | ✗ **lost** | ✓ |

**Why B:** `grading-service/src/commands.rs:370` maps `role → ReportCardRole`
(SubjectTeacher / HomeroomTeacher / Principal) to decide *which* step of the
report-card state machine the caller occupies. That is role *identity*, not a
permission. Option C discards it; Option A makes every guard re-resolve perms
(per-request DB hit or a replicated role→perm map in five services). B is the
only self-contained, stateless choice. Token-size cost is bounded because the
permission vocabulary is platform-capped and small.

**Only built-in role codes carry workflow meaning.** Custom role codes appear in
`roles[]` for display/audit but never drive a state machine — services match
workflow steps against `ROLE_*` constants only.

## Decision 3 — Built-in roles are immutable templates

**Decision:** The seven built-in roles (`tenant_id = NULL`) are read-only. To
customize, a tenant **clones** a built-in into a tenant-scoped role and edits the
clone, or creates a new role. Tenant role codes may not collide with built-in
codes.

**Why:** Built-in codes are a contract — `common_auth::ROLE_*`, the grading
workflow, and seed data all assume `"principal"` means the principal. If a tenant
could redefine `principal`'s permissions, that contract breaks silently. Cloning
gives full flexibility (the clone can drop or add any permission) without
mutating the shared vocabulary. Cost: a tenant that wants "teachers but without
grade.record" makes a custom role rather than toggling a built-in — acceptable, and
clearer in an audit.

## Decision 4 — Action-level permissions; object scope stays in services

**Decision:** Permission codes are action-level (`grade.record`,
`report.transition`).
*Which* class/student a teacher may touch remains a **row-level check in the
owning service**, exactly as today.

**Why:** Scoped codes (`grade.record:own-class`) multiply the vocabulary, push
business scope into the auth token, and duplicate logic services already perform
against their own tables. RBAC answers "may this actor perform this action at
all"; the service answers "on this specific object." Clean seam, smaller token.

## Decision 5 — No privilege escalation on role authoring

**Decision:** When creating or editing a role, an admin may only grant
permissions the admin **currently holds**. Enforced server-side against the
caller's effective `perms`.

**Why:** Without this, `role.manage` becomes god-mode — an admin mints a role
with `billing.view` they lack, assigns it to themselves, escalates. The check
makes `role.manage` "delegate a subset of my own authority," which is the safe
RBAC invariant.

## Gate audit (source of the permission vocabulary)

Authorization in the codebase today runs at **three independent layers**. RBAC
replaces only Layer 1. Conflating the other two into permissions would bloat the
token and leak business logic into auth — so they stay where they are.

```
Layer 1  ROLE-NAME      "are you an admin?"            → becomes permissions
Layer 2  ROW-SCOPE      "are you assigned to this?"    → stays in service (row-level)
Layer 3  ENTITLEMENT    "is the tenant subscribed?"    → not RBAC at all
```

| Gate | Location | Check | Layer | Maps to |
|---|---|---|---|---|
| IAM admin gates | `iam/http.rs` `require_tenant_admin` | `role == tenant_admin` | 1 | `user.invite`, `user.disable`, `user.role.assign`, `role.manage` |
| academic-config write | `academic-config/http.rs:352` | `super_admin \| tenant_admin` | 1 | `academic.config.write` |
| generate report cards | `grading/commands.rs:185` | `homeroom_teacher \| tenant_admin` | 1+2 | `report.generate` (+ keeps homeroom scope check) |
| transition report card | `grading/commands.rs:273` `report_role` | role identity → state machine | 1 (identity) | `report.transition` + **built-in role in `roles[]`** |
| record/update grade | `grading/commands.rs:100` `can_record_grade` | teacher assigned to student+subject+year | **2 only** | `grade.record` (entry) + row-scope stays in service |
| subscription active | `academic-config:46`, `academic-ops:474`, `billing:191` | `is_active(tenant)` | **3** | unchanged (not a permission) |
| module entitlement | `*/http.rs` `RequiredFeature<FeatureCode>` | tenant module enabled | **3** | unchanged (not a permission) |
| **module toggle** | `billing/http.rs:86` `toggle` | **NONE — no role check** | — | **`billing.manage` (closes a real gap)** |

Three audit findings shaped the final design:

- **The token must carry role identity.** `transition_card` (`report_role`) needs
  to know you are *homeroom_teacher* vs *principal* to pick the approval step.
  A perms-only token would break report cards — this is the empirical proof
  behind Decision 2.
- **Two layers must NOT become permissions.** Row-scope ("assigned to this
  student") and entitlement ("subscription active") are different axes; forcing
  them into permission codes explodes the vocabulary and the token. This is the
  evidence behind Decision 4.
- **A live authorization gap exists.** Module toggle has no role check; any
  tenant member (student, parent) can toggle paid modules. Not part of RBAC, but
  the rewrite gives it its first gate (`billing.manage`).

```sql
-- permission: platform-owned vocabulary (seeded, not tenant-editable)
permission(permission_id, code UNIQUE, description)

-- role: built-in (tenant_id NULL, immutable) + tenant-defined
role(role_id, tenant_id NULL, code, name, is_builtin, created_at)
  UNIQUE(tenant_id, code)            -- built-ins live under the NULL tenant
  -- tenant code may not equal any built-in code (app-enforced)

role_permission(role_id, permission_id)   -- seeded for built-ins; admin-edited for custom

user_tenant_role(id, user_id, tenant_id, role_id, created_at)
  UNIQUE(user_id, tenant_id, role_id)      -- was UNIQUE(user_id, tenant_id)
```

**Effective permission resolution** (at `/enter` and `/refresh`):

```
roles  = SELECT r.code  FROM user_tenant_role utr
         JOIN role r ON r.role_id = utr.role_id
         WHERE utr.user_id = $u AND utr.tenant_id = $t
perms  = SELECT DISTINCT p.code FROM user_tenant_role utr
         JOIN role_permission rp ON rp.role_id = utr.role_id
         JOIN permission p ON p.permission_id = rp.permission_id
         WHERE utr.user_id = $u AND utr.tenant_id = $t
-- both baked into the access token; nothing resolved per request
```

## Migration & cutover

1. **Seed** `permission` and built-in `role_permission` (encodes today's
   behavior). No runtime change yet.
2. **Schema**: `role + tenant_id, is_builtin`; `user_tenant_role` uniqueness
   swap (tighter key already satisfied by existing rows — safe).
3. **`common-auth` dual-read**: extractor accepts BOTH `{role}` and
   `{roles,perms}`. A legacy `role` maps to `roles:[role]` and perms resolved
   from that single built-in role's seed. New code reads `perms`.
4. **IAM mints new shape** at `/enter` and `/refresh`.
5. **Rewrite guards** service-by-service from role compares to
   `require_permission`, verifying the invariant *same decision, expressed as a
   permission*.
6. **Drop the shim** one release later; remove `role: String`. Access tokens are
   15-min, so no forced logout is needed — natural expiry completes cutover.

**Invariant test:** for every existing role-name gate, a user holding the
corresponding built-in role is allowed and a user lacking it is denied — before
and after the rewrite. This is the safety net that makes the refactor mechanical.

## Risks

- **Claims struct touches all five services.** Mitigated by dual-read + natural
  token expiry; no big-bang.
- **Token growth** if a future role accrues many permissions. Mitigated by a
  capped vocabulary; if it ever bites, fall back to Decision 2 Option A for that
  deployment without changing the data model.
- **Admin lockout / last-admin demotion.** Multi-role makes it easier to strip
  the wrong role. Add a guard: a tenant MUST retain ≥1 user holding
  `user.role.assign` (the "can't remove the last admin" rule).
- **Custom-role sprawl.** Tenants may create many near-duplicate roles. Acceptable
  v1; surface usage counts in the role catalog UI to discourage it.
