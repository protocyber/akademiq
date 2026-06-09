## 1. Install shadcn primitives + deps

- [x] 1.1 Create `src/components/ui/select.tsx` (dep `@radix-ui/react-select` already present)
- [x] 1.2 Create `src/components/ui/textarea.tsx`
- [x] 1.3 Add `@radix-ui/react-checkbox`; create `src/components/ui/checkbox.tsx`
- [x] 1.4 Add `@radix-ui/react-popover`; create `src/components/ui/popover.tsx`
- [x] 1.5 Add `react-day-picker` + `date-fns`; create `src/components/ui/calendar.tsx`
- [x] 1.6 Build `src/components/ui/date-picker.tsx` (Popover + Calendar), value as `YYYY-MM-DD` string via `parseISO`/`format`
- [x] 1.7 `pnpm typecheck` clean with all new primitives present

## 2. QuerySelect wrapper (loading state)

- [x] 2.1 Build `QuerySelect` wrapping shadcn `Select`: `isLoading` → `<Spinner size="sm">` in trigger + `disabled`; success+empty → empty text + `disabled`; success+data → normal
- [x] 2.2 Add a Vitest spec covering the three states (loading / empty / data)

## 3. Migrate native `<select>` → shadcn Select / QuerySelect

- [x] 3.1 `curriculum/page.tsx:150` (query-bound) → `QuerySelect` fed by `curriculum`
- [x] 3.2 `grading-policy/page.tsx:109` static scale options (`0-100`/`A-E`) → plain `Select`; rebind RHF `field` to `value`+`onValueChange`
- [x] 3.3 `years/page.tsx:206` status options → plain `Select`
- [x] 3.4 `YearPicker` (`academic-settings.tsx:223`, query-bound years) → `QuerySelect`
- [x] 3.5 Delete `SelectInput` (`academic-settings.tsx:196-209`) + its import in `years/page.tsx:26`

## 4. Migrate checkbox → shadcn Checkbox

- [x] 4.1 `login/page.tsx:237` native `<input type="checkbox">` + native `<label>` → shadcn `Checkbox` + `Label`
- [x] 4.2 Wire to RHF (or flag dead "remember device" wiring per design D7 open question)

## 5. Migrate date fields → shadcn DatePicker

- [x] 5.1 `years/page.tsx:121` (`start_date`) `<Input type="date">` → `DatePicker`
- [x] 5.2 `years/page.tsx:134` (`end_date`) `<Input type="date">` → `DatePicker`
- [x] 5.3 Confirm value stays `YYYY-MM-DD` string into the mutation; schema `academic-year.ts` unchanged

## 6. Resolve hidden `<input>` form fields

- [x] 6.1 `class-templates/page.tsx:76` — register `academic_year_id` via RHF, no rendered input
- [x] 6.2 `grading-policy/page.tsx:88` — same for `academic_year_id`
- [x] 6.3 `curriculum/page.tsx:158` — remove redundant hidden input (value set via `setValue` effect)

## 7. Data layer — document the second fetch site

- [x] 7.1 Reword `CONVENTIONS.md §5` to allow `fetch()` in `client.ts` AND `lib/query/server.ts`
- [x] 7.2 Clarify §1 that `<input type="hidden">` (form plumbing) is not a forbidden UI control

## 8. Enforcement

- [x] 8.1 Verify `react/forbid-elements` covers `src/components/features/**` (no escape hatch survives)
- [x] 8.2 `pnpm lint` passes clean with zero `forbid-elements` violations
- [x] 8.3 `pnpm typecheck` passes
- [x] 8.4 (Follow-up, optional) Confirm `next lint` runs in CI / pre-commit

## 9. Regression check

- [x] 9.1 Exercise all migrated controls: 4 selects, 2 date pickers, login checkbox
- [x] 9.2 Confirm QuerySelect shows spinner while loading, empty state when no rows
- [x] 9.3 Confirm form submissions send correct id + date values after migration
