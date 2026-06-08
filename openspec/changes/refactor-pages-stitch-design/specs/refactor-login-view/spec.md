## ADDED Requirements

### Requirement: Split login layout structure
The system SHALL display a split layout on large screens, featuring a branding/bento card grid illustration on the left and a secure login form on the right.

#### Scenario: Verify layout responsive split
- **WHEN** loading the login page on a desktop viewport
- **THEN** it displays a split-pane layout with the bento preview section taking up at least half the width and the secure form section taking up the remainder.

### Requirement: Use shadcn components in login form
The login page SHALL use shadcn/ui `<Card>`, `<Form>`, `<FormField>`, `<Input>`, and `<Button>` components instead of native HTML elements.

#### Scenario: Verify form elements rendering
- **WHEN** viewing the login form
- **THEN** input fields render with leading Lucide icons for person/lock, and the submit button displays an arrow icon.
