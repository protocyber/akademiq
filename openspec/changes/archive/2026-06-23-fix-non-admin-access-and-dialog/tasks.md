## 1. Backend — iam-service permission

- [x] 1.1 Add refinery migration defining permission `academic.ops.manage` (deterministic UUID, platform-owned, idempotent)
- [x] 1.2 Grant `academic.ops.manage` to `tenant_admin` only; confirm no read-from-write backfill grants it to other roles
- [x] 1.3 Verify `GET /tenants/me/permissions` returns `academic.ops.manage` with correct `held` flag for admin (true) and teacher (false)
- [x] 1.4 Add/extend integration test asserting admin holds and teacher lacks `academic.ops.manage`

## 2. Web — sidebar visibility

- [x] 2.1 Change Operasional items (`Siswa`/`Guru`/`Kelas`/`Penugasan`) visibility to `moduleAndPermission: academic_ops + academic.ops.manage` in `sidebar-layout.tsx`
- [x] 2.2 Change Akademik settings entry visibility to `moduleAndPermission: academic_config + academic.config.write`
- [x] 2.3 Confirm empty `Operasional`/`Pengaturan` groups hide when no children are visible

## 3. Web — page-level guards

- [x] 3.1 Add a permission-aware guard (using `useTenantPermissions()` held flags) that redirects non-admins
- [x] 3.2 Apply `academic.ops.manage` guard to `/students`, `/teachers`, `/homerooms`, `/teaching-assignments`
- [x] 3.3 Apply `academic.config.write` guard to `/settings/academic/*`
- [x] 3.4 Verify direct-URL navigation by a teacher redirects to `/dashboard` and admin access is unaffected

## 4. Web — grade-entry teacher info

- [x] 4.1 Remove the `useTenantUsers` call from `app/grading/entry/page.tsx`
- [x] 4.2 Derive teacher name/email/link-status from `useTeachers()` (academic-ops) and update `TeacherInfoBar`
- [x] 4.3 Confirm no request to `/iam/tenants/me/users` is made and the screen loads for a non-admin without 403

## 5. Web — MultiSelect portal fix

- [x] 5.1 Re-introduce `PopoverPrimitive.Portal` around `MultiSelect` content in `components/ui/multi-select.tsx`
- [x] 5.2 Resolve the `CommandInput` focus/typing conflict inside the Radix Dialog (mirror the working portaled `popover.tsx`/`select.tsx` pattern)
- [ ] 5.3 Manually verify the Tambah Penugasan dialog dropdowns render unclipped and the search input is focusable/typeable

## 6. Tests

- [x] 6.1 Update navigation/access-control tests for the new Operasional (`academic.ops.manage`) and Akademik (`academic.config.write`) visibility rules
- [x] 6.2 Add a test that a non-admin is redirected from a guarded page
- [x] 6.3 Update/extend the teaching-assignments dialog test for unclipped multi-select rendering
- [x] 6.4 Add a test asserting `/grading/entry` makes no admin IAM call

## 7. Verification

- [x] 7.1 Run `cd apps/backend && make test` for iam-service
- [ ] 7.2 Run web lint + unit tests + relevant Playwright spec in `apps/web`
- [ ] 7.3 Manual: log in as a teacher and confirm hidden menus, redirects, working grade entry, and unclipped dialog dropdowns
