## Context

The grading service approval gate checks `class_scope().homeroom_teacher`
(`domain.rs:276,279,282`). Today that boolean resolves in `repo.rs:1501-1519`
by querying `teaching_authz` — the subject-teaching-assignment projection.
`subject_teacher` and `homeroom_teacher` both equal the same `linked_assignment`
boolean. So the gate passes for any teacher with any subject assignment in that
class, which is a proxy, not a designation.

The `homeroom` table in `academic-ops-service` has no teacher column. The
printed rapor page (`apps/web/.../print/page.tsx:97-107`) currently derives the
walikelas name from "whoever approved the homeroom step" and falls back to the
oldest teaching assignment — a workaround that acknowledges the missing link.

## Goals / Non-Goals

**Goals:**
- Store a designated walikelas per homeroom (nullable — a class may have none
  yet).
- Propagate the designation to grading via the existing event/projection pattern.
- Make `class_scope().homeroom_teacher` reflect the real designation.
- Allow admin to set/clear the walikelas from the homeroom edit form.

**Non-Goals:**
- No change to IAM role assignment (role and designation stay independent).
- No co-walikelas support (1:1 per class, per year — enforced by the column).
- No audit trail of walikelas changes (out of scope for now).
- No auto-grant of `homeroom_teacher` IAM role on designation.
- No change to the rapor approval state machine or transition logic.

## Decisions

### Decision 1: Column on `homeroom` table (not a separate assignment table)

**Choice:** `ALTER TABLE homeroom ADD COLUMN homeroom_teacher_id UUID NULL
REFERENCES teacher(teacher_id) ON DELETE SET NULL`.

**Rationale:** A class has exactly one walikelas — a nullable column models this
directly. It mirrors how `academic_year_id` ties a homeroom to its year. A
separate assignment table would add a table, command, event type, and projection
for what is a simple 1:1 nullable fact. Option B (separate table) is reserved if
co-walikelas or assignment history is needed in future.

**ON DELETE SET NULL** — if a teacher is deleted the homeroom loses its walikelas
designation rather than being blocked. Matches the spirit of existing cascade
behaviour (deleting a teacher clears teaching assignments in grading projection).

### Decision 2: Reuse `homeroom.updated` event (new payload field)

**Choice:** Extend the `homeroom.updated` event payload with
`homeroom_teacher_id` (nullable UUID) and `homeroom_teacher_user_id` (nullable
UUID — the linked IAM user of that teacher at event time).

**Rationale:** `homeroom.created` is already consumed by academic-config and
grading for projection setup. Adding `homeroom.updated` as a new event type
(not currently emitted) is the natural pair. Grading and academic-config can
subscribe without touching `homeroom.created` handling.

`teacher_user_id` is resolved at event-emit time from the `teacher` row (which
already carries `user_id` from the IAM link). This avoids grading having to
cross-query academic-ops at event consumption time.

### Decision 3: New `homeroom_teacher_authz` projection in grading

**Choice:** Add a small projection table in grading-service:

```sql
CREATE TABLE homeroom_teacher_authz (
  tenant_id          UUID NOT NULL,
  homeroom_id        UUID NOT NULL,
  teacher_user_id    UUID,
  academic_year_id   UUID NOT NULL,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT homeroom_teacher_authz_pk PRIMARY KEY (tenant_id, homeroom_id, academic_year_id)
);
```

Populated (upsert) on `homeroom.updated`; row deleted on `homeroom.created` with
null teacher (idempotent). `class_scope()` queries this table for
`homeroom_teacher` instead of re-using `teaching_authz`.

**Rationale:** Keeps grading self-contained (no cross-service HTTP at auth time).
Follows the existing pattern of `teaching_authz` as a projection of
`teacher.assigned`. The table is tiny (one row per homeroom per year).

### Decision 4: Teacher picker shows all tenant teachers

**Choice:** The homeroom edit form picker lists all teachers returned by
`GET /teachers` (already fetched by `useTeachers`), not filtered to assigned
teachers.

**Rationale:** The walikelas of a class need not teach any subject in that class
— they may be a designated class guardian with no subject. Restricting to
assigned teachers would artificially limit valid designations. The user explored
this in the design session and confirmed all-tenant scope is correct.

## Risks / Trade-offs

- **[Projection lag]** — Between `homeroom.updated` event emission and grading
  consuming it, the old `class_scope` value persists. For rapor approval this
  is acceptable (eventual consistency is standard for projection-based services).
- **[Existing homerooms have no walikelas]** — Column is nullable; existing rows
  get `NULL`. The gate falls back to `false` (no walikelas designated), which
  means existing rapor approval flows may break if previously relying on the
  proxy. → Migration plan: after deploy, confirm that any homeroom needing
  approval has a designated walikelas set.
- **[ON DELETE SET NULL on teacher]** — Deleting a teacher silently clears the
  homeroom's walikelas. No event is emitted for this (DB-level cascade). For now
  acceptable; future work could add a trigger or application-layer guard.

## Migration Plan

1. Deploy academic-ops migration (column + index).
2. Deploy grading migration (new projection table).
3. Deploy services (academic-ops emits `homeroom.updated`; grading consumes it).
4. Deploy frontend (picker in homeroom edit form).
5. After deploy: admin sets walikelas for homerooms that need rapor approval via
   the new picker. No bulk-backfill script needed (nullable, opt-in).
