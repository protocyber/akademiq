## MODIFIED Requirements

### Requirement: Academic Ops service SHALL manage students, teachers, homerooms, enrollment, teaching assignments, and family profiles under `/api/v1/academic-ops`

The service MUST provide tenant-scoped CRUD for students, teachers, family profiles,
student-family links, homeroom creation and roster listing, enrollment, and teaching
assignment, under `/api/v1/academic-ops`, following the standard API envelopes. All
resources MUST be scoped to the tenant from the JWT.

Student profiles MUST support complete administrative biodata including NIS, NISN,
NIK, full name, gender, birth date, birth place, address, phone number, photo
reference, religion, nationality, child order, sibling count, entry date, origin
school, status, archive reason, and optional linked IAM user id. Teacher profiles
MUST support NIP, NIK, full name, education level, gender, birth date, birth place,
address, phone number, photo reference, email, employment status, role/position,
start date, end date, primary subject area, NUPTK, certification number, status,
archive reason, and optional linked IAM user id.

Student and teacher profile contact fields MUST be administrative data and MUST NOT
be automatically synchronized with linked IAM user email or phone fields. Student
master data MUST NOT store current class as authoritative state; class placement
MUST remain represented by enrollment records.

List endpoints for students, teachers, family profiles, homerooms, and teaching
assignments MUST accept `search`, `sort`, `page`, and `page_size` query parameters
and MUST return a `{ data, meta: { page, page_size, total } }` envelope. `sort`
MUST be validated against a per-resource whitelist and an unknown value MUST be
rejected with HTTP 400 `INVALID_SORT`. `search` MUST match the resource's name
field and relevant identifiers case-insensitively.

#### Scenario: Student is created with complete biodata and optional placement

- **WHEN** a tenant admin POSTs valid student biodata and optional initial `{ academic_year_id, homeroom_id }` placement data to `/students`
- **THEN** the response is HTTP 201 with the new student profile, and placement is attempted through enrollment rather than stored as a current class field on the student

#### Scenario: Initial placement failure keeps student profile

- **WHEN** student biodata is valid but the optional initial enrollment fails
- **THEN** the student profile remains created and the response or subsequent UI state identifies the student as not yet placed in a class

#### Scenario: Student is created with a tenant-unique NIS

- **WHEN** a tenant admin POSTs student biodata with a `nis` already used by another non-deleted student in the same tenant
- **THEN** the response is HTTP 409 with code `DUPLICATE_NIS`

#### Scenario: Teacher profile can exist without login account

- **WHEN** a tenant admin creates a teacher profile without a linked IAM user id
- **THEN** the profile is stored and no IAM user account is created

#### Scenario: Profile and IAM contact data may differ

- **WHEN** a student, teacher, or family profile is linked to an IAM user
- **THEN** profile email and phone data remain independent from the IAM user's login email and account data

#### Scenario: Homeroom roster lists actively enrolled students

- **WHEN** a tenant admin GETs `/homerooms/{id}/students`
- **THEN** the response lists exactly the students whose enrollment in that homeroom for its academic year has status `active`

#### Scenario: Student list returns a paginated envelope

- **WHEN** a tenant admin GETs `/students?search=budi&sort=-nis&page=1&page_size=20`
- **THEN** the response is HTTP 200 with `{ data: [...], meta: { page: 1, page_size: 20, total } }`, the rows match the search and sort, and `total` reflects the full filtered count regardless of page

#### Scenario: Unknown sort key is rejected

- **WHEN** a tenant admin GETs any academic-ops list endpoint with `sort=` outside that resource's whitelist
- **THEN** the response is HTTP 400 with code `INVALID_SORT` and no rows are returned

### Requirement: Students, teachers, family profiles, homerooms, and teaching assignments SHALL support archive/soft-delete behavior, and teachers SHALL support edit

The service MUST expose update, archive/nonactive, and soft-delete behavior for
students, teachers, and family profiles, and delete behavior for homerooms and
teaching assignments, all tenant-scoped from the JWT. Soft-deleted records MUST be
hidden from default lists. Restore UI is out of scope for this change.

Student, teacher, and family profile lifecycle state MUST distinguish active use
from archived/nonactive records. Teacher status values MUST include `aktif`,
`nonaktif`, and `arsip`, with archive reasons `nonaktif_sementara`, `resign`,
`mutasi`, `pensiun`, `meninggal`, and `lainnya`. Student status values MUST include
`aktif`, `nonaktif`, and `arsip`, with archive reasons `nonaktif_sementara`,
`lulus`, `pindah`, `keluar`, `meninggal`, and `lainnya`.

Bulk destructive operations MUST be all-or-nothing: they MUST pre-validate every id
and, on the first violation, reject the entire request with no changes.

- Student: destructive delete MUST be rejected with HTTP 409 `STUDENT_ENROLLED` when the student has an `active` enrollment.
- Teacher: updating MUST support the richer teacher profile fields. Destructive delete MUST be rejected with HTTP 409 `TEACHER_ASSIGNED` when a teaching assignment references the teacher. Deleting or archiving a teacher MUST NOT delete any linked login user.
- Homeroom: destructive delete MUST be rejected with HTTP 409 `HOMEROOM_NOT_EMPTY` when it has active enrollments.
- Teaching assignment: delete MUST always succeed for an existing tenant-owned assignment.

#### Scenario: Editing a teacher updates it in place

- **WHEN** a tenant admin PATCHes `/teachers/{id}` with valid profile fields
- **THEN** the response is HTTP 200 with the updated teacher and a subsequent list reflects the new values

#### Scenario: Archiving a teacher records reason

- **WHEN** a tenant admin archives a teacher with reason `resign`
- **THEN** the teacher status becomes `arsip`, the reason is stored, and any linked IAM user remains unchanged

#### Scenario: Archiving a student records academic reason

- **WHEN** a tenant admin archives a student with reason `lulus`
- **THEN** the student status becomes `arsip`, the reason is stored, and enrollment history remains intact

#### Scenario: Deleting an enrolled student is rejected

- **WHEN** a tenant admin destructively deletes a student who has an `active` enrollment
- **THEN** the response is HTTP 409 `STUDENT_ENROLLED` and the student is unchanged

#### Scenario: Deleting an assigned teacher is rejected and the login is untouched

- **WHEN** a tenant admin destructively deletes a teacher referenced by a teaching assignment
- **THEN** the response is HTTP 409 `TEACHER_ASSIGNED`, the teacher is unchanged, and any linked login user is unaffected

#### Scenario: Deleting a non-empty homeroom is rejected

- **WHEN** a tenant admin DELETEs a homeroom that still has active enrollments
- **THEN** the response is HTTP 409 `HOMEROOM_NOT_EMPTY` and the homeroom and its roster are unchanged

#### Scenario: Bulk delete is all-or-nothing

- **WHEN** a tenant admin bulk-deletes a set of student ids where one has an active enrollment
- **THEN** the response rejects the whole request with HTTP 409 `STUDENT_ENROLLED` and none of the students in the set are deleted
