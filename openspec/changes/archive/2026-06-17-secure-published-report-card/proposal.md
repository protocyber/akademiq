## Why

The published report-card endpoint (`GET /api/v1/grading/students/:student_id/report-card`) accepts an arbitrary `student_id` from the URL and only scopes the query by `tenant_id`. It never verifies that the requesting user owns or is the guardian of that student. The student/parent portal page even renders a free-text `student_id` input, so any authenticated tenant member can read any other student's report card by changing the ID. This is a broken-access-control vulnerability (IDOR). The real fix is blocked by missing data: there is no `user ↔ student` self-account link and no `guardian ↔ student` relation anywhere in the model.

## What Changes

- **BREAKING** Remove the free-`student_id` portal contract. Replace the unauthenticated-by-ownership endpoint with self/guardian-scoped endpoints:
  - `GET /api/v1/grading/me/report-cards` — lists the report cards the caller may see (self + linked children), resolved from `auth.user_id`. No client-supplied `student_id`.
  - `GET /api/v1/grading/me/report-cards/:student_id` — detail for one student, rejected with 403 unless `(auth.user_id, student_id)` exists in the authorization projection.
- Add a `student.user_id` self-account column and a many-to-many `guardian(tenant_id, user_id, student_id)` relation in academic-ops (one guardian ↔ many children, one child ↔ many guardians), mirroring the existing `teacher.user_id` link.
- Add academic-ops commands/endpoints to link a student account and add/remove guardians, emitting `student.account_linked`, `guardian.linked`, `guardian.unlinked` events.
- Add a `student_authz(tenant_id, student_id, user_id, relation)` projection in grading-service, fed by those events (mirrors the existing `teaching_authz` projection).
- Enforce `report.read` permission **and** an `student_authz` ownership match on the portal endpoints. Admin/principal continue to use the console endpoints (`get_report_card`), not the portal path.
- Update the web portal to remove the free-text `student_id` input and drive a server-controlled "pilih anak" (select child) flow; admin UI gains student-account and guardian linking (mirrors the teacher-account link UI).

## Capabilities

### New Capabilities
- `report-card-access-control`: Defines who may read a published report card (self, guardian, or privileged staff), the self/guardian-scoped portal endpoints, and the ownership-verification rules backed by the `student_authz` projection.
- `student-guardian-linking`: Defines the academic-ops `student.user_id` self-account link and the many-to-many `guardian` relation, their management commands/endpoints, and the domain events that propagate links to other services.

### Modified Capabilities
- `web-report-cards`: The student/parent portal no longer accepts a free `student_id`; it lists the caller's own/children's report cards from a server-scoped endpoint and selects among them.

## Impact

- **academic-ops-service**: new migration (`student.user_id` column + `guardian` table), new commands (`link_student_account`, `link_guardian`, `unlink_guardian`), new endpoints, new emitted events.
- **grading-service**: new migration (`student_authz` projection table), event consumers for the new events, new `me/report-cards` endpoints with `report.read` + ownership enforcement, restriction/removal of the legacy by-`student_id` published endpoint.
- **apps/web**: portal report-card page rewrite (remove free `student_id` input, add child selector), admin UI for student-account/guardian links, query hooks for the new endpoints.
- **Dependency**: this change is a prerequisite for the broader `report.read` RBAC work (Proposal A); the report portion of that work builds on the enforcement defined here.
- **Security**: closes an IDOR allowing cross-student report-card disclosure. Note a related gap (no parent↔student verification) is the root cause being fixed here.
