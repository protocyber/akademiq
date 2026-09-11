## Context

`add-academic-term` introduced `academic_term` in academic-config and re-scoped
grading's `evaluation`/`report_type` to `(year, term)`. The two services
backfilled the default term's `term_id` independently:

- academic-config `V4__academic_term.sql` seeds the default term with
  `gen_random_uuid()` — this is the source of truth.
- grading `V7__term_rework.sql` and `V8__valid_term_projection.sql` derive it as
  `md5(academic_year_id)::uuid`.

For any year created before the feature (the backfill path) the IDs never match.
Verified in dev tenant `146b77b9…`, year `b13ec157…` (Active):

```
academic_config.academic_term.term_id = 091a02f2…   (Active, real)
grading.valid_term.term_id            = 9aa7758f…   (= md5(year), ghost)
grading.evaluation  (×2)              = 9aa7758f…
grading.report_type (×4)              = 9aa7758f…
```

Grading is internally consistent (everything is `md5(year)`), so the bug only
surfaces once a real `term_id` crosses the service boundary from academic-config
via the web. Terms created through the API are unaffected because
`academic_term.created` carries the real ID; this fix targets backfilled data.

Constraints: grading MUST NOT query `academic_config_db` (projection-based
service boundary per `apps/backend/CONVENTIONS.md`); the real `term_id` can only
reach grading through events. Refinery migrations run at startup, before the
RabbitMQ replay completes.

## Goals / Non-Goals

**Goals:**
- Make a genuinely Active term editable: real `term_id` from the web resolves in
  grading's `valid_term`.
- Heal existing `evaluation`/`report_type`/`valid_term` rows that point at the
  ghost `md5(year)` id so they reference the real `term_id`.
- Remove the root cause: grading never fabricates a `term_id`.
- Idempotent, re-runnable heal that reports what it changed.

**Non-Goals:**
- Any web/UI change (covered by `restructure-term-report-ui`).
- Multi-term-per-year semantics beyond the single seeded default (the heal maps
  one default term per year; see Open Questions).
- Changing the term lifecycle, events payloads, or API contracts.

## Decisions

### Decision 1: Align grading to academic-config's real ID, not the reverse
academic-config (`academic_term`) is the source of truth and `V4` is already
applied, so its random IDs cannot be edited by re-running a migration. Forcing
academic-config to `md5(year)` (the cheaper "make both deterministic" option)
would also corrupt any term already created via the API with a random ID that is
already correct in grading. Therefore the heal moves grading's data to match
academic-config's real IDs. *Alternative rejected:* deterministic `md5` on both
sides — fragile once API-created terms exist (a mixed environment breaks).

### Decision 2: Bridge the real ID via event replay, not cross-DB query
academic-config republishes `academic_term.created` for all existing terms to
the transactional outbox; grading's existing consumer upserts `valid_term`
(`ON CONFLICT (term_id)`), so real-ID rows appear alongside the ghosts without
touching them. This respects the projection boundary. *Alternative rejected:*
grading reading `academic_config_db` directly — violates service isolation.

### Decision 3: Reconcile as a CLI operation, not a startup migration
The remap must run after the replay lands, which a refinery migration cannot
guarantee (it runs at startup, before RabbitMQ delivery). An `akademiq` CLI
reconcile command runs the remap on demand. Using the corrected `valid_term` as
the `year → real term_id` map:

```
UPDATE evaluation  SET term_id = real WHERE term_id = md5(year);
UPDATE report_type SET term_id = real WHERE term_id = md5(year);
DELETE FROM valid_term WHERE term_id = md5(year);   -- drop ghosts
```

Idempotent; exits non-zero when nothing changed (per CLI guardrails). *Alternative
rejected:* migration-time remap — silent no-op if `valid_term` lacks the real
rows yet.

### Decision 4: Forward-fix the fabrication
Remove `md5(academic_year_id)::uuid` and `unwrap_or_else(Uuid::new_v4)` from the
grading command/query fallbacks (`commands.rs`, `queries.rs`). When the client
omits `term_id`, resolve a real projected term deterministically (e.g. the one
default term for the year). A `term_id` enters grading only through the
`academic_term.*` projection. This prevents the divergence from recurring on new
backfills or future years.

## Risks / Trade-offs

- **[Risk] Reconcile runs before replay completes** → ghost rows remain mapped to
  nothing. *Mitigation:* CLI ordering is explicit (republish → wait → reconcile);
  reconcile is idempotent and reports zero-change so it can be re-run after the
  projection catches up.
- **[Risk] Multi-term-per-year ambiguity** → the `year → real term_id` map is
  unambiguous only with one term per year. *Mitigation:* current data is
  1-term-per-year; pick a tie-break rule (default-name or oldest) before any year
  gains a second term (see Open Questions). Same rule applies to the
  omitted-`term_id` fallback.
- **[Risk] Republish floods consumers / duplicates** → the grading consumer is
  idempotent (`ON CONFLICT (term_id)`), and there is no `event_id` dedup, so
  replay is safe but re-creates real rows on every run. *Mitigation:* republish
  is a one-shot operation, not on the hot path.
- **[Trade-off] Heal is operational, not automatic** → operators must run two
  steps per environment. Accepted: dev-stage data, single-operator-per-tenant.

## Migration Plan

1. **Forward fix (grading):** remove `md5(year)` fabrication from
   `commands.rs`/`queries.rs`; resolve omitted `term_id` from a real projected
   term. Ship before the heal so new writes are correct.
2. **academic-config:** add a republish operation that enqueues
   `academic_term.created` for every existing term to the outbox.
3. **Heal, per environment (ordered):**
   - run the republish; wait for grading's `valid_term` to gain real-ID rows;
   - run `akademiq` grading reconcile to remap `evaluation`/`report_type` and
     delete ghost `valid_term` rows.
4. **Verify:** the reported curl (real `term_id`) returns 201; the report board
   shows existing report types; `valid_term` has no `md5(year)` rows left.
5. **Rollback:** the reconcile is a data remap; keep a record of
   `(old_md5_id → real_id)` per row in case a reverse map is needed. The
   forward-fix code change is independently revertable.

## Open Questions

- Tie-break rule for mapping a legacy `md5(year)` row when a year has multiple
  terms: default term named "Semester 1", or oldest term? Decide before any year
  gains a second term. Current lean: the seeded default ("Semester 1").
- Should the republish + reconcile be a single composite `akademiq` command
  (e.g. `akademiq grading heal-terms`) that waits for projection catch-up, or two
  explicit commands? Lean: two commands for operator control, documented as an
  ordered pair.
