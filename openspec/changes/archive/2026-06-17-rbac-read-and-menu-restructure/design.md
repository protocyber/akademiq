## Context

The console sidebar (`apps/web/src/components/layout/sidebar-layout.tsx`) renders a flat
`navItems` array to every authenticated user. No item is hidden based on permissions or
modules. Meanwhile the RBAC catalog (IAM migrations `V11`/`V12`) defines only write/action
permissions — `user.invite`, `academic.config.write`, `grade.record`, `report.generate`,
etc. — with no read permissions. `useTenantPermissions()` already returns the full catalog
with a `held` flag per permission, so the frontend has a clean signal source; it just lacks
read codes to key off and a menu model that uses them.

Services authorize GETs today by token + tenant (+ feature for some), never by permission.
Adding read enforcement is therefore a behavioral change with a real regression surface:
roles that read today (teachers reading grades, students/parents reading published cards)
must be granted the new reads or lose access.

This change depends on `secure-published-report-card` for the portal ownership check that
the `report.read` enforcement relies on.

## Goals / Non-Goals

**Goals:**
- Introduce read permissions and grant them to built-in roles preserving current access.
- Enforce reads on GET endpoints in iam / academic-config / grading (FE + BE RBAC).
- Restructure the sidebar into the grouped, access-aware navigation described in the spec.

**Non-Goals:**
- Introducing read permissions for `academic-ops` GETs (that service is feature-gated;
  menu visibility for `Operasional` follows the module only).
- Adding per-action (write) gates beyond what exists — only read gates are new.
- Redesigning page-level RBAC guards inside pages beyond menu visibility.

## Decisions

### D1: Read permissions are platform-owned, like writes
Seed `*.read` in an IAM migration with deterministic UUIDs (continuing the `V11` scheme)
and grant them in a companion migration mirroring `V12`. `me/permissions` keeps returning
the full catalog with `held` — no shape change, just new entries.

_Alternative_: make reads tenant-customizable. Rejected — the catalog is platform-owned by
policy, and tenant-editable reads would break the "read = may view" invariant.

### D2: Enforce reads on GET handlers, not a middleware blanket
Add explicit `require_permission(read)` calls in each GET handler (same pattern as the
existing `require_academic_config_write`). This keeps gates visible per-route and avoids
over-restricting the tenant-me or permissions endpoints, which must stay open to any
authenticated tenant member.

_Alternative_: a blanket middleware that requires *some* read for all GETs. Rejected — too
coarse; the permissions/tenant-me endpoints must stay open, and ops GETs stay feature-gated.

### D3: Menu visibility = module enabled AND permission held
`Operasional` is the exception: `academic-ops` authorizes by feature only, so the group
follows the module and needs no permission. This is consistent with how that service works.
Empty groups are hidden so users see only relevant structure.

_Alternative_: require `academic.config.read` (or a new ops read) for the Operasional items
too. Rejected — would invent a permission the service does not enforce and misrepresent the
actual authz model.

### D4: Sequence behind `secure-published-report-card`
`report.read` enforcement on the portal path requires the ownership check to exist, or
students/parents get 403'd on their own cards. This change therefore lands after
`secure-published-report-card`.

## Risks / Trade-offs

- **Regression: a role loses read access** → Mitigated by the seeding matrix (D1); the
  integration test for each service MUST assert that each built-in role still reads its
  areas after enforcement.
- **Stale grants for custom roles** → Custom roles are tenant-defined; they keep whatever
  they had. If a tenant created a custom role that could read grades via the old "token
  only" path, it will now 403 unless it holds `grade.read`. Mitigation: migration grants
  the new reads to any existing role that already holds the corresponding write permission
  (a write holder is a superset reader).
- **FE menu hidden for admins mid-migration** → The web uses `held` flags; before grants
  land the menu would hide items. Mitigation: ship BE grants + web together; the web can
  treat a missing `held` for a known code as "show" until rollout completes (graceful).
- **Permissions endpoint must stay open** → Explicitly excluded from enforcement (D2).

## Migration Plan

1. IAM: migration adding `*.read` + grants (including the "existing write ⇒ new read"
   backfill for custom roles).
2. common-auth: `PERM_*_READ` constants.
3. iam / academic-config / grading: add read gates on GET handlers; run per-service
   integration tests covering each built-in role's read access.
4. Web: ship the grouped sidebar + visibility helper together with the BE release.
5. Rollback: the read gates are additive; reverting them restores the token-only behavior.
   Grants are additive and harmless if left behind.

## Open Questions

- Should the "existing write ⇒ new read" backfill apply to all write permissions or only
  the ones in the read matrix? (Leaning: only the five pairs.)
- Confirm the exact feature_code used for `academic_ops` in `useTenantMe().modules`
  (code says `"academic_ops"`; confirm before wiring the Operasional gate).
