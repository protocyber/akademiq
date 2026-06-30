## Context

The `akademiq-cli` binary (`apps/backend/tools/akademiq-cli/src/main.rs`) is a
single-file ~1540-line Rust binary. It has four top-level subcommands: `iam`,
`grading`, `academic-config`, `academic-ops`. All existing commands use **direct
SQLx** against the relevant service database — there is no HTTP client in the
CLI today.

The grading service formula endpoint
`PUT /report-types/{rt}/homerooms/{homeroom}/formulas/{subject}` (post
`fix-report-formula-homeroom-scope`) sets weights AND recomputes live/frozen
scores in one atomic operation. Duplicating that recompute logic in the CLI via
direct SQL would violate `AGENTS.md` ("prefer existing service HTTP APIs for
workflows with domain rules, side effects, or events"). The weight change
triggers a domain side-effect (score recompute) that touches multiple tables
(`subject_report_score`, `report_subject_score`, `report_card.summary`).
Therefore this command uses HTTP, not direct SQL, for the write path.

The read/discovery path (finding single-eval scopes) uses **direct SQLx
read-only queries** against `GRADING_DATABASE_URL` — consistent with existing
CLI style and requires no auth.

## Goals / Non-Goals

**Goals:**
- Identify `(homeroom, term, subject)` scopes with exactly one concrete
  `evaluation` row.
- For each scope, call the grading service HTTP endpoint to set weight = 100
  and trigger recompute.
- Dry-run by default; `--execute` + confirmation to apply.
- Optional scope narrowing via `--tenant` and `--term`.

**Non-Goals:**
- No template-side fix (`report_formula_template`) — the command only touches
  materialized concrete formulas.
- No recompute logic duplicated in the CLI — the endpoint handles it.
- No support for scopes with more than one evaluation.
- No backfill of missing `report_formula` rows (only updates existing rows or
  inserts where none exists for the scope — the endpoint handles both via its
  DELETE-then-INSERT pattern).

## Decisions

### Decision 1: HTTP for writes, direct SQL for reads

**Choice:** Discovery query runs via SQLx (read-only); each weight-set call goes
via `reqwest` to `PUT /homerooms/{h}/formulas/{s}`.

**Rationale:** The recompute side-effect lives entirely inside the grading
service. Duplicating it in SQL would mean tracking `subject_report_score`,
`report_subject_score`, `report_card.summary`, KKM logic, and valid-subject
filtering — ~120 lines of domain logic that could diverge. The HTTP path is the
canonical one. AGENTS.md explicitly covers this case.

**Trade-off:** The CLI gains a new dependency (`reqwest`) and needs auth token
plumbing. This is a new pattern for the binary but a small, self-contained
addition.

### Decision 2: Auth via Bearer token flag / env var

**Choice:** `--token <jwt>` CLI flag, with fallback to `GRADING_AUTH_TOKEN` env
var. The token must be a valid access JWT for a `tenant_admin` user in the
target tenant (or a user with `grade.evaluation.manage` + assigned to all target
scopes — in practice an admin token is simplest).

**Rationale:** The formula endpoint requires `grade.evaluation.manage` +
assignment-scope check (post `fix-report-formula-homeroom-scope`). A
`tenant_admin` JWT satisfies both. The CLI operator obtains a token via normal
login (browser or API). A `--grading-url` flag (default `http://127.0.0.1:8086`)
controls the base URL.

The CLI never prints or logs the token. Per AGENTS.md: "CLI output must not
print secrets".

### Decision 3: Scope definition — exactly one evaluation per (homeroom, term, subject)

**Choice:** The discovery SQL finds `(homeroom_id, term_id, subject_id)` tuples
where `COUNT(evaluation_id) = 1` in the `evaluation` table, then joins to
`report_type` via `term_id` to produce `(report_type_id, homeroom_id,
subject_id, evaluation_id)` tuples for the HTTP calls.

```sql
SELECT e.homeroom_id, e.subject_id, e.evaluation_id,
       rt.report_type_id, rt.tenant_id
FROM evaluation e
JOIN report_type rt
  ON rt.tenant_id = e.tenant_id
 AND rt.term_id   = e.term_id
WHERE e.tenant_id = $tenant   -- optional
  AND e.term_id   = $term     -- optional
  AND (
    SELECT COUNT(*) FROM evaluation e2
    WHERE e2.tenant_id    = e.tenant_id
      AND e2.homeroom_id  = e.homeroom_id
      AND e2.subject_id   = e.subject_id
      AND e2.term_id      = e.term_id
  ) = 1
```

Only scopes where the single evaluation's `report_formula.weight` is not already
100 are reported (dry-run shows these; execute only calls the endpoint for
these).

### Decision 4: Existing CLI conventions (dry-run, confirm, exit non-zero)

The command follows `CleanupEvaluations` (`main.rs:602-883`) exactly:
- Dry-run by default; `--execute` to apply.
- `confirm()` helper + `--yes` to skip.
- Print count of scopes found / fixed.
- Exit non-zero via `anyhow::bail!` if nothing to change.

## Risks / Trade-offs

- **[Grading service must be running]** — Unlike pure-SQL commands, this one
  requires the grading service to be up. The command fails clearly with a
  connection error if not. → Document in help text.
- **[Token expiry]** — Access tokens are short-lived (15 min default). For large
  tenants with many scopes the command may run longer. → Operator should use a
  freshly-obtained token; future work could add token refresh.
- **[Partial failure]** — If the HTTP loop fails mid-way (service restart, token
  expiry), some scopes are fixed and some are not. The command is idempotent:
  re-running with `--execute` will only attempt remaining unfixed scopes.
