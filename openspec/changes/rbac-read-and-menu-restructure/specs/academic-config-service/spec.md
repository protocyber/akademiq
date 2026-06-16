## ADDED Requirements

### Requirement: Academic Config GET endpoints SHALL require academic.config.read

The tenant-scoped GET endpoints of the Academic Config service MUST require
`academic.config.read` in addition to the existing feature entitlement. This covers
academic years (list/get), curriculum versions (list), subjects (list), grading policy
(get), and class templates (list). Callers without the permission MUST receive HTTP 403
with code `FORBIDDEN`.

#### Scenario: Listing academic years without the read permission

- **WHEN** a caller without `academic.config.read` calls `GET /api/v1/academic-config/academic-years`
- **THEN** the response is HTTP 403

#### Scenario: Reading with the permission succeeds

- **WHEN** a caller holding `academic.config.read` calls the same endpoint
- **THEN** the response is HTTP 200 with the year list
