## ADDED Requirements

### Requirement: IAM SHALL seed the grade.evaluation.manage permission

IAM MUST add `grade.evaluation.manage` to the fixed, seeded `permission`
vocabulary, describing the authority to create, update, and delete concrete
grading evaluations for a teaching assignment. The permission MUST be seeded
idempotently and MUST NOT be editable by tenants. The built-in roles
`tenant_admin`, `teacher`, and `homeroom_teacher` MUST be granted this permission
via `role_permission`, so their issued access tokens carry it in `perms`.

#### Scenario: The permission exists in the vocabulary

- **WHEN** the IAM permission seed has run
- **THEN** a permission with code `grade.evaluation.manage` exists and is not tenant-editable

#### Scenario: Built-in roles carry the permission

- **WHEN** a user holding the built-in `teacher`, `homeroom_teacher`, or `tenant_admin` role obtains a tenant-scoped access token
- **THEN** the token's `perms` includes `grade.evaluation.manage`

#### Scenario: Seed is idempotent

- **WHEN** the permission and role-permission seed migrations run more than once
- **THEN** no duplicate permission or role-permission rows are created
