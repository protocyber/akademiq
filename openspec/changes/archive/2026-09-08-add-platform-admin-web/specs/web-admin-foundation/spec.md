## ADDED Requirements

### Requirement: Nuxt 4 app in apps/web-admin submodule

The platform admin frontend SHALL be a Nuxt 4 (v4.4.8) application living in the
`apps/web-admin` git submodule, using Nuxt UI 4 (v4.9.0) and Tailwind v4 (v4.3.2).

#### Scenario: App boots in development

- **WHEN** the app is started in dev mode on its configured port
- **THEN** the Nuxt 4 app serves and renders the admin shell without errors

### Requirement: Nuxt UI components only

All interactive UI SHALL be composed from Nuxt UI 4 components. Native interactive
HTML controls (`<button>`, `<input>`, `<select>`, `<textarea>`, bare `<form>`) MUST
NOT be used in pages and components. Structural elements remain allowed.

#### Scenario: No native interactive controls

- **WHEN** a page or component renders an interactive control
- **THEN** it uses a Nuxt UI component, not a native HTML interactive element

### Requirement: GitHub-like theme with dark default

The app SHALL present a GitHub-like visual style and support both light and dark
modes, with **dark mode as the default** on first load.

#### Scenario: First load is dark

- **WHEN** a user opens the app for the first time with no stored preference
- **THEN** the app renders in dark mode

#### Scenario: Theme toggle persists

- **WHEN** a user switches to light mode
- **THEN** the preference is persisted and applied on the next visit

### Requirement: TanStack Vue Query provider mounted once

A TanStack Vue Query client SHALL be provided once at the app root so all data
hooks share one client.

#### Scenario: Query client available app-wide

- **WHEN** any page mounts a query
- **THEN** it resolves against the single app-level Vue Query client

### Requirement: Circular loading indicator for loading data state

Every component that depends on data SHALL show a circular loading indicator while
its TanStack Vue Query state is loading, following a two-tier convention (inline
spinner on action controls; layout-region indicator on first paint).

#### Scenario: Loading shows a spinner

- **WHEN** a component's query is in the loading state
- **THEN** the component renders a circular loading indicator until data resolves
