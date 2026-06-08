# Context

The current `apps/web` project has functional but visually basic pages. We want to refactor the login, register, settings, and dashboard pages using the visual structures, cards, and sidebar configurations from the Stitch design mockup specs as a reference, while implementing them strictly using standard shadcn/ui components (Card, Form, Input, Checkbox, Switch, Badge, Button) rather than raw native HTML.

## Goals / Non-Goals

**Goals:**
- Refactor the login page into a split-pane layout with a bento-style info preview on the left and secure form on the right.
- Refactor the dashboard page to use a dark side-navbar console layout, a top header nav, and card stats.
- Map all visual references from Stitch mockups to corresponding shadcn/ui component equivalents.
- Keep pages fully functional with react-hook-form validation and TanStack Query mutations/queries.

**Non-Goals:**
- Rewriting backend API endpoints or route parameters.
- Changing state validation logic or query hooks.

## Decisions

- **Decision 1: Map native elements to shadcn/ui**: All native inputs, buttons, checklists, select boxes, and badges will be replaced by `<Input>`, `<Button>`, `<Checkbox>`, `<Switch>`, and `<Badge>`.
- **Decision 2: Split pane layout for Login**: We will wrap the login page in `flex flex-col md:flex-row min-h-screen` and render a bento grid illustration on the left.
- **Decision 3: Sidebar console layout for Dashboard**: We will implement a layout structure featuring a fixed sidebar (`w-64`), header bar, and scrollable content canvas.

## Risks / Trade-offs

- **[Risk] Visual breakages or form state mismatches** → **Mitigation**: Bind all shadcn form fields to `useForm` via the `<FormField>` controllers. Keep logic focused.
