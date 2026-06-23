## Context

Access control in `apps/web` is currently authentication-only (`AuthGuard`) plus module-entitlement checks; there is no role/permission page gate and no Next.js middleware. The sidebar (`sidebar-layout.tsx`) supports `permission`/`moduleAndPermission` visibility rules, but the four Operasional items use `{ kind: "always" }` and the Akademik settings entry uses `academic.config.read` (which teachers also hold).

`/grading/entry` is a teacher-facing page (gated on `grade.read`). It calls `useTenantUsers` → `GET /iam/tenants/me/users`, which requires `user.read` (seeded to `tenant_admin` only), so teachers get a 403. Investigation confirmed this is the only non-admin page hitting an admin IAM endpoint. The page already loads `GET /academic-ops/teachers` for teacher profile data, but linked-account email/username must come from the IAM user identity linked by `user_id`, not the teacher biodata `email` field.

The "Tambah Penugasan" dialog uses a custom `MultiSelect` (`components/ui/multi-select.tsx`) whose popover is rendered without a Portal (lines 133-138) and is therefore clipped by the dialog's `overflow-hidden`/`overflow-y-auto` (dialog.tsx:38,43). The Portal was intentionally removed earlier to fix a `CommandInput` focus conflict (header comment lines 3-9).

## Goals / Non-Goals

**Goals:**
- Hide and guard admin-only pages from non-admins (menu visibility + page-level redirect).
- Eliminate the `/grading/entry` 403 without adding a new endpoint.
- Make the dialog multi-select dropdown render unclipped without regressing search-input focus.

**Non-Goals:**
- No change to `academic.config.read` access or to academic-config endpoints (teachers must keep scope selectors and grade entry working).
- No new IAM user-directory endpoint (rejected in favor of reusing academic-ops data).
- No Next.js middleware introduction (page-level guards are consistent with the existing `AuthGuard` pattern).
- No change to the `academic_ops` service authorization model.

## Decisions

### D1: Gate Operasional with a new `academic.ops.manage`; gate Akademik settings with existing `academic.config.write`
- `academic.ops` has no existing read/manage permission suited to admin gating, so introduce `academic.ops.manage`, seeded to `tenant_admin` only.
- `/settings/academic/*` reuses `academic.config.write` (already admin-only). Removing `academic.config.read` from teachers was rejected: it is a universal scope permission used app-wide (the global `AcademicScopeProvider` and sidebar selectors), and removing it would 403 four endpoints across six non-admin pages.
- Trap avoided: the existing `V19` backfill maps `academic.config.write → academic.config.read`. A brand-new `academic.ops.manage` is NOT covered by that backfill, so it will not leak to other roles — but the seed migration must also ensure no new backfill rule grants it broadly.

### D2: Page-level guards in addition to menu hiding
Menu hiding does not protect typed URLs. Add a permission-aware guard (a wrapper/redirect using `useTenantPermissions()` held flags, consistent with `AuthGuard`) on `/students`, `/teachers`, `/homerooms`, `/teaching-assignments`, and `/settings/academic/*`. Non-admins are redirected (e.g. to `/dashboard`).

### D3: Resolve teacher identity from academic-ops on `/grading/entry`
Drop `useTenantUsers`. Build teacher display from `useTeachers()` (already loaded): teacher name from `full_name`, linked status from `user_id != null`, and account label from an academic-ops `linked_user` projection (`linked_user.email ?? linked_user.username`). Do not use teacher biodata `email` to decide whether the IAM account is linked. If `user_id` exists but the projection is not available yet, show a neutral linked fallback (`akun terhubung`) rather than `(akun belum terhubung)`. This removes the 403 without exposing a new non-admin IAM lookup endpoint.

### D4: Re-portal the MultiSelect popover while preserving focus
Re-introduce `PopoverPrimitive.Portal` around the `MultiSelect` content so it escapes the dialog `overflow`, and resolve the original `CommandInput` focus conflict (e.g. by handling Radix Dialog's `onOpenAutoFocus`/pointer-event interaction, or matching the working portaled pattern in `select.tsx`/`popover.tsx`). This requires manual verification because the change re-touches the exact area of a prior bug.

## Risks / Trade-offs

- **Re-portaling regresses CommandInput focus** → Verify focus/typing manually inside the dialog; mirror the working portaled `popover.tsx` pattern; keep the fix isolated to `multi-select.tsx`.
- **`academic.ops.manage` accidentally backfilled to other roles** → Seed grants explicitly to `tenant_admin` only and confirm no write→read style backfill references it.
- **Page-guard redirect loops** → Redirect target (`/dashboard`) is `always` visible, avoiding loops.
- **Other non-admin pages depend on hidden menu state** → Investigation confirmed only `/grading/entry` hit an admin IAM endpoint; the four Operasional pages are admin-only by intent, so gating them does not break non-admin flows.
- **Tests assert old menu/visibility behavior** → Update navigation/access-control and teaching-assignments dialog tests.

## Migration Plan

1. iam-service: add migration defining `academic.ops.manage` and granting it to `tenant_admin` (idempotent, deterministic UUID).
2. web: update sidebar visibility rules and add page guards.
3. web: refactor `/grading/entry` teacher-info resolution; remove `useTenantUsers` usage there.
4. web: fix `MultiSelect` portal + focus.
5. Update tests. Rollback: revert web changes; the new permission can remain harmlessly seeded.

## Open Questions

- None blocking. Redirect destination for guarded pages assumed to be `/dashboard`; adjust if a dedicated "not authorized" view is preferred.
