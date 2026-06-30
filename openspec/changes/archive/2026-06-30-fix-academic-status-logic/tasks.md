# Tasks: fix-academic-status-logic

Backend submodule `apps/backend`, web submodule `apps/web`.

## 1. Backend — relax reason requirement for forward transitions

- [x] 1.1 Migration: make `reason` column nullable in
      `academic_year_status_transition` and `academic_term_status_transition`
      log tables.
- [x] 1.2 In `academic-config-service/src/http.rs`, change
      `TransitionYearStatusBody.reason` and `TransitionTermStatusBody.reason`
      to `Option<String>`.
- [x] 1.3 In `commands.rs` `transition_year_status` and
      `transition_term_status`: compute `is_forward` from the transition; if
      forward, reason is optional (if provided, still validate ≥ 10 chars); if
      backward/archived, reason is required and ≥ 10 chars (return
      `VALIDATION_ERROR` if missing/short).
- [x] 1.4 Update repo insert for transition log to accept nullable reason.
- [x] 1.5 Update/extend unit tests for all four transition tiers (forward
      with/without reason, backward with/without reason).

## 2. Backend — add academic year update endpoint

- [x] 2.1 In `http.rs`, add `PATCH /api/v1/academic-config/academic-years/:id`
      route → `update_academic_year` handler.
- [x] 2.2 Define `UpdateAcademicYearBody { name, start_date, end_date }`
      (same fields as create minus tenant/plan).
- [x] 2.3 Implement `commands::update_academic_year`: block Archived
      (`YEAR_NOT_EDITABLE`), validate dates, validate overlap/uniqueness
      within tenant, call `repo.update` (touches only name/dates/updated_at,
      preserves status). Consider validating that existing terms fall within
      new year bounds (see Open Questions).
- [x] 2.4 Add `repo::update_academic_year` with
      `UPDATE academic_year SET name=$3, start_date=$4, end_date=$5,
      updated_at=NOW() WHERE tenant_id=$1 AND academic_year_id=$2 RETURNING *`.
- [x] 2.5 Integration test: update non-Archived year succeeds and preserves
      status; update Archived year returns `YEAR_NOT_EDITABLE`.

## 3. Web — remove hidden transition from term form

- [x] 3.1 In `term-form-modal.tsx` `TermInfoSection.onSubmit`: remove the
      `if (nextStatus && nextStatus !== term.status) { transition... }` block
      (lines 339–346). `onSubmit` calls `update.mutateAsync` only.
- [x] 3.2 Verify the "Ubah Status" button + `StatusConfirmDialog` path is the
      sole entry point for transitions.
- [ ] 3.3 Manual test: edit an Active term's name → status remains Active.

## 4. Web — add year update (save button)

- [x] 4.1 In `use-academic-config.ts`, add `useUpdateAcademicYear(yearId)`
      mutation → `PATCH /academic-years/:id`, body `{ name, start_date,
      end_date }`, invalidates `ACADEMIC_YEARS_QUERY_KEY` on success.
- [x] 4.2 In `years/page.tsx` `IdentitySection`: handle `mode === "edit"` in
      `onSubmit` — call `update.mutateAsync(values)` instead of no-op. Add a
      "Simpan" button in edit mode (currently only rendered for create).
- [ ] 4.3 Manual test: edit a year's name → saves; status unchanged.

## 5. Web — status dialog reason logic

- [x] 5.1 In `status-confirm-dialog.tsx`: for `tier === "forward"`, render
      reason field label without the red asterisk, placeholder
      "Alasan (opsional)". Remove `isReasonValid` from `canSubmit` for forward
      tier. Keep backward/archived logic unchanged.
- [x] 5.2 In the caller (`years/page.tsx`, `term-form-modal.tsx`): when tier
      is forward and reason is empty, omit `reason` from the transition
      payload (or send null). When reason is provided, include it.
- [x] 5.3 Update `schemas/academic-year.ts` `TransitionRequestForm` and
      `schemas/academic-term.ts` `TermTransitionRequestForm`: make `reason`
      optional in the schema (`.optional()`).
- [ ] 5.4 Manual test: forward transition with empty reason succeeds;
      backward transition still requires reason.

## 6. Web — broaden query invalidation

- [x] 6.1 Audit `use-academic-config.ts` query key exports and the academic
      scope provider to identify all keys that depend on year/term status.
- [x] 6.2 In `useTransitionAcademicYear` and `useTransitionAcademicTerm`
      `onSuccess`: add invalidation for academic scope context and any
      identified dashboard KPI keys.
- [ ] 6.3 Manual test: change term status → global scope indicator updates
      without page refresh.

## 7. Verification

- [ ] 7.1 `make test` (backend + web) green — backend portion skipped by apply; run manually using the command below.
- [ ] 7.1a Web checks: `cd apps/web && bun run lint && bun run typecheck` green.
- [ ] 7.2 End-to-end manual pass: create year → create term → activate year →
      activate term → edit term (status preserved) → edit year (status
      preserved) → forward transition (no reason) → backward transition
      (reason required) → UI refreshes at each step.

## Manual Backend Tests

Run this manually after implementation (skipped by `/opsx-apply`):

```sh
cd apps/backend && make test
```

