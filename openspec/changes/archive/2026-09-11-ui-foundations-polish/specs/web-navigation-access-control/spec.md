## ADDED Requirements

### Requirement: The curriculum selector SHALL be hidden unless multiple options exist

The header academic-scope curriculum `<Select>` MUST be rendered only when the
selected year has more than one curriculum version. When exactly one version
exists, the UI MUST auto-select it into scope but hide the control; when none
exist, the control MUST stay hidden. The control MUST NOT flicker during loading.

#### Scenario: Single curriculum hides the selector but sets scope

- **WHEN** the selected year has exactly one curriculum version
- **THEN** the curriculum selector is not shown and that version is selected as
  the active curriculum scope

#### Scenario: Multiple curricula show the selector

- **WHEN** the selected year has two or more curriculum versions
- **THEN** the curriculum selector is rendered and lets the user choose

### Requirement: The user-menu avatar SHALL be visible in light mode

The header user-menu avatar circle MUST have sufficient contrast against the
light header background so it is clearly visible (not near-white on white), while
remaining visible in dark mode.

#### Scenario: Avatar is visible on the light header

- **WHEN** the app is in light mode and the header renders the user-menu avatar
- **THEN** the avatar circle is clearly distinguishable from the header
  background

### Requirement: Academic scope selectors SHALL stack vertically in the mobile sidebar

When the academic-scope selectors are rendered in the mobile sidebar, they MUST
use a vertical (stacked, full-width) layout so they do not overflow the narrow
sidebar. The header (desktop) placement MAY remain horizontal.

#### Scenario: Scope selectors do not overflow the mobile sidebar

- **WHEN** the academic-scope selectors render inside the mobile sidebar
- **THEN** the year, semester, and curriculum selectors stack vertically at full
  width without horizontal overflow

### Requirement: Route-driven navigation shells SHALL use the shared Tabs styling

The web app MUST present the route-driven navigation shells
(`academic-settings.tsx`, `academic-ops-page.tsx`) using the shared `Tabs`
component in route-driven mode (`TabsTrigger asChild` wrapping `<Link>`, active
derived from pathname), preserving per-view URLs.

#### Scenario: Academic settings nav uses Tabs styling with working URLs

- **WHEN** an admin uses the academic settings navigation
- **THEN** the entries render as tabs and selecting one navigates to its URL,
  with the current page's tab marked active
