# refactor-dashboard-view Specification

## Purpose

Defines the requirements and scenarios for the dashboard page layout and styling.

## Requirements

### Requirement: Sidebar console layout
The dashboard page SHALL implement a sidebar console layout, containing a left side-navbar with modular navigation links and a main scrollable content canvas.

#### Scenario: Verify sidebar rendering
- **WHEN** loading the dashboard page
- **THEN** it displays a fixed left side-navbar containing school branding and navigation links, with the active route highlighted.

### Requirement: Premium card stats grid
The dashboard page SHALL render overview stats inside elevated card components styled with custom shadows and rounded corners.

#### Scenario: Verify stats rendering
- **WHEN** viewing the overview grid
- **THEN** stat containers use the shadcn `<Card>` structure with a custom level 1 shadow and `rounded-lg` borders.
