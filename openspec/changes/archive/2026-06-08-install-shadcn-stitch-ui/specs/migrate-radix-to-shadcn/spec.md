## ADDED Requirements

### Requirement: Replace raw Radix component wrappers
The system SHALL replace raw Radix primitive components in existing pages, features, and custom component files with standard shadcn/ui wrappers (e.g., Switch, Button, Form, Tooltip, Input, Card).

#### Scenario: Verify component migration in pages
- **WHEN** loading dashboard, modules page, login, or registration pages
- **THEN** all UI elements render using shadcn/ui components (mapped under `@/components/ui/*`) instead of direct imports from `@radix-ui/react-*` packages or custom primitive overrides.
