## ADDED Requirements

### Requirement: The academic-ops service SHALL store a designated walikelas per homeroom

The `homeroom` entity MUST carry a nullable `homeroom_teacher_id` referencing a
`teacher` in the same tenant. An admin MUST be able to set or clear the
walikelas via the `PATCH /homerooms/{id}` endpoint. When a teacher referenced as
walikelas is deleted, the homeroom's `homeroom_teacher_id` MUST be set to `NULL`
(ON DELETE SET NULL). At most one teacher may be the walikelas of a given
homeroom at a time.

#### Scenario: Admin designates a teacher as walikelas

- **WHEN** an admin PATCHes `/homerooms/{id}` with `{ "homeroom_teacher_id": "<teacher_id>" }`
- **THEN** the response carries the updated homeroom with `homeroom_teacher_id` set and a `homeroom.updated` event is emitted

#### Scenario: Admin clears the walikelas

- **WHEN** an admin PATCHes `/homerooms/{id}` with `{ "homeroom_teacher_id": null }`
- **THEN** `homeroom_teacher_id` is cleared and a `homeroom.updated` event is emitted

#### Scenario: Teacher from another tenant is rejected

- **WHEN** an admin PATCHes with a `homeroom_teacher_id` that does not belong to the tenant
- **THEN** the response is HTTP 404 or HTTP 422 and `homeroom_teacher_id` is unchanged

#### Scenario: Deleting a walikelas clears the designation

- **WHEN** the teacher designated as walikelas of a homeroom is deleted
- **THEN** `homeroom_teacher_id` on that homeroom becomes `NULL` automatically

### Requirement: The academic-ops service SHALL emit a homeroom.updated event when a homeroom is modified

The service MUST emit a `homeroom.updated` event via the outbox whenever a
homeroom's attributes change (including `homeroom_teacher_id`). The payload MUST
include `tenant_id`, `homeroom_id`, `academic_year_id`, `homeroom_teacher_id`
(nullable), and `homeroom_teacher_user_id` (nullable — the IAM `user_id` linked
to that teacher at emit time).

#### Scenario: homeroom.updated carries teacher_user_id

- **WHEN** a homeroom is updated with a designated teacher who has a linked IAM user
- **THEN** the `homeroom.updated` event payload includes both `homeroom_teacher_id` and `homeroom_teacher_user_id`

#### Scenario: homeroom.updated with no walikelas carries nulls

- **WHEN** a homeroom is updated and `homeroom_teacher_id` is NULL
- **THEN** the event payload carries `homeroom_teacher_id: null` and `homeroom_teacher_user_id: null`

### Requirement: The grading service SHALL maintain a homeroom_teacher_authz projection

The grading service MUST consume `homeroom.updated` events and upsert a
`homeroom_teacher_authz` row keyed by `(tenant_id, homeroom_id, academic_year_id)`,
storing the `teacher_user_id`. This projection MUST be used exclusively by
`class_scope()` to determine `homeroom_teacher: true/false` — the teaching
assignment proxy MUST NOT be used for this purpose.

#### Scenario: Projection is updated on homeroom.updated

- **WHEN** grading consumes a `homeroom.updated` event with a non-null `homeroom_teacher_user_id`
- **THEN** `homeroom_teacher_authz` has an upserted row for that homeroom and `class_scope().homeroom_teacher` returns `true` for that user

#### Scenario: Clearing walikelas removes the authorization

- **WHEN** grading consumes a `homeroom.updated` event with `homeroom_teacher_user_id: null`
- **THEN** `homeroom_teacher_authz` row is deleted (or teacher_user_id set null) and `class_scope().homeroom_teacher` returns `false` for the former walikelas user

### Requirement: The web app SHALL provide a walikelas picker in the homeroom edit form

The homeroom edit form MUST include a teacher picker field labeled "Wali Kelas"
that lists all teachers in the tenant. Selecting a teacher sets
`homeroom_teacher_id`; clearing it sets the field to null. The picker MUST be
available only to admins with the academic ops write permission. The homeroom
list/detail MUST display the designated walikelas name when set.

#### Scenario: Admin sets walikelas from the homeroom edit form

- **WHEN** an admin opens the homeroom edit modal, picks a teacher as Wali Kelas, and saves
- **THEN** the homeroom row shows the teacher's name as Wali Kelas and the designation persists on reload

#### Scenario: Walikelas column shows unset state

- **WHEN** a homeroom has no designated walikelas
- **THEN** the homeroom list shows a "Belum ditentukan" or empty indicator in the Wali Kelas column
