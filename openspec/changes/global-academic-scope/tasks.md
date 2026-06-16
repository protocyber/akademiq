## 1. Provider + context

- [ ] 1.1 Create `AcademicScopeProvider` exposing `{ yearId, curriculumId, setYearId, setCurriculumId, isResolving }` via React Context, mounted inside the app providers
- [ ] 1.2 Persist `{ academic_year_id, curriculum_version_id }` to a tenant-scoped `localStorage` key (include `tenant_id` from `useTenantMe`); restore on mount inside `useEffect` (client-only) to avoid hydration mismatch
- [ ] 1.3 Validate the restored ids against `useAcademicYears` / `useCurriculumVersions(yearId)`; reset to the Active/newest default if a stored id is gone
- [ ] 1.4 Listen to the `storage` event so changes in one tab propagate to others
- [ ] 1.5 Export a `useAcademicScope()` hook for consumers

## 2. Default resolution & empty state

- [ ] 2.1 On first load (no stored scope), set year to the first `Active` year and curriculum to that year's newest version
- [ ] 2.2 When no `Active` year exists, leave the scope empty and surface an `isResolving/empty` state consumers can branch on
- [ ] 2.3 Add tests: default-to-Active, newest-curriculum selected, reset-on-deleted-year, empty-state-when-no-active

## 3. Header selectors

- [ ] 3.1 Add the academic-year selector to the header (reuse the existing `QuerySelect`/`YearPicker` styling)
- [ ] 3.2 Add the curriculum-version selector beside it, fed by `useCurriculumVersions(yearId)`; changing the year refreshes options and selects the newest version
- [ ] 3.3 Show the empty/prompt affordance when there is no Active year and none selected
- [ ] 3.4 Ensure selectors work in both desktop header and mobile (Sheet) layouts

## 4. Consume the scope in pages

- [ ] 4.1 `/grading/entry`: read year+curriculum from `useAcademicScope()`; remove the local `yearId` state and year `QuerySelect`; show empty state when no year is scoped
- [ ] 4.2 `/grading/report-cards`: read year from the scope; remove the page-level year selector
- [ ] 4.3 `teaching-assignments` (and `homerooms` if applicable): read year from the scope; remove the page/URL year param used as a local selector
- [ ] 4.4 Sweep for any other year/curriculum pickers (`grep` for `QuerySelect` + academic-year usage) and convert them

## 5. Validation

- [ ] 5.1 Add a test asserting no page-level academic-year selector remains on the converted screens
- [ ] 5.2 Add a test asserting the scope persists across a simulated reload
- [ ] 5.3 Run web lint/typecheck and `make dev-web` smoke test across grade entry, report board, and teaching assignments
