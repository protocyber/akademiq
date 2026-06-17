## Why

A set of small but visible UI issues in the academic console degrade usability and
consistency: content width differs page to page, the academic-year status control is a plain
dropdown rather than a clear lifecycle view, a date picker inside a modal is clipped by the
modal edge, and the "create academic year" form exposes settings (grading policy, curriculum
version) that only make sense after the year exists. These are independent, low-risk polish
items that can ship together.

## What Changes

- Make all console content full-width, matching the `/users` page, so pages no longer vary
  between `max-w-6xl`, `max-w-7xl`, etc.
- Replace the academic-year status dropdown with a horizontal timeline showing the lifecycle
  (Planning → Configuration → Active → Locked → Finalizing → Closed → Archived) and a button
  beneath it to advance to the next status.
- Fix the date picker clipping when opened inside a modal (the popover is cut off by the modal
  edge) by giving the popover proper portaling/collision handling.
- Remove the grading-policy and curriculum-version sections from the **create** academic-year
  form; they remain available only in the **edit** form (they require a saved year).
- Verify no native `confirm`/`alert` remain; convert any stragglers to the existing
  `ConfirmDialog`/dialog component (creating a reusable component only if a gap is found).

## Capabilities

### New Capabilities
- `web-ui-consistency`: Full-width content layout standard, the academic-year status timeline
  control, the in-modal date-picker fix, and the confirm/alert-as-dialog guarantee.

### Modified Capabilities
- `web-academic-config-management`: The create academic-year form no longer shows grading
  policy or curriculum-version controls; the status control becomes a horizontal timeline with
  a next-status action.

## Impact

- **apps/web**: layout width changes across academic/grading pages; `date-picker.tsx` popover
  portaling/collision props; `years/page.tsx` create-form trimming and status-control rewrite
  to a timeline; a sweep for native `confirm`/`alert`.
- **Risk**: low and self-contained; no backend or data changes.
- **Interplay**: independent of the RBAC and academic-scope changes; can land first.
