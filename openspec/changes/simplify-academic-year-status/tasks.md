## 1. Backend — academic-config-service domain & command

- [x] 1.1 Reduce `YearStatus` enum in `services/academic-config-service/src/domain.rs` to 4 variants (`Draft`, `Active`, `Closed`, `Archived`); update `as_str`, `from_str`, and `default` (`Draft`).
- [x] 1.2 Rewrite `can_transition_to` to implement the bidirectional matrix: allow `Draft↔Active`, `Active↔Closed`, `Closed→Archived`; reject skips (`Draft→Closed`, `Draft→Archived`, `Active→Archived`) and any transition out of `Archived`; reject no-op (same status).
- [x] 1.3 Update unit tests in `domain.rs`: add cases for each allowed forward and backward transition, each rejected skip, out-of-Archived, and no-op.
- [x] 1.4 Update `transition_year_status` in `commands.rs` to accept a `reason: String`, validate non-empty + min 10 chars (return `VALIDATION_ERROR` on failure), enforce the one-`Active`-per-tenant invariant across undo paths, and write a row to `academic_year_status_transition` in the same transaction.
- [x] 1.5 Update `create_year` in `commands.rs` to set initial status `Draft` (replacing `Planning`).
- [x] 1.6 Update the PATCH `/academic-years/{id}/status` handler in `http.rs` to parse `{ status, reason }` from the request body and return `VALIDATION_ERROR` field errors for `reason`.
- [x] 1.7 Update the `academic_year.status_changed` event payload construction to include the `reason` field.
- [x] 1.8 Update integration tests in `tests/integration.rs` to cover: forward with reason, backward undo with reason, missing reason rejection, skip rejection, out-of-Archived rejection, and the transition log row.

## 2. Backend — academic-config-service repo & migration

- [x] 2.1 Add `academic_year_status_transition` table to repo (`repo.rs`): insert + (optional) query helpers.
- [x] 2.2 Add `active_exists_except` guard usage verification across undo (ensure transitioning a second year to `Active` still rejects when another `Active` exists).
- [x] 2.3 Create migration `V<n>__simplify_academic_year_status.sql`: (a) `UPDATE academic_year SET status = 'Draft' WHERE status IN ('Planning','Configuration')`; (b) `UPDATE academic_year SET status = 'Active' WHERE status IN ('Locked','Finalizing')`; (c) `CREATE TABLE academic_year_status_transition (...)`.
- [x] 2.4 Verify migration is idempotent (re-run is a no-op once legacy values are gone).

## 3. Backend — academic-ops-service

- [x] 3.1 Update default `unwrap_or("Planning")` to `unwrap_or("Draft")` in `services/academic-ops-service/src/events.rs`.
- [x] 3.2 Update any integration test seeds that use `"Planning"` to use `"Draft"`.
- [x] 3.3 Confirm homeroom-creation guard still keys on `Active` and works after a `Closed → Active` undo (add integration test if absent).

## 4. Backend — grading-service

- [x] 4.1 In `services/grading-service/src/events.rs`, narrow the `archive_published_for_year` trigger to fire only when `status == "Archived"` (remove the `"Closed"` arm).
- [x] 4.2 Add a grade-entry guard in the grade-record command: reject `POST /grades` with code `YEAR_NOT_ACTIVE` (HTTP 409) when `valid_year.status != 'Active'` for the evaluation's year.
- [x] 4.3 Update integration tests: assert report cards are NOT archived on `Closed` and ARE archived on `Archived`; assert grade entry is rejected on `Closed`/`Archived`/`Draft` and allowed on `Active`.

## 5. Web frontend — schema & data layer

- [x] 5.1 Update Zod enum in `src/lib/schemas/academic-year.ts` from 7 to 4 statuses (`Draft`, `Active`, `Closed`, `Archived`); add `reason` field (min 10 chars) to the transition request schema.
- [x] 5.2 Rewrite `TRANSITION_MAP` in `src/app/settings/academic/years/page.tsx` to the bidirectional model (Draft↔Active, Active↔Closed, Closed→Archived).
- [x] 5.3 Rewrite `STATUS_ORDER` and status label/badge map to the 4 statuses.
- [x] 5.4 Update the API call that PATCHes status to send `{ status, reason }`.

## 6. Web frontend — confirmation UX

- [x] 6.1 Create a reusable `StatusConfirmDialog` component supporting three tiers: forward (reason + summary), backward (type-to-confirm + 5s cooldown + reason), and `→ Archived` (extra irreversible warning + type-to-confirm + cooldown + reason).
- [x] 6.2 Wire the dialog into the year-management page so each status change opens it with the correct tier based on current vs. target status.
- [x] 6.3 Surface server errors (`INVALID_STATE_TRANSITION`, `ACTIVE_YEAR_EXISTS`, `VALIDATION_ERROR` on `reason`) as readable inline messages.
- [x] 6.4 Implement the 5-second cooldown that keeps the submit button disabled after dialog open for backward and `→ Archived` transitions.

## 7. Web frontend — tests

- [x] 7.1 Update `playwright/academic-config.spec.ts` mocks/assertions: year status `"Planning"` → `"Draft"`, 7-state UI assertions → 4-state, and add a flow exercising the type-to-confirm undo path.

## 8. Documentation

- [x] 8.1 Rewrite `docs/internal/09_states/AcademiQ_State_Academic_Year_Lifecycle.md` to the 4-state machine with the bidirectional transition diagram and per-state responsibilities.
- [x] 8.2 Update `docs/internal/11_integration_contracts/apis/academic-config-api.md`: PATCH status request gains `reason`; valid lifecycle text updated to the 4-state model; error table refreshed.
- [x] 8.3 Update `docs/internal/11_integration_contracts/events/academic-year-status-changed.md`: add `reason` to the payload example and note the forward-assumption caveat for consumers.
- [x] 8.4 Align `docs/internal/13_engineering_standards/16_implementation_phases.md:83` to the final `Draft → Active` wording.
- [x] 8.5 Note in the academic-ops and grading event-consumer docs that `Closed` no longer triggers report-card archival (archival is `Archived`-only).
