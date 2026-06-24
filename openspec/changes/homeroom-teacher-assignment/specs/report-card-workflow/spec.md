## MODIFIED Requirements

### Requirement: The service SHALL store per-report-type per-evaluation weighting summing to 100% per subject

For each `(report_type, evaluation)` the service MUST store a `weight` percent.
Because an evaluation is scoped to `(homeroom, subject, year, term)`, a weight is
inherently homeroom-scoped. Weights for a given subject MUST be set under the
homeroom-scoped path `PUT /report-types/{report_type_id}/homerooms/{homeroom_id}/formulas/{subject_id}`.
The same evaluation MAY contribute to several report types with different weights.
A subject's formula within a report type is **valid only when its evaluation
weights sum to exactly 100**; otherwise the subject is treated as not-configured.

#### Scenario: class_scope homeroom_teacher uses the designation projection

- **WHEN** a user holding the `homeroom_teacher` role is designated as walikelas of homeroom X via the `homeroom_teacher_authz` projection
- **THEN** `class_scope().homeroom_teacher` returns `true` for that user and homeroom, allowing HomeroomReview → HomeroomApprove transition

#### Scenario: Undesignated teacher cannot perform homeroom approval

- **WHEN** a user holding the `homeroom_teacher` role has a subject teaching assignment in homeroom X but is NOT the designated walikelas
- **THEN** `class_scope().homeroom_teacher` returns `false` and the HomeroomApprove transition is rejected with HTTP 403
