## Why

The console menu does not reflect what a user can actually do: the sidebar shows a flat list of items regardless of the user's roles, permissions, or enabled modules, and a user with no access to a page still sees its menu entry (and only discovers the wall after clicking). Separately, the RBAC catalog is write-only — there are permissions like `academic.config.write` and `grade.record` but no read permissions — so there is no clean signal for "may view this page". This change introduces read permissions, enforces them end-to-end, and restructures the navigation into a grouped, access-aware menu.

## What Changes

- Add five read permissions to the platform RBAC catalog: `user.read`, `role.read`, `academic.config.read`, `grade.read`, `report.read`; grant them to the built-in roles that legitimately read those areas (including `student`/`parent` for `report.read`).
- **BREAKING** Enforce the new read permissions on the corresponding GET endpoints in iam-service, academic-config-service, and grading-service. Callers without the permission receive HTTP 403. Existing roles are granted the matching reads so today's access is preserved.
- Restructure the web sidebar into grouped navigation: `Dashboard`, `Pengaturan` (Modul Aktif, Pengguna, Role & Izin, Akademik→[Tahun Ajaran, Mata Pelajaran, Template Kelas]), `Operasional` (Siswa, Guru, Kelas, Penugasan), `Akademik` (Nilai, Rapor).
- Hide menu items the user cannot access: visibility is the combination of enabled module (`useTenantMe.modules`) AND held permission (`useTenantPermissions`). The `Operasional` group is gated by the `academic_ops` module only (that service authorizes by feature, not permission). Empty groups are hidden entirely.

## Capabilities

### New Capabilities
- `rbac-read-permissions`: The platform read-permission vocabulary (`*.read`), the built-in role grants, and the GET-endpoint enforcement across iam/academic-config/grading services.
- `web-navigation-access-control`: The grouped sidebar structure and the rules for showing/hiding menu items and groups based on enabled modules and held permissions.

### Modified Capabilities
- `iam-service`: GET endpoints for users, roles, and permissions gain `user.read` / `role.read` enforcement.
- `academic-config-service`: GET endpoints (years, curriculum versions, subjects, policy, class templates) gain `academic.config.read` enforcement.
- `grading-service-grade-capture`: grade/evaluation/report GET endpoints gain `grade.read` / `report.read` enforcement.

## Impact

- **iam-service**: new migration seeding `*.read` permissions + `role_permission` grants; `require_permission(read)` on list/get handlers; `me/permissions` continues returning the full catalog with `held`.
- **common-auth**: add `PERM_*_READ` constants.
- **academic-config-service / grading-service**: add read-permission gates on GET handlers; coordinate with `secure-published-report-card` for the portal `report.read` path.
- **apps/web**: rewrite `sidebar-layout.tsx` nav model into grouped, collapsible items; add a visibility helper combining `useTenantMe.modules` + `useTenantPermissions`; update active-state logic for the new routes.
- **Dependency**: `secure-published-report-card` provides the ownership check that `report.read` enforcement relies on for the student/parent portal.
- **Regression surface**: GET endpoints currently require only a token (+feature). Enforcing reads can cut off roles that read today (notably `student`/`parent` portal, `teacher`/`homeroom_teacher` grade views) unless grants are seeded correctly.
