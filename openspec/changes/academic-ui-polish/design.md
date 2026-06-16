## Context

Four independent UI issues in the academic console:

1. **Width drift**: `/users` renders full-width, but academic settings wrap content in
   `max-w-6xl mx-auto` (`academic-settings.tsx:111`) and grade entry uses `max-w-7xl`
   (`grading/entry/page.tsx:71`). The result is inconsistent line lengths between pages.
2. **Status control**: the academic-year status is a `Select` dropdown + "Ubah Status" button
   (`years/page.tsx:692`). The lifecycle is linear (`Planning → … → Archived`, defined by
   `nextStatuses` at `years/page.tsx:90`) and would read better as a timeline.
3. **Date picker clipping**: `date-picker.tsx` uses `PopoverContent` without explicit
   portaling/collision config; inside the year form modal the calendar is clipped by the
   dialog edge.
4. **Create-form overexposure**: the year form already gates the policy/curriculum/report tabs
   behind a saved `yearId` (`years/page.tsx:520`), but the requirement is to ensure the create
   path shows identity only.

Native `confirm`/`alert` were already replaced by `ConfirmDialog` (`components/ui/confirm-dialog.tsx`);
a sweep is needed to confirm none remain.

## Goals / Non-Goals

**Goals:**
- Uniform full-width content matching `/users`.
- Academic-year status as a horizontal timeline with a next-status action.
- Date picker fully visible inside modals.
- Create year form limited to identity fields; verify no native confirm/alert remain.

**Non-Goals:**
- Changing the status lifecycle itself or the transition rules (backend unchanged).
- Redesigning the year form beyond removing create-time settings and the status control swap.
- Any backend or data-model change.

## Decisions

### D1: Centralize the width standard
Adopt the `/users` layout width as the standard. Prefer removing per-page `max-w-*`/`mx-auto`
caps so the shared `SidebarLayout` `<main>` controls width, rather than setting a new cap on
each page. Audit the `className` passed into `SidebarLayout` per page.

_Alternative_: set every page to an identical `max-w-screen-2xl`. Rejected — still a cap to
maintain per page; matching `/users` (which is uncapped/full-width) is simpler and is the
stated reference.

### D2: Timeline as a presentational component driven by `nextStatuses`
Build a horizontal timeline component fed by the existing lifecycle order and the year's
current status; the next-status button reuses the existing `useTransitionAcademicYear`
mutation. Keep the transition semantics identical — only the presentation changes.

### D3: Fix the popover with portal + collision props
Render the date picker's `PopoverContent` in a portal (or set `collisionPadding`/
`avoidCollisions` and an appropriate `container`) so Radix positions it against the viewport,
not the modal's overflow box. Verify in both standalone and in-modal contexts.

_Alternative_: switch the calendar to an inline (non-popover) widget inside modals. Rejected —
inconsistent with the standalone date-picker UX; portaling is the standard Radix fix.

### D4: Create form trims to identity
The tabbed sections are already gated on `yearId`; ensure the create entry point renders only
the identity section and the gating copy, with no policy/curriculum controls visible.

## Risks / Trade-offs

- **Width change reveals layout bugs** → Some tables/cards assumed a capped width. Mitigation:
  visually check each converted page; tables already scroll/responsive via `DataTable`.
- **Portaling regresses z-index/stacking** → The popover could render above/below unexpected
  layers. Mitigation: test the date picker inside the year modal and standalone; ensure it
  stacks above the dialog overlay.
- **Timeline accessibility** → A purely visual timeline must remain operable. Mitigation: keep
  the next-status action a real button with a clear label; mark current status with text, not
  color alone.

## Migration Plan

1. Width: remove/adjust per-page caps to match `/users`; verify each page.
2. Date picker: add portal/collision props; verify in-modal and standalone.
3. Year form: ensure create shows identity only; build the status timeline + next-status
   button using the existing transition mutation.
4. Sweep for native confirm/alert; convert any stragglers.
5. Rollback: each item is independent and reversible; revert per item if needed.

## Open Questions

- Is `/users` truly uncapped, or does it use a specific wide cap to copy? Confirm by reading
  the users page layout before standardizing (D1).
- Should the timeline allow jumping backwards (it currently cannot)? Assume forward-only,
  matching `nextStatuses`.
