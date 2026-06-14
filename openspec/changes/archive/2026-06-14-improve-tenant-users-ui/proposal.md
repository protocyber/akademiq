## Why

The `/settings/users` screen is a hand-rolled CSS-grid "table" with inline
controls that are hard to scan and inconsistent with the shadcn/ui standard.
It also relates to a data-integrity bug: a user's tenant membership is modeled
*only* by their `user_tenant_role` rows, so removing a user's last role silently
un-enrolls them. The backend guard for that bug ships in the separate
`fix-last-role-guard` change (a prerequisite); this change builds on it — the
edit modal surfaces the `LAST_ROLE` refusal and adds an explicit
remove-from-tenant action as the sanctioned off-boarding path. On top of that,
admins can only create users by email invitation — there is no way to create a
user with a chosen username or to edit an existing user's identity fields, even
though `username` is the system's global login key.

## What Changes

- Rename the page title from "Pengguna Tenant" to "Pengguna".
- Replace the bespoke grid table with a shadcn data table (TanStack Table):
  sortable columns, header/row multi-select checkboxes, pagination — preserving
  the existing bulk actions (enable/disable/change-role) and CSV export.
- Keep search, role filter, status filter, sort, and pagination synchronized to
  the browser URL so refresh/bookmark/share reproduces the same view.
- Add a **create-user** flow (modal) and an **edit-user** flow (modal) covering
  identity fields, roles, password reset, and enable/disable. Move the inline
  "tambah role" selector and the inline reset-password button into the edit
  modal. **BREAKING** for the admin UI layout: inline row controls are removed.
- Add a **username** field (required, no `@`, globally unique, case-insensitive)
  to the create/edit flows, matching the IAM grand-design contract.
- Add backend endpoints to IAM for admin user create and identity update, since
  none exist today (`POST /tenants/me/users`, `PATCH /tenants/me/users/:id`).
  Identity update is gated on a new `user.update` permission (editing `username`
  changes the global login key, so it is not folded into `user.invite`).
- Create is for genuinely new people: if the submitted `username`/`email`
  already belongs to an existing user, the endpoint MUST fail with a conflict
  whose message directs the admin to the invitation flow (which already knows how
  to add an existing user to a tenant). No silent upsert.
- Fix the disappearing-user bug: the service MUST refuse removing a user's last
  role in a tenant (new `LAST_ROLE` guard), and the edit-modal UX makes role
  removal explicit so it is never triggered by an accidental single click.
- Add an explicit **remove-from-tenant** action (drops all of the user's roles in
  the tenant in one transaction, emitting `tenant_user.removed`) so admins still
  have an off-boarding path now that last-role removal is refused. This is the
  *only* sanctioned way to un-enroll a user; it lives behind a confirmation in the
  edit modal, never an inline single click.
- Move the invitations/undangan section below the main table.
- Replace the roles checkbox grid in the invitation modal with a shadcn
  multiselect dropdown.

## Capabilities

### New Capabilities
- (none — all changes extend existing capabilities)

### Modified Capabilities
- `tenant-user-management`: add admin user create + identity-update endpoints
  with global username uniqueness; add a last-role removal guard so removing a
  user's final role in a tenant is refused instead of silently un-enrolling; add
  an explicit remove-from-tenant operation as the sanctioned off-boarding path.
  Existing role events keep their current names — add/remove emit
  `tenant_user.role_assigned` / `tenant_user.role_removed`, and
  `tenant_user.role_changed` stays reserved for the single-role *replace*
  (`change_user_role`); this change does NOT rename or reuse them, and bulk
  "change role" MUST go through add/remove (not the replace path) so the
  `LAST_ROLE` guard is honoured.
- `web-user-management-list`: the screen is rebuilt on a shadcn data table and
  gains create-user and edit-user modals; bulk actions, export, URL-synced view
  state, and the invite flow are preserved; invitations move below the table.
- `web-user-role-management`: per-user role editing and reset-password move from
  inline row controls into the edit-user modal; invitation role selection uses a
  shadcn multiselect dropdown.

## Impact

- Backend: `apps/backend/services/iam-service` (http routes, commands, queries,
  repo, events, integration tests, migrations for username uniqueness if not
  already enforced). API contract doc
  `docs/internal/11_integration_contracts/apis/iam-service-api.md` and IAM ERD.
- Web: `apps/web/src/app/settings/users/page.tsx`, new shadcn primitives under
  `src/components/ui/` (table, data-table, command, dropdown-menu), new deps
  `@tanstack/react-table` and `cmdk`, new/extended schemas under
  `src/lib/schemas/`, new query/mutation hooks under `src/lib/query/`, and
  Vitest specs.
- No changes to the cross-service event envelope shapes beyond adding
  `tenant_user.created` / `tenant_user.updated` / `tenant_user.removed` events.
  Note `tenant-audit-log` (separate in-flight change) consumes
  `tenant_user.role_changed`; this change leaves that event's name and payload
  untouched.
