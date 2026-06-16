# student-guardian-linking Specification

## Purpose
Defines requirements for linking student profiles to IAM user accounts and managing guardian (parent) many-to-many relations in the academic-ops service, enabling self/guardian-scoped access to report cards and other student data.

## Requirements

### Requirement: A student profile SHALL be linkable to a single IAM user account

The academic-ops service MUST allow linking a student profile to at most one IAM
tenant user account via a nullable `student.user_id` column, mirroring the existing
`teacher.user_id` link. The service MUST expose `PATCH /api/v1/academic-ops/students/{id}/account`
with body `{ user_id }`. A given user account MUST link to at most one student in a
tenant (enforced by a unique index over `(tenant_id, user_id)` where `user_id IS NOT
NULL`). On a successful link the service MUST emit `student.account_linked{tenant_id,
student_id, user_id}`.

#### Scenario: Linking a student account

- **WHEN** a tenant admin PATCHes `/students/{id}/account` with a valid `user_id`
- **THEN** the student's `user_id` is set and a `student.account_linked` event is emitted

#### Scenario: A user cannot be linked to two students

- **WHEN** a tenant admin links a `user_id` already linked to a different student
- **THEN** the request is rejected with HTTP 409 and code `STUDENT_USER_ALREADY_LINKED`

### Requirement: A guardian SHALL relate IAM users to students many-to-many

The academic-ops service MUST maintain a `guardian(tenant_id, user_id, student_id)`
relation supporting many-to-many links: one guardian user MAY be linked to many
students and one student MAY have many guardians. The service MUST expose
`POST /api/v1/academic-ops/students/{id}/guardians` with body `{ user_id }` to add a
link and `DELETE /api/v1/academic-ops/students/{id}/guardians/{user_id}` to remove it.
A duplicate `(tenant_id, user_id, student_id)` link MUST be idempotent or rejected
with HTTP 409. On add the service MUST emit `guardian.linked{tenant_id, user_id,
student_id}`; on remove it MUST emit `guardian.unlinked{tenant_id, user_id,
student_id}`.

#### Scenario: One guardian linked to two children

- **WHEN** a tenant admin adds the same `user_id` as guardian to two different students
- **THEN** both links are stored and a `guardian.linked` event is emitted for each

#### Scenario: One student with two guardians

- **WHEN** a tenant admin adds two different `user_id`s as guardians of one student
- **THEN** both guardian links are stored for that student

#### Scenario: Removing a guardian link

- **WHEN** a tenant admin DELETEs an existing guardian link
- **THEN** the link is removed and a `guardian.unlinked` event is emitted

### Requirement: Link management SHALL be restricted to authorized staff

The student-account and guardian management endpoints MUST require an active
subscription and MUST be gated on the `academic_ops` feature entitlement, consistent
with the rest of the academic-ops service. They MUST resolve `tenant_id` from the JWT
and MUST NOT trust a client-supplied tenant.

#### Scenario: Feature gating applies

- **WHEN** a caller without the `academic_ops` entitlement calls a link endpoint
- **THEN** the request is rejected with HTTP 403 and code `FEATURE_NOT_AVAILABLE`
