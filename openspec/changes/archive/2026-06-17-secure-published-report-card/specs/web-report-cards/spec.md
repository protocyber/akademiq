## ADDED Requirements

### Requirement: The student/parent portal SHALL NOT accept a free-text student id

The published report-card portal page (`/portal/report-card`) MUST NOT render a
free-text `student_id` input. Instead it MUST call the server-scoped
`GET /api/v1/grading/me/report-cards` endpoint to obtain the set of students the
signed-in user may view (self and/or linked children) and present them as a
server-controlled selector ("Pilih anak"). The page MUST request a specific card via
the ownership-validated `GET /api/v1/grading/me/report-cards/{student_id}` endpoint,
never by sending an arbitrary id the user typed. A `?student_id=` deep link MAY be
honored only after the backend confirms ownership.

#### Scenario: Portal shows only the caller's students

- **WHEN** a guardian opens `/portal/report-card`
- **THEN** the page lists only their linked children in a selector and shows no free-text student id input

#### Scenario: Selecting a child loads its report card

- **WHEN** the guardian selects a child and an academic year
- **THEN** the page fetches and displays that child's published report card via the `me/report-cards/{student_id}` endpoint

#### Scenario: A non-owned deep link is rejected

- **WHEN** the user opens `/portal/report-card?student_id=<not-their-child>`
- **THEN** the page shows a not-available/forbidden state and does not render another student's card
