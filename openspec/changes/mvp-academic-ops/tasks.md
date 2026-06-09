## 1. Workspace & roadmap prep

- [ ] 1.1 Flip Phase 3 in `16_implementation_phases.md` from ⏳ to 🚧, delivering change `mvp-academic-ops`
- [ ] 1.2 Add `services/academic-ops-service` to `apps/backend/Cargo.toml`
- [ ] 1.3 Add `ACADEMIC_OPS_DATABASE_URL` to `.env.example`; extend `docker-compose.yml` + `compose.test.yml`
- [ ] 1.4 Add an Excel parsing crate (e.g. `calamine`) to `[workspace.dependencies]`

## 2. Schema & migrations

- [ ] 2.1 `V1__init.sql`: `student`, `teacher`, `homeroom`, `enrollment`, `teaching_assignment`, `timetable`, `known_academic_year`, `tenant_subscription_state` per `10_data_design/04_Academic_Operations_ERD.md`
- [ ] 2.2 Unique `(tenant_id, nis)` on student, `(tenant_id, nip)` on teacher
- [ ] 2.3 Partial unique active-enrollment index on `enrollment(student_id, academic_year_id) WHERE status='active'`
- [ ] 2.4 Unique `(teacher_id, subject_id, homeroom_id, academic_year_id)` on teaching_assignment
- [ ] 2.5 `make migrate` / `make migrate-down` targets

## 3. Event projections (consumers)

- [ ] 3.1 Consume `academic_year.created` → upsert `known_academic_year`
- [ ] 3.2 Consume `subscription.activated` → upsert `tenant_subscription_state`
- [ ] 3.3 Homeroom creation checks `known_academic_year` is present + active; writes gated by active subscription

## 4. Domain & repos (CQRS-separated)

- [ ] 4.1 Domain types: `Student`, `Teacher`, `Homeroom`, `Enrollment` (+ status), `TeachingAssignment`, `Timetable`
- [ ] 4.2 Commands: `CreateStudent`, `UpdateStudent`, `CreateTeacher`, `CreateHomeroom`, `EnrollStudent`, `TransferEnrollment`, `UnenrollStudent`, `AssignTeaching`
- [ ] 4.3 Queries: `ListStudents`, `GetStudent`, `ListTeachers`, `ListHomerooms`, `GetHomeroomRoster`, `ListTeachingAssignments`
- [ ] 4.4 Repository traits + SQLx impls; all reads tenant-scoped from `AuthContext`
- [ ] 4.5 Single-active-enrollment rule enforced in `EnrollStudent`/`TransferEnrollment` (transaction) + unit tests

## 5. HTTP layer (`/api/v1/academic-ops`)

- [ ] 5.1 Students: `POST`, `GET`, `GET /{id}`, `PATCH /{id}` (validate NIS, gender, birth date)
- [ ] 5.2 Teachers: `POST`, `GET`, `GET /{id}` (validate NIP)
- [ ] 5.3 Homerooms: `POST` (validate year active), `GET`, `GET /{id}/students`
- [ ] 5.4 Enrollment: `POST /enrollments`, `DELETE /enrollments/{id}`
- [ ] 5.5 Teaching assignments: `POST`, `GET /homerooms/{id}/teaching-assignments`
- [ ] 5.6 `GET /healthz`
- [ ] 5.7 Wire entitlement middleware (`academic_ops`) on all write routes

## 6. Excel import

- [ ] 6.1 `POST /imports/students` — parse template, validate all rows, all-or-nothing insert in one transaction
- [ ] 6.2 `POST /imports/teachers` — same pattern
- [ ] 6.3 Row-level error report shape: `422 { "error": { "code": "IMPORT_VALIDATION_FAILED" }, "rows": [{ "row": N, "errors": {...} }] }`
- [ ] 6.4 Provide a downloadable template (static asset or documented columns)

## 7. Event emission

- [ ] 7.1 Emit `student.enrolled` on successful enrollment (align with existing `events/student-enrolled.md`)
- [ ] 7.2 Emit `teacher.assigned` carrying `{ tenant_id, teacher_id, subject_id, homeroom_id, academic_year_id }`
- [ ] 7.3 Outbox drain (reuse phase-1 pattern); document `teacher.assigned` event contract

## 8. Integration tests

- [ ] 8.1 Create student/teacher happy paths; duplicate NIS/NIP rejected
- [ ] 8.2 Enroll student; second active enrollment in same year rejected; transfer marks old `transferred`
- [ ] 8.3 Homeroom creation rejected when year unknown/inactive
- [ ] 8.4 Teaching assignment happy path; duplicate tuple rejected
- [ ] 8.5 Import: valid sheet imports N rows; sheet with one bad row imports nothing and returns row errors
- [ ] 8.6 Non-entitled tenant → 403 `FEATURE_NOT_AVAILABLE`
- [ ] 8.7 `student.enrolled` and `teacher.assigned` land on RabbitMQ with documented payloads

## 9. Web — operational pages

- [ ] 9.1 Zod schemas: student, teacher, homeroom, enrollment, teaching-assignment
- [ ] 9.2 TanStack hooks for each resource + import
- [ ] 9.3 `/students` — list (skeleton) + create/edit (spinner)
- [ ] 9.4 `/teachers` — list + create
- [ ] 9.5 `/homerooms` — list + create + roster view + enroll dialog
- [ ] 9.6 `/teaching-assignments` — assign teacher↔subject↔homeroom
- [ ] 9.7 `/import` — upload, show row-level errors, success summary
- [ ] 9.8 Non-entitled tenant: disabled controls + upgrade tooltip

## 10. Cross-service e2e & wrap-up

- [ ] 10.1 e2e: register tenant → create year + subjects (phase 2) → add students/teachers → create homeroom → enroll → assign teacher
- [ ] 10.2 e2e: failing import rolls back and surfaces row errors
- [ ] 10.3 Playwright: full operational walkthrough incl. import error display
- [ ] 10.4 API contract `apis/academic-operations-api.md` filled out
- [ ] 10.5 Update `01_repo_structure.md`
- [ ] 10.6 `openspec validate mvp-academic-ops --strict` green
