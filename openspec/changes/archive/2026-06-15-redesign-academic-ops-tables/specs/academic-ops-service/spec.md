## MODIFIED Requirements

### Requirement: Academic Ops service SHALL manage students, teachers, homerooms, enrollment, and teaching assignments under `/api/v1/academic-ops`

The service MUST provide tenant-scoped CRUD for students and teachers,
homeroom creation and roster listing, enrollment, and teaching assignment,
under `/api/v1/academic-ops`, following the standard API envelopes. All
resources MUST be scoped to the tenant from the JWT.

List endpoints for students, teachers, homerooms, and teaching assignments MUST
accept `search`, `sort`, `page`, and `page_size` query parameters and MUST
return a `{ data, meta: { page, page_size, total } }` envelope. `sort` MUST be
validated against a per-resource whitelist and an unknown value MUST be rejected
with HTTP 400 `INVALID_SORT`. `search` MUST match the resource's name field
(and NIS/NIP where present) case-insensitively.

#### Scenario: Student is created with a tenant-unique NIS

- **WHEN** a tenant admin POSTs `{ nis, full_name, gender, birth_date }` to `/students`
- **THEN** the response is HTTP 201 with the new student, and a second POST with the same `nis` for that tenant returns HTTP 409 `DUPLICATE_NIS`

#### Scenario: Homeroom roster lists actively enrolled students

- **WHEN** a tenant admin GETs `/homerooms/{id}/students`
- **THEN** the response lists exactly the students whose enrollment in that homeroom for its academic year has status `active`

#### Scenario: Student list returns a paginated envelope

- **WHEN** a tenant admin GETs `/students?search=budi&sort=-nis&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-ops list endpoint with `sort=` outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

## ADDED Requirements

### Requirement: Students, teachers, homerooms, and teaching assignments SHALL support delete, and teachers SHALL support edit

The service MUST expose teacher update (PATCH) and delete (single + bulk)
endpoints for students, teachers, homerooms, and teaching assignments, all
tenant-scoped from the JWT. Bulk delete MUST be all-or-nothing: it MUST
pre-validate every id and, on the first violation, reject the entire request
with no deletions.

- Student: `DELETE /students/{id}` MUST be rejected with HTTP 409
  `STUDENT_ENROLLED` when the student has an `active` enrollment.
- Teacher: `PATCH /teachers/{id}` MUST update NIP and full name; `DELETE` MUST be
  rejected with HTTP 409 `TEACHER_ASSIGNED` when a teaching assignment references
  the teacher. Deleting a teacher MUST NOT delete any linked login user.
- Homeroom: `DELETE /homerooms/{id}` MUST be rejected with HTTP 409
  `HOMEROOM_NOT_EMPTY` when it has active enrollments.
- Teaching assignment: `DELETE /teaching-assignments/{id}` MUST always succeed
  for an existing tenant-owned assignment.

#### Scenario: Editing a teacher updates it in place

- **WHEN** a tenant admin PATCHes `/teachers/{id}` with a new `{ nip, full_name }`
- **THEN** the response is HTTP 200 with the updated teacher and a subsequent list reflects the new values

#### Scenario: Deleting an enrolled student is rejected

- **WHEN** a tenant admin DELETEs a student who has an `active` enrollment
- **THEN** the response is HTTP 409 `STUDENT_ENROLLED` and the student is unchanged

#### Scenario: Deleting an assigned teacher is rejected and the login is untouched

- **WHEN** a tenant admin DELETEs a teacher referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ASSIGNED`, the teacher is unchanged, and any linked login user is unaffected

#### Scenario: Deleting a non-empty homeroom is rejected

- **WHEN** a tenant admin DELETEs a homeroom that still has active enrollments
- **THEN** the response is HTTP 409 `HOMEROOM_NOT_EMPTY` and the homeroom and its roster are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of student ids where one has an active enrollment
- **THEN** the response rejects the whole request with HTTP 409 `STUDENT_ENROLLED` and none of the students in the set are deleted
