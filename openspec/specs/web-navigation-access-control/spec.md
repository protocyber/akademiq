# web-navigation-access-control Specification

## Purpose
Specifies sidebar navigation grouping, permission-based menu visibility, and page-level redirect guards for admin-only screens in the web console.
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
- `Akademik` (settings) → module `academic_config` AND `academic.config.write`
- `Nilai` → module `grading` AND `grade.read`
- `Rapor` → module `grading` AND `report.read`
- `Operasional` group (`Siswa`/`Guru`/`Kelas`/`Penugasan`) → module `academic_ops` AND `academic.ops.manage`
- `Modul Aktif` → `billing.view`
- `Dashboard` → always visible

A group with no visible children SHALL be hidden entirely.

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

### Requirement: The curriculum selector SHALL be hidden unless multiple options exist

The header academic-scope curriculum `<Select>` MUST be rendered only when the
selected year has more than one curriculum version. When exactly one version
exists, the UI MUST auto-select it into scope but hide the control; when none
exist, the control MUST stay hidden. The control MUST NOT flicker during loading.

#### Scenario: Single curriculum hides the selector but sets scope

- **WHEN** the selected year has exactly one curriculum version
- **THEN** the curriculum selector is not shown and that version is selected as
  the active curriculum scope

#### Scenario: Multiple curricula show the selector

- **WHEN** the selected year has two or more curriculum versions
- **THEN** the curriculum selector is rendered and lets the user choose

### Requirement: The user-menu avatar SHALL be visible in light mode

The header user-menu avatar circle MUST have sufficient contrast against the
light header background so it is clearly visible (not near-white on white), while
remaining visible in dark mode.

#### Scenario: Avatar is visible on the light header

- **WHEN** the app is in light mode and the header renders the user-menu avatar
- **THEN** the avatar circle is clearly distinguishable from the header
  background

### Requirement: Academic scope selectors SHALL stack vertically in the mobile sidebar

When the academic-scope selectors are rendered in the mobile sidebar, they MUST
use a vertical (stacked, full-width) layout so they do not overflow the narrow
sidebar. The header (desktop) placement MAY remain horizontal.

#### Scenario: Scope selectors do not overflow the mobile sidebar

- **WHEN** the academic-scope selectors render inside the mobile sidebar
- **THEN** the year, semester, and curriculum selectors stack vertically at full
  width without horizontal overflow

### Requirement: Route-driven navigation shells SHALL use the shared Tabs styling

The web app MUST present the route-driven navigation shells
(`academic-settings.tsx`, `academic-ops-page.tsx`) using the shared `Tabs`
component in route-driven mode (`TabsTrigger asChild` wrapping `<Link>`, active
derived from pathname), preserving per-view URLs.

#### Scenario: Academic settings nav uses Tabs styling with working URLs

- **WHEN** an admin uses the academic settings navigation
- **THEN** the entries render as tabs and selecting one navigates to its URL,
  with the current page's tab marked active

