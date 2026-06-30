## Context

The academic-config feature (`add-academic-term` and `add-academic-year`
lineage) introduced a status state machine for both years and terms:

```
Draft → [Active]
Active → [Draft, Closed]
Closed → [Draft, Active, Archived]
Archived → []  (terminal)
```

Two parallel UIs manage this: `years/page.tsx` (inline `IdentitySection`) and
`term-form-modal.tsx` (`TermInfoSection`). Both share `StatusConfirmDialog` for
confirmation. The backend (`academic-config-service`) has transition endpoints
for both, but only terms have a general update (PATCH) endpoint.

The bugs cluster around two design flaws that were introduced together:

1.  **Conflation of "save form" and "change status"** — the term form's
    `onSubmit` does both in sequence, with the status change gated only on a
    loose `nextStatus !== term.status` check against a `<Select>` default.
2.  **Asymmetric API surface** — terms are fully CRUD-capable; years are
    CR-D only (no update). This was likely an oversight during the initial
    scaffold, not a deliberate constraint.

### Evidence (live code references)

**Hidden transition path** — `term-form-modal.tsx:339-346`:
```
if (nextStatus && nextStatus !== term.status) {
  await transition.mutateAsync({
    status: nextStatus,
    reason: "Perubahan dari formulir semester"  // hardcoded, no dialog
  });
}
```
`nextStatus` defaults to `options[0]`; for an Active term that's `"Draft"`.

**No year update** — `years/page.tsx:648-665`: `onSubmit` only handles
`mode === "create"`; `http.rs` defines no PATCH on `/academic-years/:id`.

**Reason always required** — `status-confirm-dialog.tsx:81-82`:
`isReasonValid = reason.trim().length >= 10`; backend `commands.rs:148-154`
and `1400-1406` enforce the same.

## Goals / Non-Goals

**Goals:**
- A user editing a term's name/dates never accidentally changes its status.
- A user editing a year's name/dates can save (currently impossible).
- Forward status transitions don't force the user to type a meaningless reason.
- After any status change, all dependent UI updates without manual refresh.
- Backend transition log retains the reason audit trail for backward/archived
  transitions; forward transitions may have a null reason.

**Non-Goals:**
- Changing the status state machine itself (Draft→Active→Closed→Archived
  remains).
- Adding new statuses or transitions.
- Redesigning the form layout or the dialog UX beyond the reason-field logic.
- Changing event payloads (`academic_year.status_changed`,
  `academic_term.status_changed`) — they already carry `reason` as optional in
  the event schema; the command handler simply stops requiring it.

## Decisions

### Decision 1: Remove the hidden transition from `onSubmit` entirely

The term form's "Simpan" button must only call `update.mutateAsync`. Status
transitions happen exclusively through the "Ubah Status" button → dialog →
`transition.mutateAsync`. This is the cleanest fix: no heuristic, no default
comparison, no surprise.

*Alternative rejected:* keep the combined path but only fire the transition
when the user explicitly changes the `<Select>` away from default. Rejected
because it's fragile (depends on detecting "did the user touch the select?")
and conflates two distinct user intents in one button.

```
BEFORE (buggy):                      AFTER:
┌───────────────────────┐            ┌───────────────────────┐
│ Term Form             │            │ Term Form             │
│ [name] [start] [end]  │            │ [name] [start] [end]  │
│ [Select: nextStatus]  │            │                       │
│ [Simpan]              │            │ [Simpan]              │
│  └─ update + maybe    │            │  └─ update ONLY       │
│     transition        │            │                       │
│     (hardcoded reason)│            │ ───── divider ────── │
└───────────────────────┘            │ Status: Active        │
                                     │ [Select] [Ubah Status]│
                                     │  └─ dialog → trans    │
                                     └───────────────────────┘
```

### Decision 2: Reason optional for forward, mandatory for backward/archived

The backend `TransitionYearStatusBody` and `TransitionTermStatusBody` change
`reason: String` to `reason: Option<String>`. The command handler validates:

- Forward transition (`is_forward`): reason is optional; if provided, must be
  ≥ 10 chars (don't accept garbage); if absent, `None` is stored.
- Backward/archived transition: reason is required and must be ≥ 10 chars
  (returns `VALIDATION_ERROR` if missing or too short, same as today).

The transition log tables (`academic_year_status_transition`,
`academic_term_status_transition`) allow `reason` to be nullable. A migration
makes the column nullable; existing rows (all have reasons) are unaffected.

The `StatusConfirmDialog` component:
- Forward tier: reason field rendered with placeholder "Alasan (opsional)";
  `canSubmit` does not check `isReasonValid`; if the user types something
  < 10 chars, show the same inline hint but don't block submit.
- Backward/archived tiers: unchanged (reason required, ≥ 10 chars, plus type
  confirmation for backward, plus cooldown for archived).

*Alternative rejected:* frontend always sends a default reason like
`"Status diubah ke Active"` for forward transitions. Rejected because it
pollutes the audit log with meaningless entries and the user explicitly said
forward transitions don't need a reason.

### Decision 3: Add `PATCH /academic-years/:id` mirroring term update

New endpoint: `PATCH /api/v1/academic-config/academic-years/:id`
Body: `{ name, start_date, end_date }` (same fields as create minus tenant).
Handler `update_academic_year`:
- Blocks update if `current.status == Archived` (returns `YEAR_NOT_EDITABLE`,
  symmetric to `TERM_NOT_EDITABLE`).
- Validates date ordering (start < end) and year-overlap rules within tenant.
- Calls `repo.update` which issues
  `UPDATE academic_year SET name=$3, start_date=$4, end_date=$5, updated_at=NOW()
  WHERE tenant_id=$1 AND academic_year_id=$2` — **never touches `status`**.
- Returns the updated year with preserved status.

Frontend gains `useUpdateAcademicYear(yearId)` mutation and the edit-mode
`IdentitySection` renders a "Simpan" button that calls it.

### Decision 4: Broaden query invalidation on transition success

Both `useTransitionAcademicYear` and `useTransitionAcademicTerm` already
invalidate their primary list keys. The term transition also invalidates
`ACADEMIC_YEARS_QUERY_KEY` (because year status can be affected by term
guards). We additionally invalidate:
- The academic scope context query (whatever `useAcademicScope()` uses as its
  key) — so the global "active year/term" indicator updates.
- Any dashboard KPI queries that depend on term/year status (if identified).

The exact keys will be confirmed during implementation by auditing
`use-academic-config.ts` query key exports and the scope provider.

## Risks / Trade-offs

- **[Risk] Existing clients send `reason` for forward transitions** → they
  continue to work (body accepts optional reason). No breakage.
- **[Risk] Transition log has null reasons for forward transitions** → audit
  queries must handle null. Accepted: forward transitions are less
  security-sensitive; the log still captures who/when/from/to.
- **[Risk] New PATCH year endpoint could be called while year is Active** →
  allowed by design (editing name/dates of an Active year is legitimate, same
  as terms). The status itself is never changed by PATCH.
- **[Trade-off] Two code paths for status change (dialog vs removed hidden)** →
  after the fix there is exactly ONE path (dialog), which is simpler and
  correct. The removed path was the bug.

## Migration Plan

1. **Backend first:** add migration (nullable reason column), add
   `update_academic_year` endpoint, relax reason validation. Deploy.
2. **Web:** remove hidden transition from `onSubmit`, add
   `useUpdateAcademicYear`, add year save button, update dialog reason logic,
   broaden invalidation. Deploy.
3. **Verify:** edit a term → status unchanged; edit a year → saves; forward
   transition → no reason required; backward transition → reason required; UI
   refreshes after all transitions.

## Open Questions

- Should the year update endpoint also validate that the year's terms still
  fall within the new date bounds (like `update_academic_term` validates
  against the year)? Lean: yes, for consistency — reject if any term's
  `[start_date, end_date]` falls outside the new year bounds.
- Are there other consumers of the transition log `reason` column (reports,
  audit views) that assume non-null? Need to audit before making it nullable.
