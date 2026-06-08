## Why

Currently, the web application in `apps/web` uses a mix of raw Radix UI primitives and custom-styled components. This approach leads to boilerplate code, inconsistent UI styling, and slower development speed. Implementing shadcn/ui configured with the custom Stitch design system (specifically Emerald Nocturne and other internal design specs) will provide a cohesive component library that conforms to our engineering standards and design specs, speeding up UI development and ensuring visual consistency.

## What Changes

- Install and configure shadcn/ui in the `apps/web` project.
- Integrate the Stitch design tokens (colors, typography, spacing, border-radius) defined in `docs/internal/stitch_design/` (particularly `emerald_nocturne`) into the Tailwind CSS configuration.
- Add/update required shadcn/ui components (e.g., Switch, Button, Form, Card, Tooltip, Input, Alert, Skeleton).
- Replace raw Radix component primitives and imports within existing pages and custom components in `apps/web` with unified shadcn/ui components.

## Capabilities

### New Capabilities
- `install-shadcn`: Install and configure shadcn/ui inside the web app workspace.
- `stitch-design-theme`: Apply the Emerald Nocturne design tokens from the Stitch designs to the Tailwind and CSS variables.
- `migrate-radix-to-shadcn`: Refactor all files in `apps/web` currently utilizing raw Radix primitives to use the newly prepared shadcn/ui components.

### Modified Capabilities
<!-- None -->

## Impact

- **Affected Code**: `apps/web/package.json`, `apps/web/tailwind.config.ts`, `apps/web/src/app/globals.css`, `apps/web/src/components/ui/*`, and any files using raw Radix imports.
- **Dependencies**: Adds `@radix-ui` wrapper UI components managed by shadcn/ui, `tailwindcss-animate`, and potentially other shadcn dependencies.
