## ADDED Requirements

### Requirement: Step-based registration form
The registration page SHALL present a progress header indicator representing steps of school details, plan selection, and admin credentials.

#### Scenario: Verify register steps rendering
- **WHEN** loading the registration page
- **THEN** it displays an active step circle and labels, and render the card sections using shadcn `<Card>` wrappers.
