## 1. academic-ops: data model for student/guardian links

- [x] 1.1 Add migration: `ALTER TABLE student ADD COLUMN user_id UUID` + unique index `student_tenant_user_uidx` on `(tenant_id, user_id) WHERE user_id IS NOT NULL` (mirror `V2__link_teacher_user.sql`)
- [x] 1.2 Add migration: `CREATE TABLE guardian (tenant_id UUID, user_id UUID, student_id UUID, created_at TIMESTAMPTZ, PRIMARY KEY (tenant_id, user_id, student_id))` + index on `(tenant_id, student_id)`
- [x] 1.3 Update `domain.rs` student struct to carry `user_id: Option<Uuid>`; update repo read/write SQL accordingly
- [x] 1.4 Add `Guardian` domain struct and a `GuardianRepo` (list, insert, delete) with idempotent insert (409 on exact dup) and tenant-scoped queries

## 2. academic-ops: commands, endpoints, events

- [x] 2.1 Add `link_student_account(state, LinkTeacherAccount-like)` command setting `student.user_id`; reject unique violation with `STUDENT_USER_ALREADY_LINKED`; emit `student.account_linked{tenant_id, student_id, user_id}` via outbox
- [x] 2.2 Add `link_guardian` / `unlink_guardian` commands over `GuardianRepo`; emit `guardian.linked` / `guardian.unlinked{tenant_id, user_id, student_id}` via outbox
- [x] 2.3 Register the events in the IAM-style event-name constants and any outbox type registry used by `commands.rs`
- [x] 2.4 Add routes: `PATCH /api/v1/academic-ops/students/:student_id/account` and `POST /students/:id/guardians` / `DELETE /students/:id/guardians/:user_id`, all behind `AcademicOpsEntitlement` and resolving `tenant_id` from `auth`
- [x] 2.5 Add integration tests in `services/academic-ops-service/tests/integration.rs` covering the self-link (incl. dup-user 409), guardian add (M:N both directions), guardian remove, and feature/subscription gating

## 3. grading: `student_authz` projection

- [x] 3.1 Add migration creating `student_authz (tenant_id UUID, student_id UUID, user_id UUID, relation VARCHAR(16), PRIMARY KEY(tenant_id, student_id, user_id))` with indexes on `(tenant_id, user_id)` and `(tenant_id, student_id)`; `relation` constrained to `self`/`guardian`
- [x] 3.2 Add payload structs and match arms in `events.rs` for `student.account_linked` (upsert `relation='self'`), `guardian.linked` (upsert `relation='guardian'`), `guardian.unlinked` (delete the row) — mirror the `teaching_authz` consumer
- [x] 3.3 Add `student_authz` upsert/delete methods on the projection repo; wire them through `events.rs` into the existing consumer loop on queue `grading.projections`
- [x] 3.4 Add an integration test that plays the three events and asserts the projection rows

## 4. grading: portal endpoints + ownership enforcement

- [x] 4.1 Add `GET /api/v1/grading/me/report-cards?academic_year_id=` handler: require `report.read` (or temporary role gate per design D4), resolve all `student_authz` rows for `auth.user_id`, return published/archived cards only
- [x] 4.2 Add `GET /api/v1/grading/me/report-cards/:student_id?academic_year_id=` handler: verify `(auth.user_id, student_id)` exists in `student_authz` (else 403), return published/archived card else 404 for pre-publish
- [x] 4.3 Restrict/remove the legacy `GET /api/v1/grading/students/:student_id/report-card`: keep it console-admin/principal only or delete it outright (confirm with design D3)
- [x] 4.4 Add integration tests: guardian with multiple children; detail for owned child; 403 for non-owned; 404 for pre-publish; `report.read`/gate behavior

## 5. web: portal rewrite (remove free-text id)

- [x] 5.1 Add query hooks `useMyReportCards(academicYearId?)` and `useMyReportCardDetail(studentId, academicYearId)` against the new `/me/report-cards` endpoints
- [x] 5.2 Rewrite `/portal/report-card/page.tsx`: remove the free-text `student_id` input; load the caller's student list and render a "Pilih anak" selector; fetch detail on selection; show a not-allowed state for a non-owned deep link
- [x] 5.3 Add an empty state ("belum ada siswa terhubung") when the caller has no `student_authz` rows
- [x] 5.4 Add a portal test (vitest/playwright) asserting no free-text `student_id` input renders and a guardian sees only their children

## 6. web: admin link UIs

- [x] 6.1 Add a "Tautkan Akun" action on the students screen (and/or detail) calling `PATCH /students/:id/account`, mirroring the teacher-account link UI
- [x] 6.2 Add a guardians manager on the student detail (add/remove guardian by user) calling the new endpoints
- [x] 6.3 Add query/mutation hooks and error messages for the link flows; respect `academic_ops` feature gating and centralized error handling per `apps/web/CONVENTIONS.md`

## 7. Integration & validation

- [x] 7.1 Add the `student.account_linked`, `guardian.linked`, `guardian.unlinked` event contracts under `docs/internal/11_integration_contracts/events/`
- [x] 7.2 Run `make test` across both submodules and `make test-e2e` for the cross-service link→projection→portal flow
- [x] 7.3 Update `docs/internal/` (sequence/component) with the new ownership-verification flow if a relevant diagram exists
