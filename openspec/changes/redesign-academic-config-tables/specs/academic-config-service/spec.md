## MODIFIED Requirements

### Requirement: Academic Config service SHALL expose year-scoped academic structure under `/api/v1/academic-config`

The service MUST provide endpoints for academic years, curriculum versions,
subjects, grading policy, and class templates under the path prefix
`/api/v1/academic-config`, all following the success/error envelopes from
`13_engineering_standards/03_api_conventions.md`. Every resource MUST be
scoped to the tenant resolved from the JWT and MUST NOT read `tenant_id` from
the request body.

List endpoints for academic years, curriculum versions, subjects, and class
templates MUST accept `search`, `sort`, `page`, and `page_size` query
parameters and MUST return a `{ data, meta: { page, page_size, total } }`
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

## ADDED Requirements

### Requirement: Academic years, curriculum versions, subjects, and class templates SHALL support edit and delete

The service MUST expose update (PATCH) and delete (single + bulk) endpoints for
academic years, curriculum versions, subjects, and class templates, all
tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing: it MUST
pre-validate every id and, on the first violation, reject the entire request
with no deletions.

- Academic year: `DELETE /academic-years/{id}` MUST be rejected with HTTP 409
  `ACTIVE_YEAR_IMMUTABLE` when the year is `Active`, and HTTP 409 `YEAR_IN_USE`
  when homerooms or teaching assignments reference it. The reference check uses
  a local usage projection built from the academic-ops `homeroom.created` and
  `teacher.assigned` events (see "Cross-service usage projection" below).
- Curriculum version: `PATCH /curriculum-versions/{id}` MUST update name and
  description; `DELETE` MUST be rejected with HTTP 409 `CURRICULUM_IN_USE` when
  the version still has subjects.
- Subject: `PATCH /subjects/{id}` MUST update name, code, and passing grade;
  `DELETE` MUST be rejected with HTTP 409 `SUBJECT_IN_USE` when a teaching
  assignment references it (same usage projection).
- Class template: `PATCH /class-templates/{id}` MUST update grade level and
  default capacity; `DELETE` MUST always succeed (templates are advisory).

### Cross-service usage projection

The `YEAR_IN_USE` and `SUBJECT_IN_USE` guards depend on `homeroom` and
`teaching_assignment` data owned by the academic-ops service in a separate
database. Academic-config MUST consume the academic-ops `homeroom.created` and
`teacher.assigned` events into local `year_usage_ref` / `subject_usage_ref`
projection tables (idempotent on the source id) and the delete guards MUST
query those projections. Academic-ops MUST emit `homeroom.created`
(`tenant_id`, `homeroom_id`, `academic_year_id`) from its create-homeroom
command and MUST include `assignment_id` in the `teacher.assigned` payload so
each projection row keys idempotently.

#### Scenario: Editing a curriculum version updates it in place

- **WHEN** a tenant admin PATCHes `/curriculum-versions/{id}` with a new `{ name, description }`
- **THEN** the response is HTTP 200 with the updated version and a subsequent list reflects the new values

#### Scenario: Deleting an active academic year is rejected

- **WHEN** a tenant admin DELETEs an academic year whose status is `Active`
- **THEN** the response is HTTP 409 `ACTIVE_YEAR_IMMUTABLE` and the year is unchanged

#### Scenario: Deleting a curriculum version that still has subjects is rejected

- **WHEN** a tenant admin DELETEs a curriculum version that has one or more subjects
- **THEN** the response is HTTP 409 `CURRICULUM_IN_USE` and the version and its subjects are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of subject ids where one is referenced by a teaching assignment
- **THEN** the response rejects the whole request with HTTP 409 `SUBJECT_IN_USE` and none of the subjects in the set are deleted

#### Scenario: Bulk delete of all-deletable ids succeeds

- **WHEN** a tenant admin bulk-deletes class templates that all exist and belong to the tenant
- **THEN** the response is HTTP 200 and every template in the set is deleted in one transaction
