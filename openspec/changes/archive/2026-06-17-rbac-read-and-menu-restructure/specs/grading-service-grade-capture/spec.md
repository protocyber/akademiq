## ADDED Requirements

### Requirement: Grading read endpoints SHALL require grade.read or report.read

The grading GET endpoints SHALL enforce read permissions:

- Grade/evaluation reads — `GET /evaluations`, `GET /class-grades`, `GET /students/{id}/grades`,
  `GET /report-formulas`, `GET /subject-report-scores` — MUST require `grade.read`.
- Report-card reads — `GET /report-types`, `GET /report-cards`, `GET /report-cards/{id}` — MUST
  require `report.read`.
- The published-card portal endpoints (`GET /me/report-cards[/{student_id}]`) MUST require
  `report.read` AND pass the ownership verification defined by `secure-published-report-card`.

Callers without the required permission MUST receive HTTP 403 with code `FORBIDDEN`.

#### Scenario: Reading class grades without grade.read

- **WHEN** a caller without `grade.read` calls `GET /class-grades`
- **THEN** the response is HTTP 403

#### Scenario: A teacher reads report types

- **WHEN** a `teacher` holding `report.read` calls `GET /report-types`
- **THEN** the response is HTTP 200
