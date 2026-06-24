## 1. Spike the correct Portal+focus combo
- [x] 1.1 On `MultiSelect`, remove the `onOpenAutoFocus={(e) => e.preventDefault()}` and confirm the `CommandInput` receives focus with the Portal in place, against the installed Radix popover/dialog versions
- [x] 1.2 If focus is still reclaimed by the Dialog, spike the minimal prop adjustment (e.g., `modal`, a `FocusScope` boundary, or `onOpenAutoFocus` that targets the input) that yields both non-clipped dropdown AND focusable search
- [x] 1.3 Record the working prop combination; decide whether to extract a shared helper (`useComboboxInDialog` or a shared `PopoverContent` wrapper) or apply inline identically
  - Working combination: `PopoverPrimitive.Root modal={false}` + `PopoverPrimitive.Portal` + default `PopoverPrimitive.Content` open-auto-focus. No helper extracted because no custom focus props are required.

## 2. Apply the fix to all three components
- [x] 2.1 `multi-select.tsx`: apply the verified Portal+focus combo; remove the focus-killing preventDefault
- [x] 2.2 `query-combobox.tsx`: wrap `PopoverPrimitive.Content` in `PopoverPrimitive.Portal`; apply the same focus handling; update the now-stale header comment
- [x] 2.3 `query-multi-select.tsx`: add the Portal wrapper and the same focus handling
- [x] 2.4 If a shared helper was chosen in 1.3, extract it and route all three through it

## 3. Tests
- [x] 3.1 Add a Vitest/Testing Library test rendering `MultiSelect` inside a `Dialog`, asserting the dropdown is not clipped (portal rendered) and the `CommandInput` is focusable/typeable
- [x] 3.2 Add the same test for `QueryCombobox` inside a `Dialog`
- [x] 3.3 Add the same test for `QueryMultiSelect` inside a `Dialog`
- [x] 3.4 Add keyboard-interaction assertions: `Escape` closes the dropdown; no focus-trap deadlock

## 4. Verification
- [ ] 4.1 Manually verify the "tambah penugasan" dialog: search input focuses and the dropdown is not clipped
- [ ] 4.2 Manually verify the "hubungkan akun" dialog: dropdown not clipped, search works
- [ ] 4.3 Manually verify the "roster" dialog: dropdown not clipped, search works
- [ ] 4.4 Run web lint/typecheck and the full test suite
  - `pnpm typecheck` passed.
  - `rtk vitest src/components/ui/dialog-combobox.test.tsx` passed.
  - `rtk lint` failed on existing unrelated files (`src/app/login/page.tsx`, `term-form-modal.tsx`, etc.).
  - `pnpm test` failed on existing unrelated `__tests__/academic-scope.test.tsx` expectation at line 191.
