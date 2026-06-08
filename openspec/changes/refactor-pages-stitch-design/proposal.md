## Why

Currently, the frontend views (login, register, dashboard, module settings) are plain, basic layouts. To build a premium enterprise school management software, we need to refactor these pages to match the Stitch design mockups (split-pane layouts, left sidebar dashboards, bento grids, and clear typography hierarchy) while implementing them strictly using standard shadcn/ui components rather than raw native HTML.

## What Changes

- Refactor `src/app/login/page.tsx` into a modern split layout (bento preview on the left, secure form built with shadcn `<Card>` and `<Form>` on the right).
- Refactor `src/app/dashboard/page.tsx` into a professional sidebar console layout (dark left side-navbar with navigation, top stats card overview grid, and module listings).
- Ensure all interactive elements (inputs, buttons, checklists, switches, badges) are mapped to corresponding shadcn/ui components (`<Input>`, `<Button>`, `<Checkbox>`, `<Switch>`, `<Badge>`).
- Utilize the mapped Google Fonts (Plus Jakarta Sans and Inter) and HSL variable tokens for colors and border radius scaling.

## Capabilities

### New Capabilities
- `refactor-login-view`: Rebuild the login page using a split illustration bento panel and a secure shadcn form.
- `refactor-dashboard-view`: Rebuild the main dashboard with a left side-navbar console layout, stats grid, and module list.
- `refactor-register-view`: Update the registration step-form to follow the premium visual spec.

### Modified Capabilities
<!-- None -->

## Impact

- **Affected Code**: `apps/web/src/app/login/page.tsx`, `apps/web/src/app/register/register-client.tsx`, `apps/web/src/app/dashboard/page.tsx`, and `apps/web/src/app/settings/modules/page.tsx`.
- **Dependencies**: No new npm dependencies, utilizes existing shadcn/ui components and Tailwind configuration.
