# Tasks: ui-foundations-polish

Web submodule `apps/web`, branch context `feat/add-academic-term`.
Land Tabs + dialog base early; other web changes depend on them.

## 1. Shared Tabs component

- [x] 1.1 Add `src/components/ui/tabs.tsx` (shadcn/Radix): `Tabs`, `TabsList`,
      `TabsTrigger`, `TabsContent` (use the shadcn-ui skill).
- [x] 1.2 Verify route-driven usage works: `TabsTrigger asChild` wrapping
      `<Link>`, `value={pathname}`, no `TabsContent` (content is the routed page).
- [x] 1.3 Document the a11y caveat (route links inherit `role="tab"`).

## 2. Scrollable dialog base

- [x] 2.1 In `src/components/ui/dialog.tsx`, give `DialogContent` a max height
      (`max-h-[85vh]`) and an internally scrollable body with pinned
      header/footer (see shadcn scrollable-content example).
- [x] 2.2 Remove now-redundant per-modal `max-h`/`overflow` hacks (e.g. year
      modal).
- [x] 2.3 Audit every `DialogContent` caller and visually verify no clipping
      (roles, users, years, ops import, confirm dialogs).

## 3. Apply Tabs to existing nav/filter surfaces

- [x] 3.1 Convert `academic-settings.tsx` route nav to route-driven `Tabs`.
- [x] 3.2 Convert `academic-ops-page.tsx` route nav to route-driven `Tabs`.
- [x] 3.3 Convert report-card status approval
      (`grading/report-cards/[reportTypeId]/classroom/[classroomId]/page.tsx`)
      to state-filter `Tabs` with a count badge per trigger.

## 4. Table → card layout

- [x] 4.1 Apply the `/settings/users` card layout (toolbar + DataTable inside
      `Card`/`CardHeader`/`CardContent`) to: roles, subjects, class-templates,
      years.
- [x] 4.2 Apply the same to academic-ops screens: teachers, students, homerooms,
      teaching-assignments.
- [x] 4.3 Apply to the report status board.
- [x] 4.4 Keep `CardDescription` optional per page context.

## 5. Read-only role detail view

- [x] 5.1 Add a View action (enabled for all roles, including `is_builtin`) on
      `src/app/settings/roles/page.tsx`.
- [x] 5.2 Build a read-only dialog reusing the permission rendering from
      `RoleDialog` without form controls.

## 6. Header / scope polish

- [x] 6.1 Curriculum selector: render only when `curriculums.length > 1`;
      auto-select the single option into scope otherwise; no loading flicker.
- [x] 6.2 User-menu avatar: replace `bg-slate-100 text-slate-700` with a
      contrasting token (matching the institution badge); use the
      `frontend-design` skill for the final treatment.
- [x] 6.3 `AcademicScopeSelectors` `isSidebar` variant: force `flex-col` +
      full-width so selectors stack vertically and don't overflow the sidebar.
- [x] 6.4 Verify (no code change expected) that navigating across menu groups
      keeps the previously-open group open.

## 7. Verify

- [x] 7.1 Web lint + typecheck green.
- [x] 7.2 Update/extend component tests (tabs render, dialog scroll, role view,
      scope visibility) and relevant Playwright specs.
