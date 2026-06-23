## ADDED Requirements

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

### Requirement: `me/permissions` SHALL report `academic.ops.manage` with held status

The IAM `GET /tenants/me/permissions` response SHALL include `academic.ops.manage`
with a `held` flag reflecting whether the caller's effective permission set
includes it, so the web console can gate menu items and page guards.

#### Scenario: Held flag reflects admin grant

- **WHEN** a `tenant_admin` calls `GET /tenants/me/permissions`
- **THEN** `academic.ops.manage` is present with `held: true`

#### Scenario: Held flag is false for a teacher

- **WHEN** a `teacher` calls `GET /tenants/me/permissions`
- **THEN** `academic.ops.manage` is present with `held: false`
