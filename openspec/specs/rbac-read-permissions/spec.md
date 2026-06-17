# rbac-read-permissions Specification

## Purpose
TBD - created by archiving change rbac-read-and-menu-restructure. Update Purpose after archive.
## Requirements
### Requirement: The platform SHALL define read permissions

The platform-owned permission catalog SHALL include the read permissions
`user.read`, `role.read`, `academic.config.read`, `grade.read`, and `report.read`.
These permissions are platform-owned and MUST NOT be tenant-editable, consistent with
the existing write permissions. They MUST be added idempotently with deterministic seed
UUIDs.

#### Scenario: Read permissions exist in the catalog

- **WHEN** the IAM permission catalog is listed
- **THEN** it includes `user.read`, `role.read`, `academic.config.read`, `grade.read`, and `report.read`

### Requirement: Built-in roles SHALL be granted the reads they use today

The read permissions SHALL be granted to the built-in roles so that current read access
is preserved after enforcement is added:

- `tenant_admin`: `user.read`, `role.read`, `academic.config.read`, `grade.read`, `report.read`
- `super_admin`: `academic.config.read`
- `teacher`, `homeroom_teacher`: `academic.config.read`, `grade.read`, `report.read`
- `principal`: `report.read`
- `student`, `parent`: `report.read`

Grants MUST be idempotent.

#### Scenario: A parent retains report read access

- **WHEN** the role grants are seeded
- **THEN** the `parent` role holds `report.read`

#### Scenario: A teacher retains grade read access

- **WHEN** the role grants are seeded
- **THEN** the `teacher` role holds `grade.read` and `academic.config.read`

### Requirement: `me/permissions` SHALL report read permissions with held status

The IAM `GET /tenants/me/permissions` response SHALL include the new read permissions,
each with a `held` flag reflecting whether the caller's effective permission set
includes it.

#### Scenario: Held flag reflects the caller's grants

- **WHEN** a `tenant_admin` calls `GET /tenants/me/permissions`
- **THEN** `user.read`, `role.read`, `academic.config.read`, `grade.read`, and `report.read` are present with `held: true`

