## Why

The shared `DatePicker` (`components/ui/date-picker.tsx`, built on the
`Calendar` wrapper over `react-day-picker` v10) is bulkier than it needs to be
and slow to navigate for the dates this app actually captures — birthdates,
academic-year boundaries — which are often years away from today. Two problems:

- **Not compact.** The trigger and popover take more space than the surrounding
  form controls warrant.
- **No fast month/year jump.** Reaching a distant month means clicking the
  previous/next chevrons one month at a time; there is no way to pick a month and
  year directly. `react-day-picker` v10 supports a `captionLayout="dropdown"`
  caption with month + year dropdowns — we are not using it.

This is a small, isolated component change. It is intentionally **separate** from
the date fields inside the academic redesigns (`redesign-academic-*-tables`):
those screens consume this shared component, so improving it here benefits them
without touching their in-flight work.

## What Changes

- **MODIFIED `DatePicker`/`Calendar`** — make the control more compact (tighter
  trigger and popover sizing) while keeping the existing `value`/`onChange`
  (`yyyy-MM-dd` string) contract and a11y attributes unchanged.
- **NEW month/year dropdown navigation** — enable a caption with month and year
  dropdowns so users can jump directly to a month and year without stepping
  through with the chevrons. A sensible year range is configurable (e.g. wide
  enough for birthdates and academic years).

## Capabilities

### Modified Capabilities

- `migrate-radix-to-shadcn`: the shared shadcn `DatePicker`/`Calendar` gains
  compact sizing and month/year dropdown navigation while preserving its public
  props and accessibility.

## Impact

- **Web (`apps/web`):** `components/ui/date-picker.tsx` and
  `components/ui/calendar.tsx` only. Public props (`value`, `onChange`,
  `placeholder`, `disabled`, aria-*) are unchanged, so every consumer (grading,
  report-cards, academic config/ops, teaching-assignments) benefits with no
  call-site changes.
- **No backend impact.**
- **Out of scope:** redesign of the date *fields* within specific pages,
  date-range pickers, and locale/format changes (stays `yyyy-MM-dd`).
