## ADDED Requirements

### Requirement: Grade-entry filter selections SHALL be reflected in the URL

The `/grading/entry` screen MUST persist its homeroom and subject selections in
URL search params (`homeroom_id`, `subject_id`) as the single source of truth,
using the project's established parse/serialize pattern (as on
`/teaching-assignments`). Selections MUST survive a page refresh and be
applicable via a deep link, and navigating back/forward MUST restore the
corresponding selection. Changing the academic year (a header-level scope, not a
URL filter) MUST clear the homeroom and subject params. The academic-year scope
itself is NOT part of the page filter URL.

#### Scenario: Selection survives refresh

- **WHEN** a teacher selects a homeroom and subject and then refreshes the page
- **THEN** both selections are restored from the URL search params and the grade grid reloads for that scope

#### Scenario: Deep link applies the selection

- **WHEN** a teacher opens `/grading/entry?homeroom_id=H&subject_id=S`
- **THEN** the page loads with that homeroom and subject selected and the grid rendered for that scope

#### Scenario: Back and forward restore selections

- **WHEN** a teacher changes the subject selection and then navigates back
- **THEN** the previous subject selection is restored from the URL

#### Scenario: Academic-year change clears the class and subject

- **WHEN** the header academic-year scope changes
- **THEN** the `homeroom_id` and `subject_id` params are cleared from the URL, resetting the selection

### Requirement: Report-cards filter selections SHALL be URL-param-driven

The `/grading/report-cards` screen MUST derive its report-type and class
selections from URL search params (`report_type_id`, `homeroom_id`) as the
single source of truth via the project's parse/serialize pattern, rather than
seeding local state from the URL once and writing back via an effect. Selections
MUST survive refresh, apply via deep link, and round-trip across back/forward
navigation.

#### Scenario: Report-cards selection survives refresh

- **WHEN** an admin selects a report type and class and refreshes
- **THEN** both selections are restored from the URL and the board reloads for that scope

#### Scenario: Report-cards deep link applies the selection

- **WHEN** a user opens `/grading/report-cards?report_type_id=R&homeroom_id=H`
- **THEN** the page loads with that report type and class selected

#### Scenario: Report-cards back/forward round-trips

- **WHEN** the user changes the class selection and navigates back
- **THEN** the previous class selection is restored from the URL
