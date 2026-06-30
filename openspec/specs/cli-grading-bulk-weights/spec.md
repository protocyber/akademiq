## ADDED Requirements

### Requirement: The akademiq CLI SHALL provide a command to bulk-set single-evaluation formula weights to 100%

The `akademiq grading set-single-eval-weights` command MUST identify all
`(homeroom, term, subject)` scopes in the grading database where exactly one
concrete `evaluation` row exists and whose formula weight is not already 100,
then set that weight to 100 by calling the grading service HTTP endpoint for
each affected scope. The endpoint enforces sum-to-100 validation and triggers
score recompute automatically.

The command MUST default to **dry-run mode**, printing the list of scopes that
would be updated without making any changes. The `--execute` flag MUST be
provided to apply changes. An interactive confirmation prompt MUST be shown
before applying; `--yes` / `-y` bypasses it.

The command MUST accept optional `--tenant <uuid>` and `--term <uuid>` flags to
narrow the target scope. Without these flags the command operates across all
tenants in the connected grading database.

The command MUST exit non-zero and print a clear message if no scopes require
updating (nothing to change).

The command MUST require `--token <jwt>` or `GRADING_AUTH_TOKEN` env var
(a valid `tenant_admin` access JWT for the target tenant). The token MUST NOT
appear in command output or logs.

The command MUST accept `--grading-url <url>` (default `http://127.0.0.1:8086`)
to configure the grading service base URL.

#### Scenario: Dry-run prints affected scopes without changing data

- **WHEN** the operator runs `akademiq grading set-single-eval-weights --token <jwt>` (no `--execute`)
- **THEN** the command prints the list of `(homeroom, subject, report_type)` scopes that would be updated and exits zero, but no `report_formula` rows are changed

#### Scenario: Execute applies the weights and recomputes scores

- **WHEN** the operator runs with `--execute --yes`
- **THEN** for each identified scope the command calls `PUT /report-types/{rt}/homerooms/{h}/formulas/{s}` with `{ weights: { <eval_id>: 100 } }`, prints a success line per scope, and exits zero

#### Scenario: Nothing to change exits non-zero

- **WHEN** all single-evaluation scopes already have weight = 100
- **THEN** the command prints "nothing to change" and exits non-zero

#### Scenario: Scope narrowed by --term

- **WHEN** the operator passes `--term <term_id>`
- **THEN** only scopes whose evaluation belongs to that term are considered

#### Scenario: Token missing causes clear error

- **WHEN** neither `--token` nor `GRADING_AUTH_TOKEN` is set
- **THEN** the command exits non-zero with a clear message before making any HTTP calls

#### Scenario: Already-100 scopes are skipped

- **WHEN** a single-evaluation scope already has `report_formula.weight = 100`
- **THEN** the scope is not included in the dry-run list and the endpoint is not called for it
