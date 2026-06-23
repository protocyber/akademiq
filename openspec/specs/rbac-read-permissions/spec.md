# rbac-read-permissions Specification

## Purpose
Defines the platform-owned read permissions and the `academic.ops.manage` permission used by the web console to gate admin-only screens.
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

### Requirement: The platform SHALL define the `academic.ops.manage` permission

The platform-owned permission catalog SHALL include `academic.ops.manage`,
which gates access to the operational management screens (students, teachers,
homerooms, teaching assignments). It is platform-owned and MUST NOT be
tenant-editable, and MUST be added idempotently with a deterministic seed UUID.

#### Scenario: The manage permission exists in the catalog

- **WHEN** the IAM permission catalog is listed
- **THEN** it includes `academic.ops.manage`

### Requirement: `academic.ops.manage` SHALL be granted only to tenant_admin

The `academic.ops.manage` permission SHALL be granted to the `tenant_admin`
built-in role only. It MUST NOT be granted to `teacher`, `homeroom_teacher`,
`principal`, `student`, or `parent` by the built-in seed, and any read-from-write
backfill MUST NOT auto-grant it to other roles. Grants MUST be idempotent.

#### Scenario: Admin holds the permission

- **WHEN** the role grants are seeded
- **THEN** the `tenant_admin` role holds `academic.ops.manage`

#### Scenario: Teacher does not hold the permission

- **WHEN** the role grants are seeded
- **THEN** the `teacher` and `homeroom_teacher` roles do not hold `academic.ops.manage`

### Requirement: `me/permissions` SHALL report permissions with held status

The IAM `GET /tenants/me/permissions` response SHALL include permissions,
each with a `held` flag reflecting whether the caller's effective permission set
includes it.

#### Scenario: Held flag reflects the caller's grants

- **WHEN** a `tenant_admin` calls `GET /tenants/me/permissions`
- **THEN** read permissions and `academic.ops.manage` are present with `held: true`

#### Scenario: Held flag is false for a teacher

- **WHEN** a `teacher` calls `GET /tenants/me/permissions`
- **THEN** `academic.ops.manage` is present with `held: false`

