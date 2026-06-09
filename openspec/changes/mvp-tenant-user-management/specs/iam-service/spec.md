## MODIFIED Requirements

### Requirement: IAM SHALL seed the built-in role set

IAM MUST seed the platform's built-in roles with stable `role.code` values
that match the `ROLE_*` constants in `common-auth`. The seeded set MUST
include `super_admin`, `tenant_admin`, `teacher`, `homeroom_teacher`,
`principal`, `student`, and `parent`. The `principal` role is the final
academic approver in the report-card workflow.

#### Scenario: Principal is part of the seeded role set

- **WHEN** IAM migrations run against an empty database
- **THEN** the `role` table contains a `principal` row whose code matches `ROLE_PRINCIPAL` in `common-auth`, alongside the other six built-in roles

#### Scenario: Role codes match auth constants

- **WHEN** a contributor compares seeded `role.code` values to the `ROLE_*` constants in `common-auth`
- **THEN** every seeded code has a corresponding constant and vice versa
