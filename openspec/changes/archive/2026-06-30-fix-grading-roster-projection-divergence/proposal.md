## Why

On the `/grading/entry` page, the student roster is read from **academic-ops-service** (the source of truth for enrollments), but the grade-submit authorization check reads grading-service's **`enrolled_student` projection** (populated asynchronously via the `student.enrolled` event). When the projection is stale, missing, or out of sync, a student appears in the roster and their grade cell is editable, but submitting the score fails with `STUDENT_NOT_ENROLLED`. The teacher sees a valid row they cannot write to. The root cause is structural: the read path and the write path consult two different data sources that can legitimately disagree.

## What Changes

- **Single source of truth for the entry-page roster.** The grading entry grid MUST source its student roster from grading-service's own `enrolled_student` projection — the same table the grade-write authorization check reads — so that the students shown are exactly the students for whom a grade can be recorded. Read and write can no longer disagree. *(Backend + frontend.)*
- **New grading endpoint `GET /api/v1/grading/homerooms/{homeroom_id}/roster`.** Returns the active students for a homeroom+year from `enrolled_student`, with the display fields (full_name, nis) denormalized into the projection via the `student.enrolled` event payload (enrichment), so the roster is self-contained and does not require a cross-service join at read time. *(Backend.)*
- **Enrich the `enrolled_student` projection with display fields.** The `student.enrolled` event handler (`events.rs`) MUST persist `full_name` and `nis` (and update them on change) into the projection, so the roster endpoint can return display-ready rows without calling academic-ops. Migration adds the columns. *(Backend, migration.)*
- **Switch the entry page to the grading roster.** `useHomeroomRoster` on the grading entry page MUST call the new grading endpoint instead of the academic-ops roster endpoint. *(Frontend.)*
- **Graceful empty/syncing state.** When the grading roster is empty for a selected class+year (projection not yet populated), the entry grid MUST show an explicit "roster sedang tersinkronisasi" state rather than implying the class has no students, guiding the user to wait or contact an admin. *(Frontend.)*

## Capabilities

### New Capabilities
<!-- None — extends the existing grading capability. -->

### Modified Capabilities
- `grading-service-grade-capture`: the entry roster is served by grading-service from its own projection (single source with the write check); projection carries display fields; new roster endpoint; graceful syncing state

## Impact

- **Backend (`apps/backend/services/grading-service`)**: migration to add `full_name`/`nis` to `enrolled_student`; `events.rs` `student.enrolled` handler enriched + a `student.updated`-style handler for name/nis changes; `repo.rs` `active_students_for_homeroom` returns display fields; new `GET /homerooms/{id}/roster` route + handler in `http.rs`/`queries.rs`. Note: `enrolled_student` unique constraint is `(tenant_id, student_id, academic_year_id)` — homeroom moves within a year upsert in place, consistent with today.
- **Frontend (`apps/web`)**: `use-academic-ops.ts` `useHomeroomRoster` gains a grading-backed variant or the entry page switches to a new `useGradingRoster` query in `use-grading.ts`; entry grid empty-state messaging.
- **Events**: confirm `student.enrolled` payload carries `full_name`/`nis` (extend if not); add handling for student profile updates so names stay current in the projection.
- **API contract**: new endpoint documented in `docs/internal/11_integration_contracts/apis/`.
- **Tests**: backend test that the roster endpoint and the write check agree (a student in the roster is submittable; a student not in the roster is not shown); projection enrichment test; frontend test for the syncing empty-state.
- **Coordination**: confirm this does not overlap with `fix-enrollment-events` (event *delivery* reliability) — this change assumes events are delivered and makes the read/write use the same projected row regardless.
