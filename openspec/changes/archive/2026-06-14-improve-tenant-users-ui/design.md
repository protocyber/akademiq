## Context

`/settings/users` (`apps/web/src/app/settings/users/page.tsx`, ~600 lines) is a
single client component that renders a hand-built CSS-grid table with inline
controls: a per-row "tambah role" `<Select>`, a per-row reset-password button,
and a sidebar invitation panel. View state (search/role/status/page/sort) is
already URL-synced via `lib/schemas/tenant-users-params.ts`.

Two structural facts drive this change:

1. **Membership = role rows.** IAM has no membership table. A user belongs to a
   tenant only while they have ≥1 row in `user_tenant_role`
   (`repo.rs:list_tenant_user_ids` uses `EXISTS(... user_tenant_role ...)`).
   `remove_user_role` (`commands.rs:716`) guards the *last admin* but not the
   *last role*, so removing a user's only role deletes their membership and they
   vanish from the list. This is the reported bug for `fitrah.pro@gmail.com`.
2. **No admin create/update.** IAM exposes invite, list, export, role add/remove,
   enable/disable, reset-password. There is no `POST /tenants/me/users` and no
   identity-field `PATCH`. `username` is already a global, case-insensitive
   unique, no-`@` column (`V6__username_identity.sql`), so the data model already
   supports a username field — only the admin-facing endpoints are missing.

Web conventions (`apps/web/CONVENTIONS.md`) require shadcn/ui-only primitives
(new ones via the shadcn CLI under `src/components/ui/`), TanStack Query for all
data access, Zod+RHF forms with backend-matching field names, and centralized
error copy. Backend conventions (`apps/backend/CONVENTIONS.md`) require CQRS
command/query separation, `AppError` codes, outbox events, and tenant resolution
from the JWT.

## Goals / Non-Goals

**Goals:**
- Rebuild the users screen on a shadcn data table (TanStack Table) with
  selection, sorting, pagination, preserving URL-synced view state, bulk actions,
  and CSV export.
- Add admin user create and identity-update endpoints with a username field that
  honors the existing global uniqueness contract.
- Fix the last-role bug with a backend `LAST_ROLE` guard and a UI that makes role
  removal explicit (inside the edit modal).
- Consolidate per-user actions (role add/remove, reset password, enable/disable,
  identity edit) into an edit modal; move invitations below the table; convert
  invite role selection to a shadcn multiselect.

**Non-Goals:**
- A real membership entity decoupled from roles (status independent of role
  rows). Out of scope; the `LAST_ROLE` guard plus the explicit
  remove-from-tenant action are the chosen fix.
- Hard-delete of users. Disable remains the soft-delete path; remove-from-tenant
  drops the user's roles (un-enrolls from this tenant) but does not delete the
  global user record. No bulk delete.
- Upsert-on-create for existing users. Create rejects known username/email and
  defers to the invitation flow (D3).
- Changing the username format rules or migration (already in place).
- Notification/email delivery for invitations (still manual activation link).

## Decisions

### D1: shadcn data table on TanStack Table (add `@tanstack/react-table`)
shadcn's data-table pattern is built on `@tanstack/react-table`, which is not yet
a dependency. Add it plus the shadcn `table` primitive and a thin
`ui/data-table.tsx`. *Alternative:* keep extending the CSS grid — rejected; it
already fights selection/sorting and violates the "shadcn datatables" ask.
Server-side data stays the source of truth; TanStack Table runs in
`manualPagination`/`manualSorting` mode so it renders the server page rather than
filtering client-side (matches the existing server-driven spec).

### D2: Bulk actions via shadcn `dropdown-menu`; multiselect via `cmdk` Command
Add `cmdk` and the shadcn `command`, `dropdown-menu`, and `popover`-based combobox
primitives. The invite modal's role checkbox grid and (optionally) the edit
modal's role picker use a Command-based multiselect. *Alternative:* multiple
`<Select>`s or checkbox grid — rejected; the task explicitly asks for a shadcn
multiselect dropdown.

### D3: Create = new endpoint, not invitation reuse
`POST /api/v1/iam/tenants/me/users` creates a user + grants roles in one
transaction, gated on `user.invite`, tenant from JWT, emitting
`tenant_user.created`. Password optional (admin may set one or leave the account
pending/reset-later). Create is strictly for *new* people: if `username` or
`email` already maps to an existing user, the transaction MUST abort with the
relevant conflict (`USERNAME_TAKEN` / email conflict) and the error copy MUST
point the admin at the invitation flow, which already knows how to add an
existing user to a tenant. No silent upsert-into-membership here — that would
duplicate invitation logic and surprise admins who think they are creating a
fresh account. *Alternative:* force everything through invitations — rejected per
the user's explicit choice to support direct create with a chosen username.
Reuse `common-auth::hash_password` for any password handling.

### D4: Update = identity PATCH (new `user.update` perm), roles stay separate
`PATCH /api/v1/iam/tenants/me/users/{id}` updates `username`/`email`/`full_name`
only, emitting `tenant_user.updated`. Because `username` is the global login key,
identity update is gated on a **new** `user.update` permission
(`PERM_USER_UPDATE = "user.update"`, added to `common-auth` alongside the
existing `user.invite`/`user.disable`/`user.role.assign`) rather than folded into
`user.invite`. The permission MUST be seeded onto the same built-in roles that
currently hold `user.invite` so existing admins keep working. Role changes
continue to flow through the existing add/remove role endpoints (called from the
same edit modal) so authorization and guards stay in one place. *Alternative:* a
single mega-PATCH that also sets roles — rejected; it would duplicate
role-assignment logic and its guards. *Alternative:* reuse `user.invite` —
rejected; editing the login key is more sensitive than inviting.

### D5: Fix the bug with a `LAST_ROLE` guard plus an explicit remove-from-tenant
In `remove_user_role`, after the existing last-admin check, count the user's
remaining roles in the tenant; if removing this role would reach zero, return
`AppError::conflict("LAST_ROLE", ...)`. The web edit modal surfaces this via
centralized error copy. Because that closes the only off-boarding path (membership
= role rows), add an explicit `DELETE /api/v1/iam/tenants/me/users/{id}` (or a
`remove-from-tenant` sub-action) that drops *all* of the user's roles in the
tenant in one transaction and emits `tenant_user.removed`, gated on
`user.disable` (the existing off-boarding-class permission) and guarded by the
same last-admin check. It lives behind a confirmation in the edit modal, never an
inline click. *Alternatives:* (a) auto-treat last-role removal as "remove from
tenant" with confirmation — rejected; conflates an accidental single click with a
deliberate off-board; (b) introduce a membership table — largest change,
explicitly a non-goal. Guard + explicit action is the minimal correct fix and
keeps the invariant in the domain layer.

### D7: Keep existing role-event names; never route bulk through replace
IAM already emits three distinct role events: `add_user_role` →
`tenant_user.role_assigned` (`commands.rs:703`), `remove_user_role` →
`tenant_user.role_removed` (`commands.rs:767`), and `change_user_role` (single-role
*replace*) → `tenant_user.role_changed` (`commands.rs:657`). The `tenant-audit-log`
change already consumes `role_changed`. This change therefore does NOT rename or
reuse any of them. The data table's bulk "change role" MUST be implemented as
add/remove calls so the new `LAST_ROLE` (and existing `LAST_ADMIN`) guard runs;
it MUST NOT call the `change_user_role` replace path, which bypasses those guards
and overwrites the audit-log payload. *Alternative:* unify the three into one
`role_changed` — rejected; breaking for the audit-log consumer and loses the
add-vs-remove distinction.

### D6: Username validation mirrors the DB contract in Zod
Web Zod schema for create/edit enforces required, no `@`, and the existing
format (`^[a-z][a-z0-9_-]{2,63}$`); the global-uniqueness conflict is only
knowable server-side, surfaced as `USERNAME_TAKEN` (409) mapped to a
`username` field error through `applyServerFieldErrors` + centralized messages.

## Risks / Trade-offs

- **New frontend deps (`@tanstack/react-table`, `cmdk`)** → pin versions, add via
  shadcn CLI so primitives land in the conventional location; bundle impact is
  modest and both are standard shadcn building blocks.
- **`LAST_ROLE` guard changes existing remove-role behavior** → could surprise
  callers/tests that relied on silent un-enroll; mitigate by updating IAM
  integration tests and documenting the new 409 in the API contract.
- **Create-user endpoint without email/notification** → admin must communicate
  credentials out-of-band (same limitation as invitations today); acceptable for
  this iteration.
- **Page is a large client component rebuild** → risk of regressing URL-sync and
  bulk actions; mitigate by reusing the existing `tenant-users-params` helpers
  and porting bulk/export logic rather than rewriting it.
- **Username global uniqueness vs. multi-tenant intuition** → admins may expect
  tenant-scoped usernames; the grand design says global. Surface a clear
  `USERNAME_TAKEN` message so the constraint is understandable.

## Migration Plan

1. Backend first: add the new `user.update` permission to `common-auth` and seed
   it onto the roles that already hold `user.invite`; add
   `tenant_user.created`/`tenant_user.updated`/`tenant_user.removed`
   create/update/remove-from-tenant endpoints + the `LAST_ROLE` guard; extend
   integration tests; update `iam-service-api.md` and the IAM ERD note. No DB
   migration required for username (constraints already exist); seeding the new
   permission may need a small migration/seed update.
2. Web: add deps + shadcn primitives, then rebuild the page, schemas, and hooks.
3. Verify with `cd apps/backend && make test` and `cd apps/web` Vitest, plus a
   manual pass of the `fitrah.pro@gmail.com` last-role scenario.
4. Rollback: the change is additive on the backend (new endpoints + one extra
   guard); reverting the guard restores prior behavior. The web page can be
   reverted independently since it only consumes existing+new endpoints.

## Open Questions

(none — see Resolved.)

### Resolved

- *Off-boarding after `LAST_ROLE`* → add an explicit remove-from-tenant action
  (D5), gated on `user.disable`. Not deferred.
- *Cross-tenant existing user on create* → reject with a conflict that points to
  the invitation flow; no silent upsert (D3).
- *Permission for identity PATCH* → a new `user.update` permission, distinct from
  `user.invite` (D4).
- *Password on create* → optional. An empty `password` creates a
  pending/reset-required account (same end state as an unaccepted invitation),
  and the admin uses the existing reset-password action to issue an activation
  link. Forcing a password would diverge from the invitation flow and make the
  admin handle a plaintext secret out-of-band.
- *Editing `username` — invalidate sessions / audit?* → No session
  invalidation: access tokens key off `sub` (user_id, `jwt.rs:73`), not
  `username`, so a rename never invalidates a live session and forcing logout
  would be a poor UX for a typo fix. Audit needs no new work here — the endpoint
  already emits `tenant_user.updated`, which the in-flight `tenant-audit-log`
  change consumes; the payload SHOULD include which identity fields changed so
  the audit entry is meaningful (captured in task 2.2).
