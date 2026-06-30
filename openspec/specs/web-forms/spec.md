# web-forms Specification

## Purpose

Define shared web form behavior and validation normalization requirements.

## Requirements

### Requirement: The default theme SHALL be light for new visitors

`layout.tsx` MUST set `defaultTheme="light"` on the `ThemeProvider`. The
`enableSystem` flag MUST remain true so users can switch to system or dark
via the theme switcher. Returning users retain their previously chosen
preference (persisted by next-themes).

#### Scenario: New visitor sees light theme

- **WHEN** a first-time visitor opens the web app (no localStorage theme
  preference)
- **THEN** the page renders in light theme

### Requirement: The register form SHALL have a password visibility toggle

The register form's password field MUST include an eye/eye-off toggle button
that shows/hides the password, identical in behavior to the login form's
toggle.

#### Scenario: Toggle password visibility on register

- **WHEN** a user clicks the eye icon on the register password field
- **THEN** the password text is shown/hidden accordingly

### Requirement: Required form fields SHALL display a red asterisk

All forms MUST display a red asterisk (`*` in `text-destructive`) next to the
label of each required field. A field is "required" if the corresponding Zod
schema marks it as non-optional with `min(1)` or equivalent. Optional fields
MUST NOT show the asterisk.

#### Scenario: Required field shows asterisk

- **WHEN** a form renders a required field (e.g. "Nama" with
  `z.string().min(1)`)
- **THEN** the label displays "Nama *" with the asterisk in red

#### Scenario: Optional field does not show asterisk

- **WHEN** a form renders an optional field (e.g. "Kode (opsional)" with
  `z.string().optional()`)
- **THEN** the label does not display an asterisk

### Requirement: Subject group code SHALL treat empty string as absent

The subject group create and update command handlers MUST normalize an empty
or whitespace-only `code` string to `None` before validation and storage.
This ensures the frontend's empty-string default for an optional field does
not trigger a spurious validation error.

#### Scenario: Empty string code is accepted

- **WHEN** a subject group is created/updated with `code: ""` (empty string)
- **THEN** the handler normalizes it to `None`; no validation error occurs;
  the subject group is saved without a code
