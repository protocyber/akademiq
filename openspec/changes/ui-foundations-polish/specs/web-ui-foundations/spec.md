## ADDED Requirements

### Requirement: The app SHALL provide a shared shadcn Tabs component

The web app MUST provide a shared `Tabs` component (`src/components/ui/tabs.tsx`)
built on shadcn/Radix, exporting `Tabs`, `TabsList`, `TabsTrigger`, and
`TabsContent`. It MUST support a canonical state-driven mode
(`value`/`onValueChange`) and a route-driven mode where `TabsTrigger` uses
`asChild` to wrap a navigation `<Link>` and the active tab is derived from the
current pathname (with no `TabsContent`, because each tab's content is a routed
page).

#### Scenario: State-driven tabs switch content

- **WHEN** a consumer renders `Tabs` with `value`/`onValueChange` and selects a
  different trigger
- **THEN** the matching `TabsContent` is shown and the others are hidden

#### Scenario: Route-driven tabs preserve URLs

- **WHEN** a consumer renders route-driven tabs whose triggers wrap `<Link>`s and
  the user clicks a tab
- **THEN** the browser navigates to that tab's URL (deep-link, back button, and
  refresh reproduce the view) and the trigger matching the current pathname is
  marked active

### Requirement: Dialogs SHALL be scrollable by default

The base `DialogContent` MUST constrain its height (so it never exceeds the
viewport) and provide an internally scrollable body while keeping the dialog
header and footer visible. Tall modal content MUST scroll within the dialog
rather than clip above or below the viewport. Per-modal ad-hoc height/overflow
hacks MUST be removed in favor of this base behavior.

#### Scenario: Tall modal content scrolls within the dialog

- **WHEN** a dialog's content is taller than the viewport (e.g. the add-role
  permission list)
- **THEN** the dialog stays within the viewport, its body scrolls, and the
  header and footer remain reachable (no clipped top or bottom)

### Requirement: Table screens SHALL use the card layout convention

Table screens MUST follow the `/settings/users` layout: the toolbar (search,
filters, primary action) and the `DataTable` live inside a `Card` with a
`CardHeader` (title and optional `CardDescription`) and `CardContent`. This
applies to the roles, subjects, class-templates, years, teachers, students,
homerooms, teaching-assignments, and report-status-board screens.

#### Scenario: A table screen renders inside a card

- **WHEN** an admin opens one of the listed table screens
- **THEN** its search, filters, primary action, and table are contained within a
  `Card` with a `CardHeader` title, consistent with `/settings/users`
