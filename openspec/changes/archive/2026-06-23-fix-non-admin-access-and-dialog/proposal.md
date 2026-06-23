## Why

Several admin-only management pages are reachable by non-admin users because their sidebar menu items and pages are not gated by a role/permission. One of them, the teacher-facing `/grading/entry`, calls an admin-only IAM endpoint and receives a 403 for teachers. Separately, the multi-select dropdown in the "Tambah Penugasan" dialog is visually clipped by the dialog container. These are correctness and access-control bugs.

## What Changes

- Gate the admin-only pages so non-admins cannot see the menu items or open the pages:
  - `/students`, `/teachers`, `/homerooms`, `/teaching-assignments` → gated by a **new** `academic.ops.manage` permission (seeded to `tenant_admin` only).
  - `/settings/academic/*` → gated by the existing **`academic.config.write`** permission (already admin-only). **`academic.config.read` is intentionally NOT changed**, because teachers/homeroom teachers need it for the global academic scope selectors and grade entry.
- Add **page-level guards** that redirect non-admins away from these routes (menu hiding alone is insufficient because URLs can be typed directly).
- Hide the corresponding sidebar menu items for users lacking the gating permission.
- Fix the `/grading/entry` 403: **remove the `useTenantUsers` call** (admin-gated `GET /iam/tenants/me/users`) and resolve teacher name/email/account-link status from the academic-ops teachers data the page already loads. No new IAM endpoint is added.
- Fix the clipped dropdown in the "Tambah Penugasan" dialog by making the `MultiSelect` popover render via a Portal, while preserving the `CommandInput` focus behavior the Portal was originally removed to fix.

## Capabilities

### New Capabilities
- (none — `academic.ops.manage` is a permission grant covered by the modified capabilities below)

### Modified Capabilities
- `web-navigation-access-control`: admin-only pages and their menu items gain permission-based visibility and page-level redirect guards (`academic.ops.manage`, `academic.config.write`).
- `rbac-read-permissions`: introduce the `academic.ops.manage` permission and seed it to `tenant_admin` only.
- `web-grading-entry`: the grade-entry screen stops calling the admin IAM user-directory endpoint and resolves teacher identity from academic-ops data.
- `web-academic-ops-management`: the "Tambah Penugasan" dialog's multi-select dropdowns render without being clipped by the dialog.

## Impact

- **iam-service**: new permission `academic.ops.manage` defined and seeded to `tenant_admin` (new migration); ensure the V19-style read backfill does not unintentionally grant it elsewhere.
- **apps/web**:
  - `sidebar-layout.tsx` visibility rules for the four Operasional items (→ `academic.ops.manage`) and the Akademik group (→ `academic.config.write`).
  - Page-level guards/redirects for `/students`, `/teachers`, `/homerooms`, `/teaching-assignments`, `/settings/academic/*`.
  - `app/grading/entry/page.tsx`: drop `useTenantUsers`; derive teacher info from `useTeachers()`.
  - `components/ui/multi-select.tsx`: re-introduce a Portal for the popover content without regressing `CommandInput` focus (see the existing header comment, lines 3-9).
- **No backend endpoint changes** beyond the new permission seed; `academic.config.read` access is unchanged so teacher pages keep working.
- **Tests**: navigation/access-control tests and the teaching-assignments dialog test updated.
