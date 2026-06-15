## MODIFIED Requirements

### Requirement: The shared date picker SHALL be compact and support month/year dropdown navigation

The shared shadcn `DatePicker` (and its `Calendar`) MUST render compactly,
consistent with surrounding form controls, and MUST offer a caption with month
and year dropdowns so the user can jump directly to a month and year without
stepping through months via the previous/next chevrons. The component MUST
preserve its existing public contract: the `value`/`onChange` `yyyy-MM-dd` string
interface, `placeholder`, `disabled`, and `aria-*` attributes. A configurable
year range MUST be wide enough for common cases (e.g. birthdates and academic
years).

#### Scenario: Jump to a distant month and year

- **WHEN** the user opens the date picker and uses the month and year dropdowns
- **THEN** the calendar navigates directly to that month/year without repeated
  chevron clicks, and selecting a day emits the same `yyyy-MM-dd` value as before

#### Scenario: Existing consumers are unaffected

- **WHEN** any current consumer renders the date picker with its existing props
- **THEN** it works without call-site changes and selection still produces a
  `yyyy-MM-dd` string

#### Scenario: Accessibility preserved

- **WHEN** the picker is used with assistive technology
- **THEN** the trigger and dropdowns expose accessible labels and the existing
  `aria-describedby`/`aria-invalid` attributes still apply
