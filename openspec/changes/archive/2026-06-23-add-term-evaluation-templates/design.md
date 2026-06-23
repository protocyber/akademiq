## Context

Evaluations live in `grading-service`. Since migration `V7`, the `evaluation` table is scoped by `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` with a unique constraint on that tuple. Weights live in `report_formula(report_type_id, evaluation_id, weight)`, validated to sum to 100 per `(report_type, subject)`. Report types are term-scoped (`report_type.term_id`).

Teaching assignments live in `academic-ops-service` at the **academic-year** level `(teacher, subject, homeroom, academic_year_id)`. When created, academic-ops emits `teacher.assigned` (IDs only). `grading-service` consumes it into the `teaching_authz` projection, which is the authorization gate for evaluation/grade writes.

Today there is no master evaluation list. Teachers recreate evaluations and weights per class/subject on `/grading/entry` via the "Kelola Evaluasi" dialog. This change adds a per-term master (template) and materializes concrete rows from it.

Cross-service note (AGENTS.md): services communicate via projections, never trust client `tenant_id`, and use `refinery` migrations. The grading service already holds both `teaching_authz` (assignments) and `evaluation` (concrete), so "which assignments lack evaluations" is answerable locally without calling academic-ops.

## Goals / Non-Goals

**Goals:**
- A per-term master evaluation list + weight template, managed on the term edit form.
- Concrete evaluations + weights auto-created for new teaching assignments, and backfillable on demand for pre-existing ones.
- Idempotent materialization that survives RabbitMQ event redelivery and repeated backfill clicks.
- Template acts as a seed; teacher overrides remain fully editable.

**Non-Goals:**
- No hard-block on teaching-assignment creation when report types/templates are missing (rejected in design discussion; replaced by self-healing + nudge).
- No synchronous cross-service calls and no new projection in academic-ops.
- No change to the `teacher.assigned` event payload (stays IDs-only).
- No locking of teacher overrides to the template.
- No automatic rebalancing of weights after teacher overrides (warn only).

## Decisions

### D1: Separate template tables, not nullable-scope rows
Add `evaluation_template` and `report_formula_template` as their own tables rather than reusing `evaluation`/`report_formula` with NULL `homeroom_id`/`subject_id`.
- `evaluation_template(template_id PK, tenant_id, term_id, code, name, position)`, `UNIQUE(tenant_id, term_id, code)`.
- `report_formula_template(report_type_id, evaluation_template_id, weight)`, `UNIQUE(report_type_id, evaluation_template_id)`.
- `tenant_id` is stored explicitly (resolved from `valid_term` on insert) per repo convention, even though `term_id` already implies a tenant.
- Rationale: avoids nullable FKs, keeps the concrete `evaluation` unique-constraint and authz logic untouched, and mirrors the existing `report_formula` shape so weight validation reuses the same 100%-per-`(report_type, subject)` rule. Alternative (nullable-scope rows) rejected: pollutes authz checks and the unique index.

### D2: Tab order `Info | Status | Rapor | Evaluasi` (Evaluasi last)
The weight matrix columns are report types, which are created in the Rapor tab. Placing Evaluasi after Rapor resolves the chicken-and-egg: report types exist before weights are edited.
- Alternative (Evaluasi before Rapor, original request) rejected: weight matrix would render with no columns until the user visits Rapor and returns.

### D3: Self-healing materialization, no hard-block
Three idempotent layers, all computed locally in grading:
1. **Auto** — on `teacher.assigned`, materialize concrete evaluations + weights from the term template.
2. **Backfill** — "Terapkan ..." endpoint scans `teaching_authz ⟕ evaluation` for assignments with zero evaluations in the term and fills them.
3. **Nudge** — an endpoint returns the count of assignments lacking evaluations; UI shows a banner.
- Rationale: academic-ops would otherwise need to read grading state (violating projection-based comms). Grading already owns both sides. A missing template/report type becomes a recoverable "not yet materialized" state, never a broken/blocked state.
- Alternatives rejected: (a) hard-block assignment creation in academic-ops (cross-service coupling, year-vs-term scope mismatch); (b) new `report_type_exists` projection in academic-ops (event + consumer + eventual-consistency lag for a block we don't need).

### D4: Materialization scope and idempotency
- Materialize only for terms with status `Draft` or `Active` that have a template.
- A teaching assignment is year-scoped; materialization fans out to each qualifying term within that year that has a template.
- Concrete evaluation insert uses the existing unique tuple `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)` with `ON CONFLICT DO NOTHING` → safe under event redelivery and repeated backfill.
- Concrete `report_formula` materialization requires the matching `report_type` to already exist for the term; if absent, only the evaluation list is created and weights follow when the user next applies (after creating report types). Weight rows also use `ON CONFLICT DO NOTHING`.

### D5: Weight invariant is warn-only after override
The 100%-per-`(report_type, subject)` rule is enforced on template/weight save. After a teacher adds a concrete evaluation outside the template, the subject total may drift from 100%. The UI surfaces a clear warning rather than blocking grade entry or materialization.

### D6: Reuse the "Kelola Evaluasi" UI on the term form
The Evaluasi tab reuses the evaluation-list editor and `WeightMatrix` components currently on `/grading/entry`, parameterized by `term_id` (template mode) instead of `(homeroom, subject)` (concrete mode). New TanStack Query hooks target the template endpoints.

## Risks / Trade-offs

- **Year-scoped assignment vs term-scoped template** → Materialize per qualifying term in the year (D4); only Draft/Active terms, so future terms are not prematurely populated unless their template is ready and the term is active/draft.
- **Report types created after assignments** → Evaluation list materializes immediately; weights materialize on the next apply once report types exist. Nudge banner keeps admins aware.
- **Event redelivery / double-click backfill** → `ON CONFLICT DO NOTHING` on both concrete tables guarantees idempotency.
- **Weight drift after teacher override** → Warn-only (D5); admins/teachers rebalance manually. Documented in user-facing docs.
- **Existing UI tests assert `Info | Rapor` tab structure** → Update `__tests__/academic-config-restructure.test.tsx` and `playwright/academic-config.spec.ts`.
- **`Evaluation` TS type lacks `term_id`** → Extend the type; the create/list payloads already pass `term_id`.
- **Backfill on a large tenant** → Single-statement set-based inserts (INSERT ... SELECT) scoped by term to bound the work; return created/skipped counts.

## Migration Plan

1. Add grading migration creating `evaluation_template` and `report_formula_template` (refinery, next `V` number).
2. Ship template CRUD + weight CRUD + backfill + count endpoints behind existing `grading` module gating.
3. Extend the `teacher.assigned` consumer to materialize (idempotent; safe to deploy before any template exists — no-op).
4. Ship the web Evaluasi tab + nudge banner + tab-order change + test updates.
5. No data backfill required at deploy; templates are opt-in per term. Rollback: drop the two tables and revert the consumer extension; concrete evaluations created by materialization remain valid and editable.

## Open Questions

- None blocking. Future: optionally add a `report_type.created` event so weight materialization can auto-trigger when report types are created after assignments (currently handled by the apply action + nudge).
