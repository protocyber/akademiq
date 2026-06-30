# term-evaluation-templates Specification

## Purpose

Defines the per-term evaluation template contract — template CRUD, weight templates, materialization on teaching assignment, backfill, and unmaterialized-assignment reporting.
## Requirements
### Requirement: The grading service SHALL manage a per-term evaluation template

The service MUST provide evaluation-template CRUD under `/api/v1/grading/evaluation-templates`, tenant-scoped from the JWT. A template entry captures `{ term_id, code, name, position }` and defines one default assessment column (e.g. "UH1", "UTS") for the whole term. `tenant_id` MUST be resolved from the term (via the `valid_term` projection) and never taken from the client. `code` MUST be unique per `(tenant_id, term_id)`. Template writes MUST require the academic-config write permission (tenant admin).

#### Scenario: Admin defines a template evaluation for a term

- **WHEN** a tenant admin POSTs `{ term_id, code: "UH1", name: "Ulangan Harian 1", position: 1 }` to `/evaluation-templates`
- **THEN** the response is HTTP 201 with the stored template entry and `tenant_id` resolved from the term

#### Scenario: Duplicate template code in the same term is rejected

- **WHEN** an admin POSTs a template entry whose `code` already exists for that `term_id`
- **THEN** the response is HTTP 409 `DUPLICATE_EVALUATION_CODE` and nothing is created

#### Scenario: Template entries are listed for a term in column order

- **WHEN** a client GETs `/evaluation-templates?term_id=...`
- **THEN** the response lists that term's template entries ordered by `position`

### Requirement: The grading service SHALL manage per-term weight templates

The service MUST let an admin set, per report type of the term, a weight for each template evaluation under `/api/v1/grading/report-types/{report_type_id}/formula-templates`. A weight-template row links `{ report_type_id, evaluation_template_id, weight }` and MUST be unique per `(report_type_id, evaluation_template_id)`. The report type MUST belong to the same term as the referenced template evaluation. The weights for a report type MUST sum to 100.

#### Scenario: Admin sets template weights summing to 100

- **WHEN** an admin PUTs weights for a report type where the template-evaluation weights total 100
- **THEN** the response is HTTP 200 and the weight template is stored

#### Scenario: Weights not summing to 100 are rejected

- **WHEN** an admin PUTs template weights that do not total 100
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` and nothing is stored

#### Scenario: Template weight referencing another term is rejected

- **WHEN** an admin submits a weight whose `evaluation_template_id` belongs to a different term than the report type
- **THEN** the response is HTTP 400 `VALIDATION_ERROR` and nothing is stored

### Requirement: The grading service SHALL materialize concrete evaluations from a term template on teaching assignment

When a `teacher.assigned` event is consumed, the service MUST materialize concrete evaluations from the term template into each qualifying term of the assignment's academic year. A term qualifies only when its status is `Draft` or `Active` and a template exists for it. Materialization MUST be idempotent: concrete evaluations are inserted using the existing unique tuple `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` with conflict-ignore semantics, so event redelivery creates no duplicates. When a matching report type exists for the term, concrete `report_formula` weights MUST also be materialized from the weight template, also idempotently.

#### Scenario: New assignment auto-creates the term's evaluation list

- **WHEN** `teacher.assigned` is consumed for `(homeroom, subject, year)` and the year has a Draft/Active term with a template
- **THEN** concrete evaluations matching the template entries exist for that `(homeroom, subject, year, term)`

#### Scenario: Redelivery does not duplicate evaluations

- **WHEN** the same `teacher.assigned` event is consumed twice
- **THEN** the concrete evaluation set is unchanged after the second delivery

#### Scenario: Missing report type defers weight materialization

- **WHEN** materialization runs but no report type exists yet for the term
- **THEN** the concrete evaluation list is still created and no weights are materialized

#### Scenario: Closed or archived term is skipped

- **WHEN** the assignment's year has a term whose status is Closed or Archived
- **THEN** no evaluations are materialized for that term

### Requirement: The grading service SHALL backfill evaluations for assignments lacking them

The service MUST expose an endpoint that applies a term's template to every teaching assignment in that term that currently has **no evaluations at all**, creating the concrete evaluations (and weights where report types exist). "No evaluations" MUST be determined per assignment by the absence of any `evaluation` row for that `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id)` — NOT by the absence of a same-coded evaluation. An assignment that already has one or more evaluations MUST be skipped entirely, even when the template defines a code that assignment does not yet have. This skip predicate MUST match the one used by the unmaterialized-assignment count so the two stay consistent. The operation MUST be idempotent, MUST require the academic-config write permission, and MUST return counts of assignments filled and skipped.

#### Scenario: Apply template fills only assignments with no evaluations

- **WHEN** an admin POSTs the apply action for a term with template entries
- **THEN** assignments in that term with zero evaluations receive the template's evaluations and assignments that already have evaluations are left unchanged

#### Scenario: Assignment with a different-coded evaluation is skipped

- **WHEN** an assignment already has an evaluation `SA` and the term template defines `SAS`, and the admin POSTs the apply action
- **THEN** no `SAS` evaluation is inserted for that assignment and it is reported as skipped

#### Scenario: Apply is idempotent

- **WHEN** the apply action is invoked twice in a row
- **THEN** the second invocation creates no additional evaluations and reports them as skipped

#### Scenario: Skip predicate matches the unmaterialized count

- **WHEN** the unmaterialized-assignment count for a term reports zero
- **THEN** the apply action for that term creates no evaluations

### Requirement: The grading service SHALL report assignments lacking evaluations for a term

The service MUST expose an endpoint returning the count of teaching assignments in a term that have no evaluations, so clients can surface a nudge. The count MUST be computed locally from the grading service's own projections without calling other services.

#### Scenario: Count reflects unmaterialized assignments

- **WHEN** a client GETs the unmaterialized-assignment count for a term with 12 assignments and none materialized
- **THEN** the response reports a count of 12

#### Scenario: Count is zero after backfill

- **WHEN** the count is requested after the apply action has filled every assignment
- **THEN** the response reports a count of 0

