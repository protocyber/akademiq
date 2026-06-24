## ADDED Requirements

### Requirement: Formula weight writes SHALL require evaluation-management permission and assignment scope

The service MUST authorize concrete formula weight writes under
`PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`
the same way it authorizes evaluation CRUD. A write is allowed only when **both**
hold:

1. The caller holds the `grade.evaluation.manage` permission; otherwise the
   response is HTTP 403 `FORBIDDEN`.
2. The caller is a `tenant_admin`, **or** the caller is the teacher assigned to
   that `(subject, homeroom, academic_year)` via a teaching assignment; otherwise
   the response is HTTP 403 `NOT_ASSIGNED`.

A valid tenant token plus grading feature entitlement alone MUST NOT be
sufficient to change weights, because weights determine final report-card scores.

#### Scenario: Caller without grade.evaluation.manage is rejected

- **WHEN** a caller whose permissions do not include `grade.evaluation.manage` PUTs weights to the homeroom-scoped formula path
- **THEN** the response is HTTP 403 `FORBIDDEN` and no weights are changed

#### Scenario: Unassigned teacher is rejected

- **WHEN** a `teacher` who holds `grade.evaluation.manage` but is not assigned to the path's `(subject, homeroom, academic_year)` scope PUTs weights
- **THEN** the response is HTTP 403 `NOT_ASSIGNED` and no weights are changed

#### Scenario: Assigned teacher succeeds

- **WHEN** a `teacher` who holds `grade.evaluation.manage` and is assigned to the path's `(subject, homeroom, academic_year)` scope PUTs valid weights (summing to 100)
- **THEN** the response is HTTP 204 and the weights are stored

#### Scenario: Tenant admin succeeds

- **WHEN** a `tenant_admin` PUTs valid weights (summing to 100) to the homeroom-scoped formula path
- **THEN** the response is HTTP 204 and the weights are stored

## MODIFIED Requirements

### Requirement: The service SHALL store per-report-type per-evaluation weighting summing to 100% per subject

For each `(report_type, evaluation)` the service MUST store a `weight` percent.
Because an evaluation is scoped to `(homeroom, subject, year, term)`, a weight is
inherently homeroom-scoped. Weights for a given subject MUST be set under the
homeroom-scoped path
`PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`,
NOT under the old `(report_type, subject)`-only path. The same evaluation MAY
contribute to several report types with different weights.

When weights are saved for a class, the service MUST replace only that
homeroom's formula rows for the `(report_type, subject)` — it MUST NOT delete or
modify formula rows belonging to any other homeroom, even when those other
homerooms teach the same subject under the same report type. A subject's formula
within a report type is **valid only when its evaluation weights sum to exactly
100**; otherwise the subject is treated as not-configured and rejected. The
sum-to-100 check applies to the weights submitted for that single
`(report_type, homeroom, subject)` scope.

#### Scenario: Weights summing to exactly 100 are accepted

- **WHEN** a teacher sets `{ UH1: 25, UTS: 75 }` for a subject within a report type for a specific homeroom via `PUT /report-types/{rt}/homerooms/{homeroom}/formulas/{subject}`
- **THEN** the weights are stored and the subject counts as configured for that report type and homeroom

#### Scenario: Weights not summing to 100 are rejected

- **WHEN** a teacher sets weights for a `(report_type, homeroom, subject)` that sum to anything other than 100
- **THEN** the response is HTTP 400 `INVALID_WEIGHTS` and the subject remains unconfigured for that homeroom

#### Scenario: One evaluation contributes to multiple report types

- **WHEN** evaluation UH1 is given weight 25 in report type A and weight 10 in report type B
- **THEN** both weights are stored independently and each report type computes UH1's contribution with its own weight

#### Scenario: Saving one homeroom's weights does not affect another homeroom

- **WHEN** homeroom 7A and homeroom 7B each have their own `SAS` evaluation under the same report type and subject, and a teacher saves weights for homeroom 7A
- **THEN** only homeroom 7A's formula rows are replaced and homeroom 7B's formula rows remain unchanged

#### Scenario: Old subject-only formula path is no longer available

- **WHEN** a client calls the former `PUT /report-types/{report_type_id}/formulas/{subject_id}` path
- **THEN** the response is HTTP 404 (route removed) and no weights are changed
