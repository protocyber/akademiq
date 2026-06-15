## 1. Month/year dropdown navigation (#2)

- [ ] 1.1 Enable `captionLayout="dropdown"` (month + year) on the `Calendar` wrapper using react-day-picker v10
- [ ] 1.2 Set a configurable `startMonth`/`endMonth` (or year range) wide enough for birthdates and academic years
- [ ] 1.3 Style the dropdowns to match shadcn tokens (works in light and dark)
- [ ] 1.4 Verify selecting via dropdowns + day still emits `yyyy-MM-dd` through the existing `onChange`

## 2. Compact sizing (#1)

- [ ] 2.1 Tighten the `DatePicker` trigger and popover sizing to sit consistently with sibling inputs
- [ ] 2.2 Keep the trigger's icon + formatted value / placeholder behavior
- [ ] 2.3 Confirm no public prop changes (`value`, `onChange`, `placeholder`, `disabled`, `aria-*`)

## 3. Verify

- [ ] 3.1 `pnpm lint` + `pnpm build` (or typecheck) pass
- [ ] 3.2 Spot-check consumers (a birthdate field, an academic-year field) — dropdown jump works, value round-trips
- [ ] 3.3 Verify a11y: dropdowns labeled, `aria-invalid`/`aria-describedby` still applied; renders correctly in dark mode
