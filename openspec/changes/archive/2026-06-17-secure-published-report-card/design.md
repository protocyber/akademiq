## Context

The published report-card endpoint `GET /api/v1/grading/students/{student_id}/report-card`
(`grading-service/src/http.rs:678`) takes `student_id` from the URL and scopes the
query only by `tenant_id` resolved from the JWT. It performs no ownership check, so any
authenticated tenant member can read any student's published report card by changing the
id (IDOR). The portal page (`apps/web/src/app/portal/report-card/page.tsx:35`) makes this
trivial by rendering a free-text `student_id` input.

The proper fix is blocked by a missing data model: nothing links an IAM user to a student
(self-account) or to a student as guardian. The teacher side already solves the analogous
problem — `teacher.user_id` (migration `V2__link_teacher_user.sql`) flows via the
`teacher.assigned` event into the grading `teaching_authz` projection, which authorizes
teachers for their own classes. We will mirror that pattern for students/guardians.

Relevant existing pieces:
- academic-ops emits `student.enrolled`, `teacher.assigned`, etc. via an outbox
  (`commands.rs`); grading consumes them in `events.rs` and upserts projections in
  `repo.rs` (`teaching_authz`, `enrolled_student`).
- `link_teacher_account` (`commands.rs:271`) sets `teacher.user_id` directly and does not
  emit its own event — the user id rides along on `teacher.assigned`.
- Permissions are platform-owned (IAM `V11`/`V12` seeds). `report.read` does not yet
  exist; it is introduced by the broader RBAC change (Proposal A) that depends on this one.

## Goals / Non-Goals

**Goals:**
- Close the IDOR: a user can only read report cards for themselves or their linked children.
- Add the minimum data model to express `user ↔ student` (self) and `user ↔ student`
  (guardian, many-to-many) relations.
- Provide self/guardian-scoped portal endpoints that do not trust a client-supplied
  `student_id` as the access authority.
- Keep the projection-based service boundary: grading authorizes from a local
  `student_authz` projection, never by reaching into academic-ops data.

**Non-Goals:**
- Defining the `report.read` permission and its seeding/grants — owned by Proposal A.
  This change assumes `report.read` exists and gates the new endpoints on it; if Proposal
  A is not yet merged, the gate can be a temporary role check, swapped later.
- Self-service account creation / invitation flow for students and guardians (out of scope;
  links are created by admins from existing IAM users).
- The console admin report board (`/grading/report-cards/...`) — unchanged; admins/principal
  keep using the console path, not the portal endpoints.

## Decisions

### D1: Self-account via `student.user_id`, guardians via a `guardian` table
Mirror `teacher.user_id` with a nullable `student.user_id` (unique per tenant where not
null). Guardians are a separate `guardian(tenant_id, user_id, student_id)` table because
the relation is many-to-many (a parent with several children; a child with two parents).
A single `student.user_id` cannot express M:N, so the table is required.

_Alternative considered_: a single polymorphic `student_account(user_id, student_id,
relation)` table covering both self and guardian. Rejected to keep the self-link symmetric
with the teacher precedent and to enforce the "one self-account per student" constraint
with a simple column + unique index.

### D2: Authorization via a grading-local `student_authz` projection
Add `student_authz(tenant_id, student_id, user_id, relation)` to grading, populated by
consuming `student.account_linked`, `guardian.linked`, and `guardian.unlinked`. This keeps
authorization decisions inside grading (no cross-service synchronous calls) and matches the
existing `teaching_authz` pattern.

_Alternative considered_: have grading call academic-ops synchronously to check ownership.
Rejected — violates the repo's projection-based communication rule and adds a runtime
dependency on another service for every portal read.

### D3: Portal endpoints resolve identity from the JWT, not the path
- `GET /me/report-cards` returns the caller's authorized cards by looking up all
  `student_authz` rows for `auth.user_id`.
- `GET /me/report-cards/{student_id}` validates `(auth.user_id, student_id)` is in
  `student_authz` before returning; otherwise 403. A pre-publish card returns 404 to avoid
  leaking existence.
The legacy `GET /students/{student_id}/report-card` is removed from the portal contract
(restricted to console/admin if still needed).

_Alternative considered_: keep the by-`student_id` endpoint and just add a check. Equivalent
security-wise for the detail call, but the list endpoint (`/me/...`) is still needed for the
"choose child" UX, and removing the typed-id input is the clearest way to prevent regressions.

### D4: `report.read` gate is assumed from Proposal A
The new endpoints require `report.read`. Because that permission is introduced by Proposal
A, this change depends on it. If sequencing forces this change first, gate temporarily on
the student/parent/guardian roles and switch to `require_permission(report.read)` when
Proposal A lands.

## Risks / Trade-offs

- **Projection lag** → A link added in academic-ops is not visible in grading until the
  event is consumed. Mitigation: the link admin UI shows "pending" until confirmed; the
  window is the same as existing projections (seconds) and acceptable for this read path.
- **Event/migration ordering across services** → `student_authz` must exist before grading
  consumes the new events. Mitigation: ship the grading migration in the same release; the
  consumer ignores unknown event types already (`_ => {}` arm), so out-of-order deploys
  degrade gracefully (no crash, just no projection until both sides are up).
- **Breaking the existing portal** → Removing the typed-id endpoint changes the portal
  contract. Mitigation: ship FE + BE together; until guardians are linked, the portal shows
  an empty "no linked students" state rather than 403 spam.
- **Pre-existing unlinked data** → Existing tenants have no student/guardian links, so the
  portal is empty until admins link accounts. Mitigation: document the admin linking step;
  optionally backfill via a one-off admin task (out of scope here).
- **Related auth gaps elsewhere** → Other grading GET endpoints (`get_student_grades`) are
  also unscoped by ownership. Out of scope here but should be tracked; Proposal A's
  `grade.read` enforcement is the place to address them.

## Migration Plan

1. academic-ops: add migration for `student.user_id` (nullable + unique index where not
   null) and the `guardian` table. Add commands/endpoints and outbox events.
2. grading: add migration for `student_authz`; add event consumers; add `/me/report-cards`
   endpoints; restrict/remove the legacy by-id endpoint.
3. web: rewrite the portal page (remove typed-id input, add child selector + new hooks);
   add admin link UIs.
4. Deploy backend (both services) together, then web.
5. Rollback: revert web to the previous portal; the new endpoints and tables are additive
   and can remain. The legacy endpoint removal is the only non-additive step — keep it
   behind the same release so rollback restores it.

## Open Questions

- Should a deep link `?student_id=` be supported in the portal, or only in-app selection?
  (Spec allows it only after backend ownership confirmation; FE may defer implementing it.)
- Does Proposal A land before or after this change? Determines whether the `report.read`
  gate is real or a temporary role check (D4).
