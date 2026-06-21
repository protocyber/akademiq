## Why

The academic year/term status UX has five interlocking bugs that stem from two
root causes: a hidden status-transition path embedded inside the term "Simpan"
button, and an asymmetric API surface (terms have PATCH, years do not).

Root cause 1 — hidden transition in `onSubmit`:
`term-form-modal.tsx:onSubmit` (lines 332–355) calls `update.mutateAsync` and
**then** silently calls `transition.mutateAsync` with a hardcoded reason
(`"Perubahan dari formulir semester"`) whenever the `<Select>` nextStatus
differs from the current status. Because the default `nextStatus` is
`options[0]` (which is `"Draft"` for an Active term), merely editing a
semester's name/dates and clicking "Simpan" triggers an undocumented status
demotion to Draft — no confirmation dialog involved. This single code path
explains:

- issue: "update semester → status berubah ke draft" (the hidden transition fires)
- issue: "ada request yang langsung mengubah status, modal reason seharusnya
  hanya muncul saat status mundur" (the request that "jumps ahead" is this
  dialog-less path, not the dialog itself)

Root cause 2 — no PATCH endpoint for academic years:
`academic-config-service/src/http.rs` defines GET and DELETE on
`/academic-years/:id` but **no PATCH**. The frontend's `IdentitySection`
(years/page.tsx:648–665) only handles `mode === "create"` in `onSubmit`; edit
mode has no save button at all. The `useUpdateAcademicYear` mutation hook does
not exist. This is issue: "belum ada tombol simpan di form tahun ajaran".

The remaining bugs are consequence or companions:

- issue: "perubahan status maju tidak perlu reason" — the shared
  `StatusConfirmDialog` requires a reason (min 10 chars) for **all** tiers
  including forward. Backend `transition_year_status` / `transition_term_status`
  also unconditionally require reason ≥ 10 chars.
- issue: "UI tidak berubah setelah status diubah" — the mutation's
  `onSuccess` invalidates the primary list query key but may not cover all
  derived queries (e.g. academic scope context, dashboard KPIs).

## What Changes

- **Term form: separate "Simpan" from "Ubah Status".** The `onSubmit` handler
  in `term-form-modal.tsx` will NO LONGER call `transition`. The "Simpan"
  button only updates `{ name, start_date, end_date }`. Status changes happen
  exclusively via the dedicated "Ubah Status" button → `StatusConfirmDialog`
  → `transition.mutateAsync`. The hidden hardcoded-reason path is removed.
- **Year form: add update (save) capability.** Backend gains
  `PATCH /academic-years/:id` mirroring the existing term update: accepts
  `{ name, start_date, end_date }`, preserves `status`, blocks edits on
  Archived years. Frontend gains `useUpdateAcademicYear` mutation and a
  "Simpan" button in edit mode.
- **Reason requirement: forward = optional, backward = mandatory.** Backend
  `TransitionYearStatusBody` / `TransitionTermStatusBody` make `reason`
  optional (`Option<String>`). The command handler enforces reason ≥ 10 chars
  ONLY for backward/archived transitions; forward transitions accept an
  optional reason or none. The transition log table allows null reason for
  forward transitions.
- **Dialog tier logic updated.** `StatusConfirmDialog` shows the reason field
  as **optional** for `forward` tier (placeholder "Alasan (opsional)") and
  **required** for `backward`/`archived` tiers (unchanged). `canSubmit` no
  longer gates on `isReasonValid` for forward tier.
- **Query invalidation broadened.** After a successful year/term transition,
  invalidate the primary list key AND any derived scope/context queries so
  the UI reflects the new status without a manual refresh.

## Capabilities

### Modified Capabilities
- `academic-config-service`: gains `PATCH /academic-years/:id` (update);
  status transition handlers make `reason` optional for forward transitions.
- `web-academic-ui`: term/year forms separate data-save from status-change;
  year edit gains a save button; status dialog reason is optional for forward.

## Impact

- **Backend** (`apps/backend`): `services/academic-config-service` — new route
  + `update_academic_year` command/repo, `transition_year_status` /
  `transition_term_status` reason relaxation, migration to allow null reason
  in transition log tables (or make column nullable).
- **Web** (`apps/web`): `term-form-modal.tsx`, `years/page.tsx`,
  `status-confirm-dialog.tsx`, `use-academic-config.ts`,
  `schemas/academic-year.ts`, `schemas/academic-term.ts`.
- **Migration:** the `academic_year_status_transition` and
  `academic_term_status_transition` log tables must allow `reason` to be null
  (forward transitions). Existing rows are unaffected (all have reasons).
- **No breaking API contract change for existing callers** — the PATCH body
  for transitions remains `{ status, reason? }`; existing clients that always
  send a reason continue to work.
