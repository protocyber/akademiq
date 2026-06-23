## ADDED Requirements

### Requirement: The grade-entry screen SHALL resolve teacher identity without admin IAM endpoints

The `/grading/entry` screen MUST resolve the assigned teacher's display name, email, and account-link status from the academic-ops teachers data it already loads, and MUST NOT call any tenant-admin-gated IAM endpoint (e.g. `GET /iam/tenants/me/users`). Non-admin teachers MUST be able to use the screen without receiving a 403 from a user-directory lookup.

#### Scenario: Teacher info shows without an admin lookup

- **WHEN** a non-admin teacher opens `/grading/entry`
- **THEN** the assigned teacher's name and account status are shown from academic-ops data and no request is made to `/iam/tenants/me/users`

#### Scenario: No 403 for a non-admin

- **WHEN** a teacher who does not hold `user.read` loads the screen
- **THEN** no admin IAM request is issued and the screen loads without a permission error

### Requirement: The grade-entry screen SHALL surface unmaterialized-assignment and weight warnings

The screen MUST show a nudge when teaching assignments in the active term lack evaluations, using the grading service's unmaterialized-assignment count. The screen MUST show a non-blocking warning when a report type's subject weights no longer total 100% (e.g. after a teacher added an evaluation outside the template) or when no report type exists for the term. Neither condition blocks grade entry.

#### Scenario: Nudge appears when assignments lack evaluations

- **WHEN** the active term reports N assignments without evaluations
- **THEN** the screen shows a banner indicating N assignments have no evaluations

#### Scenario: Weight drift is warned, not blocked

- **WHEN** a report type's subject weights total other than 100%
- **THEN** the screen shows a warning and still allows grade entry
