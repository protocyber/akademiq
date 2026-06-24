## MODIFIED Requirements

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
