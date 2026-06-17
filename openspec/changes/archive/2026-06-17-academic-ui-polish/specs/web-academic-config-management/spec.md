## ADDED Requirements

### Requirement: The create academic-year form SHALL omit settings that require a saved year

The **create** Tahun Ajaran form SHALL contain only identity fields (name, start date, end
date). It SHALL NOT show the grading-policy or curriculum-version controls; those SHALL be
available only in the **edit** form, after the year exists.

#### Scenario: Create form shows only identity fields

- **WHEN** the user opens the create Tahun Ajaran form
- **THEN** only name and start/end dates are shown — no grading-policy or curriculum-version controls

#### Scenario: Edit form still exposes the settings

- **WHEN** the user opens the edit form for an existing year
- **THEN** the grading-policy and curriculum-version sections are available

### Requirement: Academic-year status SHALL be shown as a horizontal timeline with a next-status action

The academic-year status control SHALL be presented as a horizontal timeline of the lifecycle
(Planning → Configuration → Active → Locked → Finalizing → Closed → Archived), highlighting
the current status, with a button beneath it to advance to the next status. The dropdown-style
status selector SHALL be replaced by this timeline.

#### Scenario: Timeline highlights the current status

- **WHEN** the user views a year whose status is `Active`
- **THEN** the timeline shows the full lifecycle with `Active` highlighted and earlier stages marked complete

#### Scenario: Advancing to the next status

- **WHEN** the user clicks the next-status button beneath the timeline
- **THEN** the year transitions to the next lifecycle status and the timeline updates

#### Scenario: No next status at the end of the lifecycle

- **WHEN** the year is `Archived` (terminal)
- **THEN** the next-status button is absent or disabled
