## ADDED Requirements

### Requirement: The grade-entry screen SHALL not call admin-only IAM endpoints

The `/grading/entry` screen MUST resolve the assigned teacher's display name
from the academic-ops teacher profile and account-link status from
`teacher.user_id`. Linked account email/username MUST come from an academic-ops
linked-user projection of the IAM user, not from the teacher biodata
`teacher.email` field. The screen MUST NOT call any tenant-admin-gated IAM
endpoint such as `GET /api/v1/iam/tenants/me/users`. A non-admin teacher MUST be
able to use the screen without any request returning HTTP 403 due to a missing
`user.read` permission.

#### Scenario: Non-admin teacher loads grade entry without a 403

- **WHEN** a teacher who does not hold `user.read` opens `/grading/entry`
- **THEN** no request is made to `/iam/tenants/me/users` and the screen loads without a permission error

#### Scenario: Linked teacher identity is shown from projected IAM data

- **WHEN** the grade-entry screen displays an assigned teacher with `user_id`
- **THEN** the account label uses `linked_user.email` or `linked_user.username`
- **AND** it does not use the teacher biodata `email` field to decide linked status

#### Scenario: Linked teacher without projected identity uses fallback label

- **WHEN** the grade-entry screen displays an assigned teacher with `user_id` but no `linked_user`
- **THEN** it shows a linked-account fallback label rather than `(akun belum terhubung)`

#### Scenario: Unlinked teacher shows unlinked label

- **WHEN** the grade-entry screen displays an assigned teacher with no `user_id`
- **THEN** it shows `(akun belum terhubung)`
