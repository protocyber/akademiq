# web-theming Specification

## Purpose
TBD - created by archiving change shell-and-theming. Update Purpose after archive.
## Requirements
### Requirement: The web app SHALL support light, dark, and system color themes

The web app MUST provide class-based theming using a `next-themes` provider
mounted at the root layout. It MUST support three explicit modes — `light`,
`dark`, and `system` — where `system` follows the operating-system color-scheme
preference. The selected mode MUST persist across reloads and navigations, and
the initial paint MUST NOT flash the wrong theme.

#### Scenario: User selects dark mode

- **WHEN** the user picks "dark" from the theme switcher
- **THEN** the `dark` class is applied to the document root, the dark token set
  takes effect, and the choice persists after a full reload

#### Scenario: System mode follows the OS

- **WHEN** the user selects "system" and the OS is in dark mode
- **THEN** the app renders dark, and switching the OS preference flips the app
  without a manual change

#### Scenario: No flash of wrong theme

- **WHEN** a page is loaded with a persisted non-default theme
- **THEN** the first paint already reflects the persisted theme

### Requirement: The header SHALL expose a theme switcher

A theme switcher offering light/dark/system MUST be present in the top-right
header, adjacent to the user control, on every authenticated screen.

#### Scenario: Switcher is reachable from any page

- **WHEN** the user is on any authenticated screen
- **THEN** the theme switcher is visible in the top-right header and changes the
  theme on selection

### Requirement: App shell surfaces SHALL use theme tokens

Shell surfaces that should follow the theme MUST use the semantic theme tokens
(e.g. `bg-background`, `bg-card`, `text-foreground`, `border-border`) rather than
hardcoded palette values. Any surface intentionally fixed to one appearance
(e.g. a permanently dark sidebar) MUST be a documented, deliberate exception.

#### Scenario: Themed surfaces invert with the theme

- **WHEN** the theme switches between light and dark
- **THEN** token-driven shell surfaces update accordingly and no themed surface
  remains stuck in the opposite scheme by accident

