## Context

`apps/web` lacks shared UI foundations for patterns it uses repeatedly:

- No `src/components/ui/tabs.tsx` exists; no page uses shadcn `<Tabs>`. "Tabs"
  are faked three ways: route-driven `<Button variant={pathname===href?...}>`
  nav (`academic-settings.tsx`, `academic-ops-page.tsx`), state `setActiveTab`
  buttons (year modal), and a state `setActiveStatus` border-bottom button row
  (report-card status approval, `classroom/[classroomId]/page.tsx`).
- `DialogContent` (`src/components/ui/dialog.tsx`) sets no max height or internal
  scroll, so tall modals clip top/bottom (e.g. the add-role modal). Some callers
  patch `max-h-[90vh] overflow-y-auto` ad hoc (year modal); others don't
  (RoleDialog) — inconsistent.
- Table screens use ad-hoc layouts; `/settings/users` already wraps its table +
  search + filters in `Card`/`CardHeader`/`CardContent` and is the reference.
- Built-in roles have Edit disabled (`is_builtin`) with no read-only view, so
  admins cannot inspect their permissions.
- Header issues: curriculum `<Select>` always renders; the user-menu avatar uses
  `bg-slate-100` which is near-invisible on the light header; the mobile sidebar
  scope selectors use `sm:flex-row` and overflow the narrow sidebar.

Already correct (out of scope): the sidebar keeps a previously-open menu group
open when navigating to another group — `toggleGroup`/`useEffect[pathname]` only
add active groups, never close others (`sidebar-layout.tsx`). No work needed for
that complaint beyond verification.

## Goals / Non-Goals

**Goals:**
- One shared `Tabs` component with three documented usage patterns.
- Dialogs scrollable by default (fix clipping) via the base component.
- A reusable table→card layout convention applied to the listed screens.
- A read-only role detail view.
- Header/scope polish: curriculum visibility, avatar contrast, mobile scope
  layout.

**Non-Goals:**
- The term/report-type relocation and modal form tabs
  (`restructure-term-report-ui` consumes the `Tabs` component).
- The `term_id` data bug (`fix-term-id-divergence`).
- Backend/API/event changes.
- Menu-group open/close behavior (already implemented).

## Decisions

### Decision 1: One `Tabs` component, three usage patterns
Add `src/components/ui/tabs.tsx` (shadcn/Radix). Patterns:

| Pattern | Where | Composition |
|---|---|---|
| Route-driven nav | `academic-settings.tsx`, `academic-ops-page.tsx` | `Tabs value={pathname}` + `TabsTrigger asChild` → `<Link>`, **no `TabsContent`** (content is the routed page) |
| State filter | report-card status approval | canonical `Tabs value/onValueChange`, count badge per trigger |
| Modal form tabs | (year/semester forms) | canonical `Tabs`, consumed by `restructure-term-report-ui` |

Route-driven nav must preserve per-view URLs (deep-link, back, refresh), so it
uses `TabsList`/`TabsTrigger` for appearance/active-state only. *A11y caveat:*
`asChild` makes the `<Link>` inherit `role="tab"`, semantically weaker than
`nav` + `aria-current="page"` for navigation; accepted tradeoff to match the
shadcn look — document it. *Alternative rejected:* a separate bespoke nav-tabs
component — duplicates styling and drifts.

### Decision 2: Fix scrolling in the base `DialogContent`
Give base `DialogContent` a max height (`max-h-[85vh]`) and a flex column with a
scrollable body region, keeping `DialogHeader`/`DialogFooter` pinned. Remove
per-modal `max-h`/`overflow` hacks so every dialog inherits correct behavior.
*Alternative rejected:* patch each modal — that is exactly the current
inconsistent state. *Risk:* touches every dialog (see Risks).

### Decision 3: Table→card layout convention from `/settings/users`
Adopt the `/settings/users` pattern: each table screen wraps its toolbar (search,
filters, primary action) and `DataTable` inside `Card` → `CardHeader`
(title + optional `CardDescription`) → `CardContent`. Apply to roles, subjects,
class-templates, years, teachers, students, homerooms, teaching-assignments, and
the report status board. *Alternative rejected:* a new shared `TableCard`
wrapper now — defer; first align structurally, extract a wrapper later if churn
warrants.

### Decision 4: Read-only role detail dialog
Add a View action (always enabled, including `is_builtin`) opening a dialog that
renders the role's active permissions read-only, reusing RoleDialog's
`permissions.map` rendering without form controls. *Alternative rejected:*
enabling Edit for built-in roles — built-in roles are intentionally immutable.

### Decision 5: Header/scope polish
- Curriculum `<Select>`: render only when `curriculums.length > 1`; when exactly
  one, auto-select it into scope but hide the control; never flicker during
  loading; hidden when zero.
- User-menu avatar: replace `bg-slate-100 text-slate-700` with a token that has
  real contrast on the light header (e.g. `bg-primary/10 text-primary` +
  `border border-primary/20`), matching the institution badge; use the
  `frontend-design` skill for final treatment.
- Mobile sidebar scope: an `isSidebar` variant that forces `flex-col` + full
  width so the three selectors stack vertically and don't overflow the `w-72`
  sidebar.

## Risks / Trade-offs

- **[Risk] Base dialog change affects every modal** → broad visual regression
  surface. *Mitigation:* audit all `DialogContent` callers; remove now-redundant
  `max-h` hacks; visually verify each modal (roles, users, years, ops import,
  confirm dialogs).
- **[Risk] Route-driven `Tabs` a11y semantics** → `role="tab"` on nav links.
  *Mitigation:* documented tradeoff; revisit with `aria-current` if it causes AT
  issues.
- **[Risk] Card refactor overlaps files with `restructure-term-report-ui`**
  (e.g. `years/page.tsx`) → merge conflicts. *Mitigation:* sequence — land
  `ui-foundations-polish` (Tabs + card layout) before the term restructure, or
  coordinate edits on the shared branch.
- **[Trade-off] Curriculum auto-select hides a control** → operators with one
  curriculum lose the visible picker. Accepted: reduces clutter; reappears when a
  second version exists.

## Migration Plan

1. Add `ui/tabs.tsx`; fix `dialog.tsx` base scrolling; remove ad-hoc modal
   `max-h` hacks.
2. Apply route-driven tabs to `academic-settings.tsx` and `academic-ops-page.tsx`.
3. Convert report-card status approval to state-filter `Tabs` with count badges.
4. Apply the card layout to the listed table screens.
5. Add the read-only role detail dialog.
6. Header/scope polish (curriculum visibility, avatar, mobile scope layout).
7. Rollback: each item is independent and revertable; the dialog base change is
   the only broad one — revert restores prior per-modal behavior.

## Open Questions

- Extract a shared `TableCard`/`TableToolbar` wrapper now, or just align
  structurally and extract later? Lean: align now, extract if duplication hurts.
- Avatar treatment: initials on tinted circle vs a neutral ring — defer to the
  `frontend-design` skill during implementation.
