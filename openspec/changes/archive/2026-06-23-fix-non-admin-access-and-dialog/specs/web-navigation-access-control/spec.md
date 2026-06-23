## MODIFIED Requirements

### Requirement: Menu items SHALL be hidden when the user lacks access

Each menu item SHALL be shown only when the user can access it. Access is the
combination of the relevant module being enabled (from `useTenantMe().modules`) AND the
relevant permission being held (from `useTenantPermissions()`), per this mapping:

- `Pengguna` → `user.read`
- `Role & Izin` → `role.read`
- `Akademik` (settings) → module `academic_config` AND `academic.config.write`
- `Nilai` → module `grading` AND `grade.read`
- `Rapor` → module `grading` AND `report.read`
- `Operasional` group (`Siswa`/`Guru`/`Kelas`/`Penugasan`) → module `academic_ops` AND `academic.ops.manage`
- `Modul Aktif` → `billing.view`
- `Dashboard` → always visible

A group with no visible children SHALL be hidden entirely. The change from
prior behavior is that the `Operasional` items now require the admin-only
`academic.ops.manage` permission (not module-only), and the `Akademik` settings
entry now requires `academic.config.write` (admin-only) rather than
`academic.config.read` (which non-admins retain for scope selectors).

#### Scenario: A user without grade access sees no Nilai item

- **WHEN** a user lacks `grade.read` (or the `grading` module is disabled)
- **THEN** the `Nilai` menu item is not rendered

#### Scenario: An empty group is hidden

- **WHEN** a user can access none of `Pengguna`, `Role & Izin`, `Akademik`, or `Modul Aktif`
- **THEN** the `Pengaturan` group heading is not rendered

#### Scenario: Operasional requires the admin permission

- **WHEN** the `academic_ops` module is enabled but the user lacks `academic.ops.manage`
- **THEN** the `Operasional` group and its four items are not rendered

#### Scenario: Teacher does not see the Akademik settings item

- **WHEN** a teacher holds `academic.config.read` but not `academic.config.write`
- **THEN** the `Akademik` settings menu item is not rendered

## ADDED Requirements

### Requirement: Admin-only pages SHALL redirect non-admins at the page level

The pages `/students`, `/teachers`, `/homerooms`, `/teaching-assignments`, and `/settings/academic/*` MUST guard access at the page level and redirect users who lack the gating permission, independent of menu visibility. `/students`,
`/teachers`, `/homerooms`, and `/teaching-assignments` require
`academic.ops.manage`; `/settings/academic/*` requires `academic.config.write`.
Hiding the menu item alone is not sufficient because the route can be reached by
typing the URL.

#### Scenario: Direct navigation by a non-admin is redirected

- **WHEN** a teacher without `academic.ops.manage` navigates directly to `/teaching-assignments`
- **THEN** the page does not render its admin content and the user is redirected away

#### Scenario: Direct navigation to academic settings by a teacher is redirected

- **WHEN** a teacher without `academic.config.write` navigates directly to `/settings/academic/terms`
- **THEN** the page does not render its admin content and the user is redirected away

#### Scenario: Admin can access the guarded pages

- **WHEN** a tenant admin holding the gating permission navigates to any guarded page
- **THEN** the page renders normally
