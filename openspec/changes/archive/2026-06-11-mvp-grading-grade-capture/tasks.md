## 1. Roadmap & workspace prep

- [x] 1.1 Add the Grade Capture phase entry to `16_implementation_phases.md` (owning service `grading-service`, delivering change `mvp-grading-grade-capture`, depends on Academic Ops)
- [x] 1.2 Add `services/grading-service` to `apps/backend/Cargo.toml`
- [x] 1.3 Add `GRADING_DATABASE_URL` to `.env.example`; extend `docker-compose.yml` + `compose.test.yml`

## 2. Schema & migrations

- [x] 2.1 `V1__init.sql`: `grade` table per `10_data_design/06_Grading_Service_ERD.md` (+ `homeroom_id`, `recorded_by`, timestamps)
- [x] 2.2 Unique `(tenant_id, student_id, subject_id, academic_year_id)` on `grade`
- [x] 2.3 Projection tables: `teaching_authz`, `enrolled_student`, `valid_year`, `tenant_subscription_state`
- [x] 2.4 Indexes: `grade(homeroom_id, subject_id, academic_year_id)`, `grade(student_id, academic_year_id)`, `teaching_authz(teacher_user_id, subject_id, homeroom_id, academic_year_id)`
- [x] 2.5 `make migrate` / `make migrate-down`

## 3. Event projections (consumers)

- [x] 3.1 Consume `teacher.assigned` → upsert `teaching_authz` (resolve `teacher_user_id` by linked account where available)
- [x] 3.2 Consume `student.enrolled` → upsert `enrolled_student`
- [x] 3.3 Consume `academic_year.created` → upsert `valid_year`
- [x] 3.4 Consume `subscription.activated` → upsert `tenant_subscription_state`

## 4. Domain & repos (CQRS-separated)

- [x] 4.1 Domain types: `Grade`, `TeachingAuthz`, `EnrolledStudent`
- [x] 4.2 Authorization function `can_record_grade(teacher_user, student, subject, year)` joining the two projections + unit tests
- [x] 4.3 `can_edit_grade(student, year)` checkpoint stub returning true (filled by next change)
- [x] 4.4 Commands: `RecordGrade` (upsert), `UpdateGrade`
- [x] 4.5 Queries: `GetClassGrades` (homeroom+subject+year grid), `GetStudentGrades` (student+year)
- [x] 4.6 `GradeRepo` trait + SQLx impl; reads tenant-scoped from `AuthContext`

## 5. HTTP layer (`/api/v1/grading`)

- [x] 5.1 `POST /grades` — validate score range, enforce `can_record_grade`, upsert
- [x] 5.2 `PATCH /grades/{id}` — enforce `can_edit_grade` + authorization, update
- [x] 5.3 `GET /grades?homeroom_id=&subject_id=&academic_year_id=` — class grid
- [x] 5.4 `GET /students/{id}/grades?academic_year_id=` — per-student grades
- [x] 5.5 `GET /healthz`
- [x] 5.6 Wire entitlement middleware (`grading`) on write routes

## 6. Integration tests

- [x] 6.1 Assigned teacher records grade for an enrolled student → success
- [x] 6.2 Teacher records grade for a subject/class they are NOT assigned → 403 `NOT_ASSIGNED`
- [x] 6.3 Grade for a non-enrolled student → 422 `STUDENT_NOT_ENROLLED`
- [x] 6.4 Re-posting the same (student, subject, year) updates (idempotent), no duplicate row
- [x] 6.5 Score out of range rejected per-field
- [x] 6.6 Unlinked teacher account → `TEACHER_ACCOUNT_NOT_LINKED`
- [x] 6.7 Non-entitled tenant → 403 `FEATURE_NOT_AVAILABLE`

## 7. Web — grade entry

- [x] 7.1 Zod schema: grade entry (score)
- [x] 7.2 TanStack hooks: class grades, record/update grade
- [x] 7.3 `/grading/entry` — teacher picks assigned homeroom + subject; roster grid with per-row inline save (spinner); skeleton while loading
- [x] 7.4 Read-only / hidden for non-assigned classes; clear message when assignments still syncing

## 8. Cross-service e2e & wrap-up

- [x] 8.1 e2e: full chain register → year+subjects → students+homeroom+enroll+assign teacher → teacher logs in → records grades → reads back via `GET /students/{id}/grades`
- [x] 8.2 Playwright: teacher fills the grade grid for a class
- [x] 8.3 API contract `apis/grading-service-api.md` expanded for grade endpoints
- [x] 8.4 Update `01_repo_structure.md`
- [x] 8.5 `openspec validate mvp-grading-grade-capture --strict` green
