## Context

The `/grading/entry` page builds its student grid from `useHomeroomRoster`, which calls **academic-ops-service** (`GET /academic-ops/homerooms/{id}/roster`). Academic-ops owns the enrollment master. When a teacher submits a grade, grading-service authorizes it via `can_record_grade_for_evaluation`, which checks its **own** `enrolled_student` projection (a separate table in the grading DB, fed by the `student.enrolled` event). These two sources can disagree:

- Event not yet delivered / failed → student in academic-ops roster, absent from grading projection → `STUDENT_NOT_ENROLLED`.
- Event delivered with a status other than `'active'` → student visible (academic-ops filters differently) but write-check fails.
- Homeroom reassignment mid-year upserts the projection's homeroom, but the roster (academic-ops) may transiently show the old class.

The `enrolled_student` table (grading, `V1__init.sql:39`) carries only `{tenant_id, student_id, homeroom_id, academic_year_id, status}` — no display fields — so it cannot directly serve a roster with names. The projection's unique key is `(tenant_id, student_id, academic_year_id)`, so a student has exactly one row per year (homeroom moves update in place), which matches the write-check semantics.

`fix-enrollment-events` (in-flight) targets event *delivery* reliability. This change makes the read and write consult the **same** projected table, so even if delivery lags, the UI never shows a student the write path would reject.

## Goals / Non-Goals

**Goals:**
- Eliminate read/write divergence: the entry roster and the grade-write check use one source.
- Make the roster self-contained (display-ready from the grading projection, no cross-service read-time join).
- Give a clear UX when the projection is empty/not-yet-synced.

**Non-Goals:**
- Replacing academic-ops as the enrollment source of truth (it remains the master; grading only projects).
- Fixing event-delivery reliability itself (owned by `fix-enrollment-events`).
- Changing the write-check logic or the `STUDENT_NOT_ENROLLED` error semantics.
- Touching report-card roster reads (separate path; only the grade-entry grid is in scope).

## Decisions

### Decision 1: Serve the entry roster from grading's own projection
**Choice:** Add `GET /api/v1/grading/homerooms/{homeroom_id}/roster?academic_year_id=` returning active students from `enrolled_student` (the write-check table), and switch the entry page to it.

**Rationale:** The write check (`repo.rs:567`) and the existing read helper `active_students_for_homeroom` (`repo.rs:737`) already use the identical filter (`status='active'` + homeroom + year). Promoting the read helper to a served endpoint and pointing the UI at it guarantees the roster == the submittable set. They share one table; they cannot disagree by construction.

**Alternatives considered:**
- *Keep academic-ops roster + client-side intersection with grading projection.* Two round-trips, partial divergence on name enrichment, and the "can I submit?" question still needs the grading source. Rejected.
- *Make the write check call academic-ops at submit time.* Cross-service synchronous dependency in the hot write path; violates projection-based service communication (CONVENTIONS.md); adds latency and a failure mode. Rejected.

### Decision 2: Denormalize display fields into the projection
**Choice:** Add `full_name` and `nis` columns to `enrolled_student`; enrich the `student.enrolled` event handler to persist them; handle a student-profile-update event to keep them current. The roster endpoint returns them directly.

**Rationale:** Grading must not synchronously query academic-ops at read time. The projection pattern (already used for teacher user-linking) is the established way grading holds cross-service data. Names/nis are display-only; eventual consistency on rename is acceptable (a renamed student shows the new name after the next event).

**Alternatives considered:**
- *Return ids only; frontend enriches names from academic-ops.* Reintroduces a second source: a student could be named (academic-ops) but not submittable (projection), or vice versa. Undermines the single-source goal. Rejected.
- *Store only at first enrollment, never update.* Stale names after a profile edit. Minor, but the update event is cheap to handle. Chose to handle it.

### Decision 3: Explicit syncing empty-state
**Choice:** When the grading roster endpoint returns an empty list for a selected class+year, the entry grid shows "Roster kelas sedang tersinkronisasi" (not "Roster kelas kosong"), because an empty projection is more likely a sync gap than a genuinely empty class.

**Rationale:** The previous "Roster kelas kosong" message (`entry/page.tsx:358`) was misleading when the real cause was a missing projection row. Distinguishing the two cases requires knowing whether academic-ops has students — but we deliberately do not want a second call. Compromise: treat grading-projection-empty as "syncing" messaging, which is both the common cause and the actionable framing.

## Risks / Trade-offs

- **[Projection empty despite real enrollment]** → The syncing message is shown. This is the correct framing and self-resolves when the event lands. Pair with `fix-enrollment-events` for delivery reliability.
- **[Stale names after rename]** → Accepted; corrected on the next student-profile event. Names are display-only and not authoritative in grading.
- **[Migration adds columns to a projection table]** → Additive `ALTER TABLE ... ADD COLUMN ... NULL`; backfill not required (rows populate as events arrive; existing rows get names on the next enrollment/name event). Low risk.
- **[Event payload may not carry name/nis today]** → Confirm during implementation; if absent, extend the `student.enrolled` payload (additive, non-breaking) or issue a follow-up read. Documented as a task.
- **[Report-card roster still uses academic-ops]** → Out of scope (Non-Goal); only the grade-entry grid switches. Document to avoid confusion.

## Migration Plan

1. **Migration:** `ALTER TABLE enrolled_student ADD COLUMN full_name TEXT, ADD COLUMN nis TEXT` (nullable).
2. **Backend:** enrich `student.enrolled` handler; add name-update handling; extend `active_students_for_homeroom` to return the new columns; add the roster route + handler. Ship ahead of the frontend switch (additive).
3. **Frontend:** switch the entry page roster to the grading endpoint; update the empty-state copy. Deploy after the backend endpoint is live.
4. **Rollback:** the frontend can revert to the academic-ops roster independently; the backend endpoint/columns are additive and harmless if unused.

## Open Questions

- Does the `student.enrolled` event payload currently include `full_name`/`nis`, or must it be extended? (Verify against the academic-ops event producer during implementation.)
- Is there an existing `student.updated`/`student.profile_changed` event for name changes, or must one be added? (Check the event contract in `docs/internal/11_integration_contracts/events/`.)
