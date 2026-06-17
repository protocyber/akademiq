# web-navigation-access-control Specification

## Purpose
TBD - created by archiving change rbac-read-and-menu-restructure. Update Purpose after archive.
## Requirements
### Requirement: The sidebar SHALL present a grouped navigation structure

The web console sidebar SHALL render the following grouped structure:

- `Dashboard`
- `Pengaturan` (group): `Modul Aktif`, `Pengguna`, `Role & Izin`, `Akademik`
  (the `Akademik` entry routes to the academic settings, which itself presents
  `Tahun Ajaran`, `Mata Pelajaran`, `Template Kelas` as tabs)
- `Operasional` (group): `Siswa`, `Guru`, `Kelas`, `Penugasan`
- `Akademik` (group): `Nilai`, `Rapor`

Groups SHALL visually distinguish their child items from top-level items.

#### Scenario: Grouped items render under their headings

- **WHEN** a fully-privileged user opens the console
- **THEN** the sidebar shows `Dashboard`, a `Pengaturan` group, an `Operasional` group, and an `Akademik` group with the listed children

### Requirement: Menu items SHALL be hidden when the user lacks access

Each menu item SHALL be shown only when the user can access it. Access is the
combination of the relevant module being enabled (from `useTenantMe().modules`) AND the
relevant permission being held (from `useTenantPermissions()`), per this mapping:

- `Pengguna` → `user.read`
- `Role & Izin` → `role.read`
- `Akademik` (settings) → module `academic_config` AND `academic.config.read`
- `Nilai` → module `grading` AND `grade.read`
- `Rapor` → module `grading` AND `report.read`
- `Operasional` group (`Siswa`/`Guru`/`Kelas`/`Penugasan`) → module `academic_ops` only (no per-item permission, because that service authorizes by feature)
- `Modul Aktif` → `billing.view`
- `Dashboard` → always visible

A group with no visible children SHALL be hidden entirely.

#### Scenario: A user without grade access sees no Nilai item

- **WHEN** a user lacks `grade.read` (or the `grading` module is disabled)
- **THEN** the `Nilai` menu item is not rendered

#### Scenario: An empty group is hidden

- **WHEN** a user can access none of `Pengguna`, `Role & Izin`, `Akademik`, or `Modul Aktif`
- **THEN** the `Pengaturan` group heading is not rendered

#### Scenario: Operasional follows the module only

- **WHEN** the `academic_ops` module is enabled for the tenant
- **THEN** the `Operasional` group and its four items are visible regardless of write permissions

