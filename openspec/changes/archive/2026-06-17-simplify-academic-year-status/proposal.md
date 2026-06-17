## Why

The academic-year status model is over-engineered. The 7-state lifecycle
(`Planning → Configuration → Active → Locked → Finalizing → Closed → Archived`)
originated from a single large architecture scaffold commit and contradicts the
documented implementation intent (`16_implementation_phases.md:83` describes
`draft → active`). Two intermediate states (`Locked`, `Finalizing`) have no real
side effects in code, and the strictly forward-only transition rule prevents
recovering from operator mistakes — a concrete recent pain: an admin
accidentally clicked `Active → Locked` in dev and could not undo it.

## What Changes

- **BREAKING**: Reduce the academic-year lifecycle from 7 states to 4:
  `Draft`, `Active`, `Closed`, `Archived`.
- **BREAKING**: Allow bidirectional (undo) transitions between `Draft`,
  `Active`, and `Closed`. Only transitions out of `Archived` remain forbidden.
- **BREAKING**: Rename existing state values during migration:
  `Planning`/`Configuration` → `Draft`; `Locked`/`Finalizing` → `Active`;
  `Active`/`Closed`/`Archived` unchanged.
- Require a non-empty `reason` (min 10 chars) on every status transition
  (forward and backward). The reason is persisted for audit.
- Change the grading-service report-card archival trigger: published report cards
  SHALL be archived only when a year transitions to `Archived` (currently it
  fires on both `Closed` and `Archived`).
- Add an operational guard: new grade entries SHALL be rejected when the year's
  status is not `Active` (enforced via the existing `valid_year` projection in
  grading-service). Homeroom creation remains gated on `Active` (existing).
- Introduce a tights confirmation UX for status changes: type-to-confirm +
  cooldown for backward transitions, and an extra prominent warning for the
  irreversible `→ Archived` transition.
- Emit `academic_year.status_changed` with a new `reason` field in the payload.

## Capabilities

### New Capabilities

_None_ — this change simplifies and tightens an existing capability rather than
introducing a new one.

### Modified Capabilities

- `academic-config-service`: The academic-year lifecycle requirement changes
  from a 7-state forward-only chain to a 4-state undoable model, and every
  transition now requires a `reason`. The `academic_year.status_changed` event
  payload gains a `reason` field.
- `grading-service-grade-capture`: Report-card archival on year close is
  respecified to fire only on `→ Archived`, and a new guard rejects grade entry
  when the year is not `Active`.
- `web-academic-config-management`: The year management UI gains the tights
  status-change confirmation flow (type-to-confirm + cooldown + reason field)
  and its status set shrinks from 7 to 4.

## Impact

**Backend — academic-config-service**
- `domain.rs`: `YearStatus` enum reduced to 4 variants; `can_transition_to`
  rewritten to allow undo except out of `Archived`; unit tests updated.
- `commands.rs`: `transition_year_status` accepts and validates `reason`; the
  one-`Active`-per-tenant invariant is preserved across undo paths.
- `http.rs`: PATCH `/academic-years/{id}/status` request schema gains `reason`.
- New migration: `UPDATE academic_year SET status = ...` to remap legacy values;
  placeholder storage for `reason` pending the `tenant-audit-log` change.

**Backend — academic-ops-service**
- `events.rs`: default `unwrap_or("Planning")` becomes `unwrap_or("Draft")`.

**Backend — grading-service**
- `events.rs`: `archive_published_for_year` fires only on `→ Archived`.
- `commands.rs` / `domain.rs`: new guard rejecting grade entry when
  `valid_year.status != Active`.

**Web frontend (`apps/web`)**
- `src/lib/schemas/academic-year.ts`: Zod enum 7 → 4, `reason` field added.
- `src/app/settings/academic/years/page.tsx`: `TRANSITION_MAP` and
  `STATUS_ORDER` rewritten for bidirectional 4-state model.
- New `StatusConfirmDialog` component (type-to-confirm + 5s cooldown + extra
  warning for `→ Archived`).
- `playwright/academic-config.spec.ts`: mocks and assertions updated.

**Docs**
- `09_states/AcademiQ_State_Academic_Year_Lifecycle.md`: rewritten to 4-state.
- `11_integration_contracts/apis/academic-config-api.md`: PATCH status endpoint
  and lifecycle description updated.
- `11_integration_contracts/events/academic-year-status-changed.md`: `reason`
  added to payload example.
- `13_engineering_standards/16_implementation_phases.md:83`: aligned to the
  final `Draft → Active` wording (now the source of truth).

**Out of scope**
- Real `tenant-audit-log` integration: this change specs the audit hook
  (`reason` SHALL be persisted) but defers full integration until the
  in-progress `tenant-audit-log` change lands. Until then `reason` is stored in
  a lightweight local transition log.
- Attendance guards on `Closed` years: the attendance module is not yet
  implemented; its status guard will be added when that module is built.
