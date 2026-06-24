## ADDED Requirements

### Requirement: Combobox controls rendered inside a Dialog SHALL not clip and SHALL focus their search input

Popver/Command-based combobox controls (`MultiSelect`, `QueryCombobox`,
`QueryMultiSelect`) rendered inside a Radix Dialog MUST display their dropdown
via a Portal so it is not clipped by the Dialog's overflow/stacking context, and
MUST allow the search (`CommandInput`) to receive keyboard focus when the
dropdown opens. The control MUST NOT suppress the popover's open-auto-focus in a
way that prevents the search input from being focused. This behavior MUST be
identical across all three components and any future Dialog-rendered combobox.

#### Scenario: Dropdown is not clipped inside a Dialog

- **WHEN** a `MultiSelect`, `QueryCombobox`, or `QueryMultiSelect` is rendered inside an open Dialog and its trigger is activated
- **THEN** the dropdown content is fully visible (not truncated by the Dialog wrapper) because it is portaled out of the Dialog's clipping context

#### Scenario: Search input receives focus when the dropdown opens

- **WHEN** one of these combobox controls opens its dropdown inside a Dialog
- **THEN** the search input receives keyboard focus and the user can type to filter without an extra click

#### Scenario: Keyboard interaction is preserved

- **WHEN** a combobox dropdown is open inside a Dialog
- **THEN** `Escape` closes the dropdown (and returns focus appropriately) and `Tab` navigation remains usable, with no focus trap deadlock between the Dialog and the popover

### Requirement: Combobox-in-Dialog behavior SHALL be regression-tested

The web app MUST include a component test (Vitest + Testing Library, or
Playwright) that renders each of `MultiSelect`, `QueryCombobox`, and
`QueryMultiSelect` inside a Radix Dialog and asserts both that the dropdown
content is not clipped and that the search input receives focus and accepts
typed input. This guards against the focus/portal workaround regressing.

#### Scenario: Regression test covers all three combobox components

- **WHEN** the web test suite runs
- **THEN** a test for each of the three components rendered in a Dialog passes, asserting non-clipped rendering and focusable, typeable search input
