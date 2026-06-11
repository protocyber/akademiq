## MODIFIED Requirements

### Requirement: Roadmap SHALL declare deferred work explicitly

The document MUST include a "Deferred / Future Phases" section listing
attendance, promotion, notification, file/storage, payment provider
integration, and email/SMS delivery as out of scope for the foundational
phases with a one-line rationale each. **Grading & report cards SHALL NOT be
listed as deferred**; they are promoted into numbered phases delivered by
`mvp-grading-grade-capture` (grade capture) and `mvp-report-card-workflow`
(report card approval workflow), which depend on Academic Operations
(`mvp-academic-ops`) having shipped enrollment and teaching assignments.

#### Scenario: Deferred work is enumerated without grading

- **WHEN** a contributor reads the deferred section
- **THEN** attendance, promotion, notification, file/storage, payment provider, and email/SMS each appear with a brief rationale, and grading & report cards do NOT appear in the deferred list

#### Scenario: Grading phases are numbered with explicit dependencies

- **WHEN** a contributor reads the phase list after Academic Operations
- **THEN** a grade-capture phase (owning service `grading-service`, delivering change `mvp-grading-grade-capture`) and a report-card-workflow phase (delivering change `mvp-report-card-workflow`) are present, each declaring its dependency on the Academic Operations phase
