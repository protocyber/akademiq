# report-card-access-control Specification

## Purpose
Defines requirements for self/guardian-scoped report-card endpoints in the grading service, ensuring that published report cards are only accessible to authorized users (the student themselves or their linked guardians) through ownership verification via the `student_authz` projection.

## Requirements

### Requirement: The service SHALL expose self/guardian-scoped report-card endpoints

The grading service MUST expose ownership-scoped portal endpoints that never accept
an arbitrary `student_id` as the sole authority for access:

- `GET /api/v1/grading/me/report-cards?academic_year_id=` — returns the report cards
  the caller is authorized to see: their own (when the caller's IAM user is linked to
  a student via `student.user_id`) plus every child linked via the `guardian` relation.
- `GET /api/v1/grading/me/report-cards/{student_id}?academic_year_id=` — returns the
  detail for one student, and MUST be rejected with HTTP 403 when
  `(auth.user_id, student_id)` does not exist in the `student_authz` projection.

Both endpoints MUST require `report.read` permission and MUST restrict returned cards
to status `Published` or `Archived` only (pre-publish cards MUST NOT be revealed and
their existence MUST NOT be leaked — return 404, not 403, when the card exists but is
not yet published).

The legacy `GET /api/v1/grading/students/{student_id}/report-card` endpoint MUST be
removed or restricted to privileged staff (tenant admin / principal) using the console
authorization path; it MUST NOT serve student/parent callers by `student_id`.

#### Scenario: Guardian with multiple children lists all of them

- **WHEN** a guardian whose IAM user is linked to two students GETs `/me/report-cards?academic_year_id=Y`
- **THEN** the response is HTTP 200 with both children's published report cards for year `Y`

#### Scenario: Detail for an owned child succeeds

- **WHEN** a guardian GETs `/me/report-cards/{child_student_id}?academic_year_id=Y` for a student they are linked to
- **THEN** the response is HTTP 200 with that child's published report card

#### Scenario: Detail for a non-owned student is forbidden

- **WHEN** a caller GETs `/me/report-cards/{other_student_id}` for a student not linked to their IAM user
- **THEN** the response is HTTP 403

#### Scenario: A pre-publish card is not revealed

- **WHEN** a caller GETs `/me/report-cards/{owned_student_id}` for a year whose card is still in `Draft`, `HomeroomReview`, or `PrincipalApproval`
- **THEN** the response is HTTP 404 (existence is not revealed)

### Requirement: Ownership SHALL be verified through the `student_authz` projection

The grading service MUST resolve report-card ownership exclusively via a
`student_authz(tenant_id, student_id, user_id, relation)` projection table that is
populated by consuming `student.account_linked`, `guardian.linked`, and
`guardian.unlinked` events from academic-ops. `relation` MUST be `self` (the student's
own account) or `guardian`. A caller MUST be treated as authorized for a student only
when a matching `(tenant_id, student_id, user_id)` row exists. Direct DB lookups by
`student_id` against the source-of-truth academic-ops data MUST NOT be used for
authorization.

#### Scenario: Link event grants access

- **WHEN** academic-ops emits `guardian.linked{user_id, student_id}` and grading consumes it
- **THEN** a subsequent `GET /me/report-cards/{student_id}` by that user is authorized

#### Scenario: Unlink event revokes access

- **WHEN** academic-ops emits `guardian.unlinked{user_id, student_id}` and grading consumes it
- **THEN** a subsequent `GET /me/report-cards/{student_id}` by that user is HTTP 403
