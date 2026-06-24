## 1. Migration + projection enrichment
- [x] 1.1 Add migration: `ALTER TABLE enrolled_student ADD COLUMN full_name TEXT, ADD COLUMN nis TEXT` (nullable)
- [x] 1.2 Confirm whether the `student.enrolled` event payload currently carries `full_name`/`nis`; if not, coordinate extending it (additive) with the academic-ops producer and update `docs/internal/11_integration_contracts/events/`
- [x] 1.3 Enrich the `student.enrolled` handler in `events.rs` to persist `full_name`/`nis` into `enrolled_student`
- [x] 1.4 Add handling for the student profile-update event (existing or new) to refresh `full_name`/`nis` in the projection; document the event name
- [x] 1.5 Update the projection upsert SQL (`upsert_enrolled_student`) to write the new columns

## 2. Backend — roster endpoint
- [x] 2.1 Extend `active_students_for_homeroom` in `repo.rs` to return `(student_id, full_name, nis)` rows instead of bare `Uuid`
- [x] 2.2 Add `GET /api/v1/grading/homerooms/{homeroom_id}/roster` route + handler in `http.rs`, with `academic_year_id` query param and `grade.read` permission guard
- [x] 2.3 Add the query in `queries.rs` returning the roster shape `{ student_id, full_name, nis }`
- [x] 2.4 Add a backend test asserting roster == submittable set (a student in the roster passes the write check; one absent fails)
- [x] 2.5 Add the endpoint to the API contract docs

## 3. Frontend — switch entry roster to grading + syncing state
- [x] 3.1 Add `useGradingRoster(homeroomId, yearId)` in `use-grading.ts` calling the new grading endpoint
- [x] 3.2 Switch `GradeEntryPanel` (`grading/entry/page.tsx`) from `useHomeroomRoster` to `useGradingRoster`
- [x] 3.3 Update the empty-state: distinguish "syncing" (grading roster empty) with "Roster kelas sedang tersinkronisasi" messaging
- [x] 3.4 Keep the academic-ops roster hook for any non-grading consumers (do not delete)
- [x] 3.5 Add a frontend test: roster sourced from grading; empty roster shows syncing state

## 4. Verification
- [x] 4.1 Repro the original scenario: a student formerly showing but failing `STUDENT_NOT_ENROLLED` now either submits successfully or is not shown until synced
- [x] 4.2 Confirm roster rows and write check agree across enroll/unenroll/rename
- [ ] 4.3 Run `make test` in both submodules; run web lint/typecheck
