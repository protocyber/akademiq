## 1. IAM: read permissions + grants

- [ ] 1.1 Add migration seeding `user.read`, `role.read`, `academic.config.read`, `grade.read`, `report.read` with deterministic UUIDs (continue the `V11` scheme), idempotent on `code`
- [ ] 1.2 Add migration granting reads per the design matrix (tenant_admin all five; super_admin config.read; teacher/homeroom_teacher config.read+grade.read+report.read; principal report.read; student/parent report.read), idempotent
- [ ] 1.3 Add backfill grant: any existing role holding a write permission also gets its paired read (write ⇒ read superset)
- [ ] 1.4 Verify `GET /tenants/me/permissions` returns the five new codes with correct `held` flags (add/extend a test)

## 2. common-auth constants

- [ ] 2.1 Add `PERM_USER_READ`, `PERM_ROLE_READ`, `PERM_ACADEMIC_CONFIG_READ`, `PERM_GRADE_READ`, `PERM_REPORT_READ` and export them from `lib.rs`

## 3. Enforce reads on GET endpoints

- [ ] 3.1 iam-service: gate `list_tenant_users` on `user.read`; gate `list_roles`/`get_role` on `role.read`; leave `list_permissions` and `/me` open
- [ ] 3.2 academic-config-service: gate year/curriculum/subject/policy/class-template GET handlers on `academic.config.read` (in addition to feature)
- [ ] 3.3 grading-service: gate grade/evaluation/formula/score GET handlers on `grade.read`; gate report-type/report-card GET handlers on `report.read`
- [ ] 3.4 Per-service integration tests: assert each built-in role still reads its areas (no regression) and that a role lacking the read gets 403

## 4. Web: grouped sidebar model

- [ ] 4.1 Replace the flat `navItems` in `sidebar-layout.tsx` with a grouped model (Dashboard; Pengaturan→[Modul Aktif, Pengguna, Role & Izin, Akademik]; Operasional→[Siswa, Guru, Kelas, Penugasan]; Akademik→[Nilai, Rapor])
- [ ] 4.2 Render group headings with child items visually distinct from top-level items; preserve active-state highlighting for the new routes (incl. `activePrefix`/`activePrefixes`)
- [ ] 4.3 Ensure mobile (Sheet) and desktop sidebars share the grouped model

## 5. Web: visibility helper

- [ ] 5.1 Add a `useMenuVisibility()` (or pure helper) combining `useTenantMe().modules` (enabled) and `useTenantPermissions()` (held) per the spec mapping
- [ ] 5.2 Apply the mapping: Pengguna→user.read; Role & Izin→role.read; Akademik(settings)→academic_config+academic.config.read; Nilai→grading+grade.read; Rapor→grading+report.read; Operasional→academic_ops module only; Modul Aktif→billing.view; Dashboard→always
- [ ] 5.3 Hide a group entirely when it has no visible children; handle loading state (avoid flicker) gracefully
- [ ] 5.4 Add a test asserting items hide/show correctly for representative role sets (admin, teacher, parent, ops-only)

## 6. Integration & validation

- [ ] 6.1 Confirm `secure-published-report-card` is merged (or coordinate) so `report.read` portal enforcement has the ownership check
- [ ] 6.2 Confirm the `academic_ops` feature_code value used by `useTenantMe().modules` matches the Operasional gate
- [ ] 6.3 Run `make test` across both submodules; run web lint/typecheck
