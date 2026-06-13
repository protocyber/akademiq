## Why

AcademiQ today has the *vocabulary* of RBAC but not the *mechanism*. Three gaps:

1. **Permissions are dead schema.** `permission` and `role_permission` were
   created in `V1__init.sql` and then never seeded and never queried. Every
   authorization decision in every service is a hardcoded **role-name string
   compare** — `claims.role == "tenant_admin"` (`iam-service/src/http.rs`),
   `ROLE_SUPER_ADMIN | ROLE_TENANT_ADMIN` (`academic-config-service`),
   `ROLE_HOMEROOM_TEACHER | ROLE_TENANT_ADMIN` (`grading-service`). There is no
   permission layer; there is a fixed list of seven role names baked into code.

2. **One user, one role per tenant.** `user_tenant_role` carries
   `UNIQUE(user_id, tenant_id)` and the access JWT carries a single
   `role: String`. A teacher who is also a homeroom teacher cannot hold both —
   the data model forbids it. Real schools assign overlapping positions
   constantly (a teacher who is also Wali Kelas and sits on the curriculum team).

3. **The role catalog is closed.** The seven roles are seeded rows whose codes
   must match `common_auth::ROLE_*` constants. A tenant cannot express positions
   the platform didn't predefine — *Wakil Kepala Kurikulum*, *Guru BK*,
   *Bendahara*, *Operator Dapodik*, *Plt. Kepala Sekolah* — all of which are real,
   named positions in Indonesian schools.

This change turns the dormant permission tables into the real authorization
substrate, lets tenant admins **define their own roles** from a permission
palette, and lets a user **hold several roles** in one tenant with permissions
**unioned**.

```
  BEFORE                              AFTER
  ──────                              ─────
  guard: role == "tenant_admin"       guard: perms ∋ "user.invite"
  roles: 7 fixed code constants       roles: 7 built-in + tenant-defined
  membership: 1 role / tenant         membership: N roles / tenant (∪ perms)
  token: { role: String }             token: { roles:[…], perms:[…] }
  permission tables: unused           permission tables: the source of truth
```

## What Changes

### Permissions become the unit of authorization (`iam-service`, `common-auth`)

- **NEW seeded permission vocabulary.** A migration seeds `permission` with a
  fixed, platform-owned set of action codes **derived from an audit of every
  current role-name gate** (see `design.md` "Gate audit"). The v1 set is:
  `user.invite`, `user.disable`, `user.role.assign`, `role.manage`,
  `billing.view`, `billing.manage`, `academic.config.write`, `report.generate`,
  `report.transition`, `grade.record`. The code list is the platform's API
  surface for authorization and is **not** tenant-editable.
  - `report.transition` is intentionally a **single** permission, not
    `report.sign`/`report.approve`: the audit showed report-card transitions are
    driven by a **state machine keyed on built-in role identity**
    (`grading-service/src/commands.rs:273`, `report_role`), not by graded
    permission levels. The permission grants entry to the workflow; *which* step
    you may perform comes from your built-in role in `roles[]`.
  - `billing.manage` closes a current gap: `PATCH /billing/tenants/me/modules`
    (`billing-service/src/http.rs:86`, `toggle`) has **no role check today** — any
    tenant member can toggle paid modules. The rewrite gates it on
    `billing.manage`.
- **NEW `role_permission` seed for built-in roles.** Each of the seven built-in
  roles is mapped to its permission set, encoding today's implicit behavior
  explicitly (e.g. `tenant_admin → {user.invite, user.disable,
  user.role.assign, role.manage, …}`).
- **Guards check permissions, not role names.** `common-auth` gains
  `require_permission(&auth, "user.invite")`. Existing role-name guards across
  all services are rewritten to permission checks. **Built-in role *identity* is
  still carried** (see token shape) because the report-card workflow keys off
  *which* role you act as, not merely a permission.

### Custom roles per tenant (`iam-service`, `tenant-user-management`)

- **MODIFIED `role` table**: add `tenant_id UUID NULL`. `NULL` = built-in
  (global, immutable template). Non-null = a tenant-defined role. Uniqueness
  becomes `UNIQUE(tenant_id, code)` with built-ins under the `NULL` tenant.
  Tenant role codes **may not collide** with built-in codes.
- **Built-in roles are immutable.** A tenant customizes by **cloning** a built-in
  into a tenant role and editing the clone's permissions, or by creating a fresh
  role. This keeps `grading-service`'s `role → ReportCardRole` mapping
  (`commands.rs:370`) stable — only built-in role codes ever drive workflow.
- **NEW role-management endpoints** (permission `role.manage`):
  `GET/POST /tenants/me/roles`, `GET/PATCH/DELETE /tenants/me/roles/{id}`,
  `GET /tenants/me/permissions` (the assignable palette).
- **No privilege escalation.** An admin MUST NOT grant a role any permission the
  admin does not currently hold. A role in use MUST NOT be hard-deleted (block or
  soft-disable).

### Multi-role membership (`iam-service`)

- **MODIFIED `user_tenant_role`**: drop `UNIQUE(user_id, tenant_id)`, add
  `UNIQUE(user_id, tenant_id, role_id)`. A user may hold several roles in one
  tenant.
- **Effective permissions = union.** Entering a tenant (or refreshing) resolves
  **all** of the user's roles in that tenant and unions their permission sets.
- **MODIFIED role assignment**: `PATCH /tenants/me/users/{id}/role` becomes
  add/remove against a set (e.g. `POST`/`DELETE
  /tenants/me/users/{id}/roles/{roleId}`), replacing single-role swap.

### Token shape: roles **and** permissions (`common-auth`)

- **MODIFIED access-token claims**: `role: String` → `roles: Vec<String>`
  (the codes the user holds in this tenant, for workflow identity + display) and
  `perms: Vec<String>` (the deduplicated union, for guards). `typ:"access"`,
  `tenant_id`, `sub`, `jti`, `iat`, `exp` unchanged.
- **Rationale**: `grading-service` maps role *identity* to report-card workflow
  steps; a perms-only token would lose that. Carrying both keeps the JWT
  **stateless** — no service makes a per-request DB call to resolve authority.
- This is the **real blast radius**: the claims struct lives in `common-auth`,
  which **all five services** decode through. The migration is staged (dual-read,
  below) so a deploy doesn't hard-break in-flight tokens.

### Direct-permission-on-user is explicitly **out** (decided)

Permissions attach to **roles only**. A one-person authority is modeled as a
single-member custom role (free, already supported). This keeps "who can do X?"
answerable by reading the role catalog — O(roles), not O(users). Time-boxed,
audited **exceptions** (break-glass) are a possible **phase 2** with their own
table (expiry + reason + audit), not a permission silently living on a user row.

## Capabilities

### Modified Capabilities

- `iam-service`: activates the permission layer; adds tenant-custom roles,
  multi-role membership, role-management endpoints, union-based effective
  permissions, and the `roles[]/perms[]` token shape.
- `tenant-user-management`: assignment moves from single-role swap to a role
  *set* per user; invitations may carry one or more roles.
- `web-user-role-management` *(new capability)*: a role catalog + permission-matrix
  UI, and a user view that shows/edits multiple role chips per user.

## Impact

- **Token claim change is the central risk.** `Claims.role: String` →
  `roles/perms` is decoded by every service's extractor. Mitigation: **dual-read**
  — extractors accept both old (`role`) and new (`roles`/`perms`) claims for one
  release; IAM mints the new shape; old access tokens expire within 15 min;
  refresh tokens already rotate. After one release the compatibility shim is
  removed.
- **Migrations**: seed `permission` + built-in `role_permission`; `role +
  tenant_id`; `user_tenant_role` uniqueness change. The uniqueness change is
  backward-compatible (existing rows already satisfy the tighter key).
- **Every service's authz call sites change** from role-name compares to
  `require_permission`. Behavior is preserved by seeding built-in roles to today's
  effective permissions; this is a refactor with a verifiable invariant
  ("same decisions, expressed as permissions").
- **Affected code**: `common-auth` (claims, extractor, `require_permission`);
  IAM `commands.rs`/`queries.rs`/`http.rs`/`repo.rs`/`domain.rs` + migrations;
  authz call sites in `academic-config-service`, `academic-ops-service`,
  `grading-service`, `billing-service`; web (`settings/users`, new
  `settings/roles`, schemas, query/mutation hooks).
- **Docs**: IAM domain model (permission/role wiring, multi-role), ERD,
  component diagram, API contract, and the authorization section of the
  engineering standards.

## Resolved Decisions

All five decisions are confirmed; this change is build-ready.

1. **Built-in role mutability** — **RESOLVED: immutable templates.** Built-in
   roles (`tenant_id = NULL`) are read-only; tenants customize by cloning into a
   tenant-scoped role. Preserves the "built-in code ⇒ known behavior" contract
   that the grading workflow relies on (Gate #4 in `design.md`).
2. **Permission granularity for v1** — **RESOLVED: action-level codes only**
   (e.g. `grade.record`). Object scope (*which* class/student) stays a row-level
   check in the owning service, as today (Gate #5 in `design.md`).
3. **Token size ceiling** — **RESOLVED: carry the unioned `perms[]`** alongside
   `roles[]`. Consistent with the chosen `roles + perms` token shape; the capped
   permission vocabulary keeps the token well under header limits.
4. **Role assignment API shape** — **RESOLVED: add/remove endpoints**
   (`POST`/`DELETE /tenants/me/users/{id}/roles/{roleId}`). Fits the chip-style
   UI and audits each grant/revoke independently.
5. **Migration cutover** — **RESOLVED: dual-read for one release**, then drop the
   `role` claim. Extractors accept both `{role}` and `{roles,perms}`; legacy
   tokens expire naturally within 15 min — no forced logout.
