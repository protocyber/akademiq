## 1. Backend — academic-ops-service migration

- [x] 1.1 Create migration `V{next}__homeroom_teacher.sql`: `ALTER TABLE homeroom ADD COLUMN homeroom_teacher_id UUID NULL REFERENCES teacher(teacher_id) ON DELETE SET NULL`.
- [x] 1.2 Add index `homeroom_teacher_idx ON homeroom (tenant_id, homeroom_teacher_id)` for reverse-lookup (which class is a teacher walikelas of).

## 2. Backend — academic-ops-service command + event

- [x] 2.1 Extend `UpdateHomeroom` command struct to accept `homeroom_teacher_id: Option<Uuid>` (explicit `Some(null)` to clear, `None` to leave unchanged).
- [x] 2.2 In the command handler, validate that `homeroom_teacher_id` (if set) references a teacher belonging to the same tenant; return HTTP 422 `TEACHER_NOT_FOUND` otherwise.
- [x] 2.3 Emit `homeroom.updated` via outbox after a successful update; payload: `{ tenant_id, homeroom_id, academic_year_id, homeroom_teacher_id, homeroom_teacher_user_id }`. Resolve `teacher.user_id` from the teacher row at emit time (nullable).
- [x] 2.4 Update `GET /homerooms` and `GET /homerooms/{id}` responses to include `homeroom_teacher_id` (nullable).

## 3. Backend — grading-service migration + projection

- [x] 3.1 Create migration `V{next}__homeroom_teacher_authz.sql`: add `homeroom_teacher_authz (tenant_id, homeroom_id, teacher_user_id, academic_year_id, updated_at)` with PK `(tenant_id, homeroom_id, academic_year_id)`.
- [x] 3.2 Add `homeroom.updated` event consumer in `events.rs`: upsert `homeroom_teacher_authz` when `homeroom_teacher_user_id` is non-null; delete the row when null.
- [x] 3.3 Update `class_scope()` in `repo.rs` (~line 1501): replace the single `linked_assignment` query with two separate queries — `subject_teacher` from `teaching_authz` (unchanged), `homeroom_teacher` from `homeroom_teacher_authz`.
- [x] 3.4 Update `GradeRepository` trait and impl for the new `class_scope` signature if needed.

## 4. Backend — tests

- [x] 4.1 academic-ops: test that setting `homeroom_teacher_id` to a valid teacher persists and `homeroom.updated` is emitted with correct payload.
- [x] 4.2 academic-ops: test that setting `homeroom_teacher_id` to a teacher from another tenant returns HTTP 422.
- [x] 4.3 grading: test that consuming `homeroom.updated` with a `teacher_user_id` makes `class_scope().homeroom_teacher` return `true` for that user.
- [x] 4.4 grading: test that consuming `homeroom.updated` with `teacher_user_id: null` makes `class_scope().homeroom_teacher` return `false`.
- [x] 4.5 grading: test that a teacher with a subject assignment but NOT in `homeroom_teacher_authz` gets `homeroom_teacher: false` (proxy no longer used).
- [ ] 4.6 Run `cargo test -p academic-ops-service -p grading-service`. <!-- skipped: backend test execution — run manually -->

## 5. Frontend — homeroom edit form

- [x] 5.1 Add `homeroom_teacher_id?: string | null` to the `Homeroom` type in the web query types.
- [x] 5.2 Add `homeroom_teacher_id` to the homeroom update mutation body (`useUpdateHomeroom`).
- [x] 5.3 Add a "Wali Kelas" combobox/picker field to the homeroom edit modal (`homerooms-screen.tsx`) using the existing `useTeachers` data. Include a "Kosongkan" (clear) option.
- [x] 5.4 Display the walikelas name in the homeroom list table (new column or within the existing row), showing "Belum ditentukan" when null.
- [x] 5.5 Verify the picker is hidden/disabled for non-admin users (`canManage` gate already in place).

## 6. Verification

- [ ] 6.1 End-to-end: designate a teacher as walikelas → confirm grading projection updates → confirm that teacher can now approve rapor at HomeroomReview step.
- [ ] 6.2 Confirm a teacher with a teaching assignment but no walikelas designation is rejected at HomeroomApprove.
- [ ] 6.3 Run `cargo clippy` and `npm run lint` / `tsc` per `AGENTS.md`.

## Manual Backend Tests

Run to verify backend tasks:

```sh
cd apps/backend && cargo test -p academic-ops-service -p grading-service
```
