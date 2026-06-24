## Why

The walikelas (homeroom teacher) role and rapor approval gate exist and work, but
there is no way to designate which teacher is the walikelas of a specific class.
The system currently uses a proxy: any teacher who has a subject teaching
assignment in that class **and** holds the global `homeroom_teacher` role can
approve that class's report cards. This means a class has no single designated
walikelas, and the printed rapor must fall back to "whoever approved at the
homeroom step" to determine the walikelas name. The feature is visually present
(role picker in user settings, approval step in rapor) but structurally
incomplete.

## What Changes

- Add a `homeroom_teacher_id UUID NULL REFERENCES teacher(teacher_id)` column to
  the `homeroom` table in `academic-ops-service`.
- Extend `UpdateHomeroom` command to accept and persist `homeroom_teacher_id`.
- Emit a `homeroom.updated` event carrying `homeroom_teacher_id` and the resolved
  `teacher_user_id` so downstream services can project the assignment.
- Add a `homeroom_teacher_authz` projection table in `grading-service` populated
  from `homeroom.updated`. Fix `class_scope()` so `homeroom_teacher` is derived
  from the dedicated projection instead of the proxy.
- Add a walikelas picker to the homeroom edit form in the web UI. The picker
  shows all teachers in the tenant (not restricted to assigned teachers).
- Role assignment (`homeroom_teacher` IAM role) stays independent — designation
  and role remain two separate concerns.

## Capabilities

### New Capabilities

- `homeroom-teacher-assignment`: Designating a teacher as walikelas of a class,
  including the backend data model, event, projection, and web UI picker.

### Modified Capabilities

- `academic-ops-service`: `homeroom` entity gains `homeroom_teacher_id`; the
  update endpoint and event shape change.
- `report-card-workflow`: `class_scope().homeroom_teacher` is derived from the
  new dedicated projection instead of the teaching-assignment proxy.

## Impact

- **Backend `academic-ops-service`**: new DB migration, `UpdateHomeroom` command,
  `homeroom.updated` event payload, `GET /homerooms` response shape.
- **Backend `grading-service`**: new migration (`homeroom_teacher_authz` table),
  new event handler for `homeroom.updated`, `class_scope()` query updated.
- **Frontend `apps/web`**: homeroom edit form gains a teacher picker
  (`useTeachers` already available); `Homeroom` type gains optional
  `homeroom_teacher_id`.
- **No change** to IAM role assignment, the approval state machine, or any other
  service.
