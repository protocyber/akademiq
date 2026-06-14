## Why

The `/settings/roles` screen is a card grid (`RoleCard` in
`apps/web/src/app/settings/roles/page.tsx`): every role renders a large card
that dumps its full permission set as badges. It does not match the shadcn data
table standard the sibling `/settings/users` screen was just rebuilt on
(`improve-tenant-users-ui`), it has no search, sort, pagination, or URL-synced
view state, and the wall of permission badges is hard to scan once a tenant has
more than a handful of roles. Admins also have no at-a-glance signal for how
many users actually hold a given role.

The backend list endpoint already returns a `{ data, meta }` envelope but leaves
`meta` empty (`list_roles_handler`, `iam-service/src/http.rs:796`) and accepts no
query parameters — so there is no server-side search, sort, or pagination to
build the table on. The single-role delete path already enforces the right
guards (`delete_role`, `commands.rs:1359`: `BUILT_IN_ROLE_IMMUTABLE` and
`ROLE_IN_USE` via `count_role_holders`), but there is no bulk-delete endpoint
and no reusable confirmation dialog in the web app — destructive confirmations
today use the browser-native `window.confirm`.

## What Changes

- Rebuild `/settings/roles` on the same shadcn data table (TanStack Table) as the
  users screen: columns **Nama** (name + code subtitle), **Tipe** (Bawaan/Custom
  badge), and **Jumlah User** (count of tenant users holding the role), plus a
  header/row multi-select checkbox column and a per-row actions dropdown
  (Edit / Clone / Hapus). **BREAKING** for the admin UI layout: the per-role card
  grid and its inline Edit/Clone/Hapus buttons are removed.
- Move the permission set entirely out of the table — permissions are only shown
  (and edited) inside the create/edit/clone modal's existing checkbox grid, which
  is preserved as-is.
- Add server-side **search** (name/code), **sort** (Nama, Tipe, Jumlah User), and
  **pagination**, all synchronized to the browser URL so refresh/bookmark/share
  reproduces the same view — mirroring the `tenant-users-params` pattern. The
  toolbar has search only (no filter dropdowns).
- Sort/clone/edit/delete actions: the actions dropdown replaces the inline button
  row. Built-in roles offer only **Clone** (Edit/Hapus disabled), matching the
  existing immutability rule.
- Add a **bulk delete** flow over selected custom roles. The Hapus button is
  **disabled whenever the selection includes any built-in role** (red helper text
  tells the admin to deselect built-in roles first). When all selected roles are
  custom, clicking Hapus opens a reusable **AlertDialog** confirmation before the
  delete runs.
- Add backend endpoints/fields to IAM:
  - `GET /tenants/me/roles` gains query params (`search`, `sort`, `page`,
    `page_size`) and fills `meta { page, page_size, total }`; each role view
    gains a `user_count` field (count of `user_tenant_role` rows for that role in
    the calling tenant — per-tenant even for built-in roles).
  - A new **bulk delete** endpoint (`POST /tenants/me/roles/bulk/delete`, gated on
    `role.manage`) that is **all-or-nothing**: it pre-validates every id in the
    payload and rejects the entire request (no deletions) if any role is built-in
    (`BUILT_IN_ROLE_IMMUTABLE`) or still assigned to users (`ROLE_IN_USE`), then
    deletes all of them in one transaction.
- Add a reusable `src/components/ui/alert-dialog.tsx` (shadcn AlertDialog) for
  destructive confirmations. Scope note: this change only *introduces* the
  component and uses it for role bulk delete; it does NOT retrofit the existing
  `window.confirm` call sites on the users screen.

## Capabilities

### New Capabilities
- (none — all changes extend existing capabilities)

### Modified Capabilities
- `iam-service`: the role-management list endpoint gains server-side search,
  sort, and pagination with a populated `meta`, and each role view gains a
  per-tenant `user_count`; add an all-or-nothing bulk-delete endpoint that
  reuses the existing built-in-immutable and role-in-use guards.
- `web-user-role-management`: the role screen is rebuilt on a shadcn data table
  (Nama / Tipe / Jumlah User columns, no permission column) with URL-synced
  search/sort/pagination, multi-select, and a bulk-delete flow guarded against
  built-in roles and confirmed via a reusable AlertDialog; the create/edit/clone
  modal and its permission checkbox grid are preserved.

## Impact

- Backend: `apps/backend/services/iam-service` (http routes, commands, repo
  query for list + bulk delete, integration tests). API contract doc
  `docs/internal/11_integration_contracts/apis/iam-service-api.md`.
- Web: `apps/web/src/app/settings/roles/page.tsx` (rebuilt), new
  `src/components/ui/alert-dialog.tsx`, new
  `src/lib/schemas/tenant-roles-params.ts`, extended
  `src/lib/query/queries/use-tenant-roles.ts` (params + `user_count` type) and
  `src/lib/query/mutations/use-tenant-roles.ts` (bulk delete), and Vitest specs.
  Reuses the existing `@tanstack/react-table` and `DataTable` primitives added by
  `improve-tenant-users-ui`.
- No event-contract changes: single and bulk delete continue to emit the existing
  `role.deleted` event (one per deleted role).
