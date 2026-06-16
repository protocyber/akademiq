## 1. Full-width content

- [x] 1.1 Read the `/users` page layout to confirm the exact width standard (capped vs uncapped) before changing others
- [x] 1.2 Update `academic-settings.tsx` to drop `max-w-6xl mx-auto` so content matches `/users`
- [x] 1.3 Update `grading/entry` (`max-w-7xl`), report board, portal, and any other capped pages to the standard
- [x] 1.4 Visually verify each converted page (tables, cards, forms) renders correctly full-width

## 2. Date picker in modal

- [x] 2.1 Update `date-picker.tsx` `PopoverContent` to portal and/or set collision props (`avoidCollisions`, `collisionPadding`, container) so the calendar is not clipped
- [x] 2.2 Verify the calendar opens fully inside the year form modal and still works standalone; confirm it stacks above the dialog overlay

## 3. Create year form trim

- [x] 3.1 Ensure the create entry point of the year form renders only identity fields (name, start/end date) with no grading-policy or curriculum-version controls
- [x] 3.2 Confirm the edit form still exposes the grading-policy and curriculum-version sections
- [x] 3.3 Add/adjust a test asserting the create form shows no policy/curriculum controls

## 4. Status timeline

- [x] 4.1 Build a horizontal timeline component driven by the lifecycle order (Planning→Configuration→Active→Locked→Finalizing→Closed→Archived), highlighting the current status and marking earlier stages complete
- [x] 4.2 Replace the `Select` + "Ubah Status" control in `years/page.tsx` with the timeline plus a next-status button beneath it, reusing `useTransitionAcademicYear`
- [x] 4.3 Disable/hide the next-status button at the terminal `Archived` status
- [x] 4.4 Ensure the control is accessible (real button, status conveyed by text not color alone)

## 5. Confirm/alert sweep

- [x] 5.1 Scan the web app for `window.confirm`/`window.alert`; convert any user-facing usage to `ConfirmDialog` (add a reusable variant only if a gap is found)

## 6. Validation

- [x] 6.1 Run web lint/typecheck
- [x] 6.2 Smoke-test the academic pages: full-width layout, in-modal date picker, status timeline transitions, create-vs-edit year form
