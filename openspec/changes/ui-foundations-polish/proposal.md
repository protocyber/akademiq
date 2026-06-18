## Why

Several cross-cutting UI problems recur across the web app and have no shared
foundation: there is no shadcn `Tabs` component (pages fake tabs with styled
buttons or route-driven `<Button variant>` nav), the base `DialogContent` has no
height/scroll constraint so tall modals get clipped top and bottom (e.g. the add
role modal), table screens use ad-hoc layouts instead of the card layout proven
on `/settings/users`, and built-in roles cannot be inspected because Edit is
disabled with no read-only view. Fixing these once, centrally, unblocks
`restructure-term-report-ui` and removes copy-paste drift.

## What Changes

- Add a shared shadcn `Tabs` component (`src/components/ui/tabs.tsx`) and
  establish three usage patterns:
  - **Route-driven nav** (1 tab = 1 page + URL): `TabsList`/`TabsTrigger asChild`
    wrapping `<Link>`, `value={pathname}`, no `TabsContent` — applied to
    `academic-settings.tsx` and `academic-ops-page.tsx`.
  - **In-place state filter**: report-card status approval, count badge per
    trigger.
  - (Modal form tabs are consumed by `restructure-term-report-ui`.)
- Make dialogs scrollable by default: give base `DialogContent` a max height and
  a scrollable body region with sticky header/footer, so modal content never
  clips off-screen. Remove per-modal ad-hoc `max-h` hacks.
- Add a read-only **View role** dialog so admins can inspect a role's active
  permissions, including built-in roles whose Edit is disabled.
- Refactor table screens to the `/settings/users` card layout (search/filter/
  actions inside `CardContent`, optional `CardDescription`): roles, subjects,
  class-templates, years, teachers, students, homerooms, teaching-assignments,
  report status board.
- Header/scope polish: hide the curriculum selector unless there is more than one
  option (still auto-select the single option); make the user-menu avatar circle
  visible in light mode; force a vertical layout for the academic scope selectors
  in the mobile sidebar so they do not overflow.

## Capabilities

### New Capabilities
- `web-ui-foundations`: shared `Tabs` component + usage patterns, scrollable
  dialog base, and the table→card layout convention.
- `web-role-detail-view`: read-only role detail dialog showing active
  permissions.

### Modified Capabilities
- `web-navigation-access-control`: route-driven nav shells use the shared `Tabs`
  styling; academic scope selectors restructure for small screens; curriculum
  selector visibility rule; user-menu avatar contrast.

## Impact

- Web submodule `apps/web`, branch context `feat/add-academic-term`.
- New `src/components/ui/tabs.tsx`; modified `src/components/ui/dialog.tsx`.
- `src/components/layout/sidebar-layout.tsx` (scope selectors, avatar,
  curriculum visibility).
- `src/components/features/academic-config/academic-settings.tsx`,
  `src/components/features/academic-ops/academic-ops-page.tsx` (route-driven
  tabs).
- `src/app/grading/report-cards/[reportTypeId]/classroom/[classroomId]/page.tsx`
  (status filter tabs).
- `src/app/settings/roles/page.tsx` (view-role dialog), plus the table screens
  listed above (card layout).
- Touches the base dialog → broad visual regression surface; verify all modals.
- No backend change.
