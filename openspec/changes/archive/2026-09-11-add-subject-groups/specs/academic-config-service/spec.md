## ADDED Requirements

### Requirement: The service SHALL expose subject groups scoped per curriculum version

The service MUST provide a `subject_group` resource scoped to
`(tenant_id, curriculum_version_id)` under
`/api/v1/academic-config/curriculum-versions/{curriculum_version_id}/subject-groups`,
following the success/error envelopes and tenant-from-JWT rule used by the other
academic-config resources. Each group MUST carry `name` (required), optional
`code`, and `position` (integer) used to order groups in report cards.

List endpoint MUST accept `search` (substring on `name` or `code`),
`sort` (whitelist: `name`, `-name`, `position`, `-position`, `created_at`,
`-created_at`), `page`, and `page_size` and MUST return the
`{ data, meta: { page, page_size, total } }` envelope. Unknown `sort` MUST be
rejected with HTTP 400 `INVALID_SORT`.

CRUD MUST mirror the existing resource pattern: create, update (name, code,
position), single delete, and all-or-nothing bulk delete. `DELETE` MUST be
rejected with HTTP 409 `SUBJECT_GROUP_IN_USE` when the group still has one or
more subjects; all-or-nothing bulk delete MUST pre-validate every id and reject
the whole set on the first violation.

#### Scenario: Creating a subject group for a curriculum version

- **WHEN** a tenant admin POSTs `{ name: "Kelompok A", code: "A", position: 2 }` to `/curriculum-versions/{id}/subject-groups`
- **THEN** the response is HTTP 201 with the created group envelope scoped to the caller's tenant and curriculum version

#### Scenario: Listing groups is paginated and sortable

- **WHEN** a tenant admin GETs `/curriculum-versions/{id}/subject-groups?sort=position&page=1&page_size=25`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page, page_size, total } }` ordered by position ascending

#### Scenario: Deleting a group that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a subject group that has one or more subjects
- **THEN** the response is HTTP 409 `SUBJECT_GROUP_IN_USE` and the group and its subjects are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of subject-group ids where one still has subjects
- **THEN** the response rejects the whole request with HTTP 409 `SUBJECT_GROUP_IN_USE` and none of the groups are deleted

### Requirement: A default subject group SHALL be auto-created with each curriculum version

When a curriculum version is created, the service MUST, in the same
transaction, insert exactly one `subject_group` whose `name` is the
`DEFAULT_SUBJECT_GROUP_NAME` constant (value `"Umum"`) and whose `position` is
`1`. The constant MUST be defined once in the service source and reused by both
the application code and the data migration so the default name is adjustable in
a single place.

#### Scenario: Creating a curriculum version also creates the default group

- **WHEN** a tenant admin creates a curriculum version
- **THEN** a subject group named "Umum" at position 1 exists for that curriculum version and a subsequent list of its groups returns exactly that one group

#### Scenario: The default group name is a single configurable constant

- **WHEN** the default group is created by the application or by the data migration backfill
- **THEN** both use the same `DEFAULT_SUBJECT_GROUP_NAME` constant value so the name can be changed in one place

## MODIFIED Requirements

### Requirement: Academic Config service SHALL expose year-scoped academic structure under `/api/v1/academic-config`

The service MUST provide endpoints for academic years, curriculum versions,
subject groups, subjects, grading policy, and class templates under the path
prefix `/api/v1/academic-config`, all following the success/error envelopes from
`13_engineering_standards/03_api_conventions.md`. Every resource MUST be
scoped to the tenant resolved from the JWT and MUST NOT read `tenant_id` from
the request body.

List endpoints for academic years, curriculum versions, subject groups,
subjects, and class templates MUST accept `search`, `sort`, `page`, and
`page_size` query parameters and MUST return a `{ data, meta: { page, page_size, total } }`
envelope. `sort` MUST be validated against a per-resource whitelist and an
unknown value MUST be rejected with HTTP 400 `INVALID_SORT`. `search` MUST match
the resource's primary name field (and code where present) case-insensitively.

#### Scenario: Academic year creation is tenant-scoped

- **WHEN** a tenant admin POSTs `{ name, start_date, end_date }` to `/api/v1/academic-config/academic-years` with a valid access token
- **THEN** the response is HTTP 201 with `data: { academic_year_id, name, start_date, end_date, status: "Planning" }` and the row is owned by the tenant from the JWT

#### Scenario: Listing returns only the caller's tenant data

- **WHEN** a tenant admin GETs `/api/v1/academic-config/academic-years`
- **THEN** the response contains only academic years owned by the tenant resolved from the JWT and never another tenant's years

#### Scenario: List returns a paginated envelope

- **WHEN** a tenant admin GETs `/api/v1/academic-config/academic-years?search=2026&sort=-name&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-config list endpoint with `sort=` set to a value outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

#### Scenario: Subject carries a passing grade validated on input

- **WHEN** a tenant admin POSTs a subject with `passing_grade` outside the allowed range to `/curriculum-versions/{id}/subjects`
- **THEN** the response is HTTP 400 with `{ "error": { "code": "VALIDATION_ERROR", "fields": { "passing_grade": ["..."] } } }`

### Requirement: Academic years, curriculum versions, subjects, and class templates SHALL support edit and delete

The service MUST expose update (PATCH) and delete (single + bulk) endpoints for
academic years, curriculum versions, subject groups, subjects, and class
templates, all tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing:
it MUST pre-validate every id and, on the first violation, reject the entire
request with no deletions.

- Academic year: `DELETE /academic-years/{id}` MUST be rejected with HTTP 409
  `ACTIVE_YEAR_IMMUTABLE` when the year is `Active`, and HTTP 409 `YEAR_IN_USE`
  when homerooms or teaching assignments reference it. The reference check uses
  a local usage projection built from the academic-ops `homeroom.created` and
  `teacher.assigned` events (see "Cross-service usage projection" below).
- Curriculum version: `PATCH /curriculum-versions/{id}` MUST update name and
  description; `DELETE` MUST be rejected with HTTP 409 `CURRICULUM_IN_USE` when
  the version still has subjects.
- Subject group: `PATCH /subject-groups/{id}` MUST update name, code, and
  position; `DELETE` MUST be rejected with HTTP 409 `SUBJECT_GROUP_IN_USE` when
  the group still has subjects.
- Subject: `PATCH /subjects/{id}` MUST update name, code, passing grade, and
  `subject_group_id`; `DELETE` MUST be rejected with HTTP 409 `SUBJECT_IN_USE`
  when a teaching assignment references it (same usage projection).
- Class template: `PATCH /class-templates/{id}` MUST update grade level and
  default capacity; `DELETE` MUST always succeed (templates are advisory).

#### Cross-service usage projection

The `YEAR_IN_USE` and `SUBJECT_IN_USE` guards depend on `homeroom` and
`teaching_assignment` data owned by the academic-ops service in a separate
database. Academic-config MUST consume the academic-ops `homeroom.created` and
`teacher.assigned` events into local `year_usage_ref` / `subject_usage_ref`
projection tables (idempotent on the source id) and the delete guards MUST
query those projections. Academic-ops MUST emit `homeroom.created`
(`tenant_id`, `homeroom_id`, `academic_year_id`) from its create-homeroom
command and MUST include `assignment_id` in the `teacher.assigned` payload so
each projection row keys idempotently. The `SUBJECT_GROUP_IN_USE` guard uses a
direct in-database subject count, not a projection.

#### Scenario: Editing a curriculum version updates it in place

- **WHEN** a tenant admin PATCHes `/curriculum-versions/{id}` with a new `{ name, description }`
- **THEN** the response is HTTP 200 with the updated version and a subsequent list reflects the new values

#### Scenario: Deleting an active academic year is rejected

- **WHEN** a tenant admin DELETEs an academic year whose status is `Active`
- **THEN** the response is HTTP 409 `ACTIVE_YEAR_IMMUTABLE` and the year is unchanged

#### Scenario: Deleting a curriculum version that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a curriculum version that has one or more subjects
- **THEN** the response is HTTP 409 `CURRICULUM_IN_USE` and the version and its subjects are unchanged

#### Scenario: Deleting a subject group that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a subject group that has one or more subjects
- **THEN** the response is HTTP 409 `SUBJECT_GROUP_IN_USE` and the group is unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of subject ids where one is referenced by a teaching assignment
- **THEN** the response rejects the whole request with HTTP 409 `SUBJECT_IN_USE` and none of the subjects in the set are deleted

#### Scenario: Bulk delete of all-deletable ids succeeds

- **WHEN** a tenant admin bulk-deletes class templates that all exist and belong to the tenant
- **THEN** the response is HTTP 200 and every template in the set is deleted in one transaction

## ADDED Requirements

### Requirement: A subject SHALL belong to exactly one subject group

The `subject` table MUST carry a non-null `subject_group_id` referencing a
`subject_group` in the same curriculum version. `POST /subjects` and
`PATCH /subjects/{id}` MUST accept `subject_group_id`; creating a subject
without it MUST be rejected with HTTP 400 `VALIDATION_ERROR` and a
`subject_group_id` field error. Moving a subject between groups via `PATCH`
MUST succeed when the target group belongs to the same curriculum version and
tenant; otherwise the response is HTTP 400 `VALIDATION_ERROR`.

Subject list and detail responses MUST include `subject_group_id` plus a group
summary `{ name, code, position }` so clients can group subjects without a
second round-trip.

#### Scenario: Creating a subject requires a group

- **WHEN** a tenant admin POSTs a subject without `subject_group_id`
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` with a `subject_group_id` field error and no subject is created

#### Scenario: Subject response carries its group

- **WHEN** a tenant admin GETs `/curriculum-versions/{id}/subjects`
- **THEN** each subject in `data` includes `subject_group_id` and a `subject_group` summary with `name`, `code`, and `position`

#### Scenario: Moving a subject to a group in another curriculum version is rejected

- **WHEN** a tenant admin PATCHes a subject with a `subject_group_id` from a different curriculum version
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` and the subject's group is unchanged
