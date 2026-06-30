## ADDED Requirements

### Requirement: An operator tool SHALL detect duplicate evaluations and split formulas

The platform MUST provide an operator command (an `akademiq` CLI subcommand or a
script wrapped by it) that, for a given tenant and optional term, reports:
- teaching assignments that hold more than one evaluation for the same
  `(homeroom, subject, year, term)`, and
- `report_formula` rows that reference an evaluation which has no recorded grades.

The command MUST default to report-only (no mutation) and MUST print the target
resources (ids and codes) it found. It MUST NOT print secrets, tokens, or
password hashes.

#### Scenario: Report mode lists duplicates without changing data

- **WHEN** an operator runs the command in its default (report) mode for a tenant whose assignments hold duplicate evaluations
- **THEN** the command lists the affected assignments and formulas and makes no changes

#### Scenario: Report mode lists nothing for clean data

- **WHEN** the command runs for a tenant with exactly one evaluation per assignment and no orphaned formulas
- **THEN** the command reports no duplicates and no formula issues

### Requirement: The cleanup tool SHALL delete duplicates only with explicit confirmation

The cleanup tool MUST require an explicit confirmation flag before deleting any
duplicate evaluations (and their dependent grades and formula rows). When confirmed, the tool MUST keep the
evaluation that has recorded grades and remove the duplicate; when both or neither
duplicate evaluation has grades, the tool MUST NOT auto-delete and MUST instead
report the conflict for manual resolution. The command MUST exit non-zero when it
makes no change in a mode where a change was expected.

#### Scenario: Confirmed cleanup removes the gradeless duplicate

- **WHEN** an assignment has two evaluations where one has grades and one has none, and the operator runs the command with the confirm flag
- **THEN** the gradeless duplicate evaluation and its formula rows are removed and the graded evaluation is kept

#### Scenario: Ambiguous duplicate is left for manual review

- **WHEN** an assignment has two evaluations that both have grades and the operator runs the command with the confirm flag
- **THEN** the tool deletes neither and reports the assignment for manual resolution

#### Scenario: No-op confirmed run exits non-zero

- **WHEN** the operator runs the command with the confirm flag against a tenant that has nothing to clean up
- **THEN** the command makes no change and exits with a non-zero status
