# stitch-design-theme Specification

## Purpose

Defines the requirements and scenarios for integrating colors, border-radius, and typography tokens from the Stitch design system (specifically Emerald Nocturne and EduCore Narrative) into the web application styling.

## Requirements

### Requirement: Design tokens integration
The system SHALL map the colors, border-radius, and typography tokens from the Stitch design system (specifically Emerald Nocturne) into CSS variables inside `apps/web/src/app/globals.css` and configure them in `apps/web/tailwind.config.ts`.

#### Scenario: Verify application of design tokens
- **WHEN** the user opens the web application
- **THEN** elements styled with Tailwind semantic tokens (e.g., `bg-background`, `text-primary`, `bg-card`) render according to the Emerald Nocturne colors (e.g., primary as `#10b981`, background as `#0b1326`, and rounded-md as `0.5rem`).
