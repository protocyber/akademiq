## Context

The academic year is currently a flat, single-level construct in
`academic-config-service` (`migrations/V1__init.sql:11-30`, `domain.rs:67-77`).
Every period-sensitive entity attaches directly to `academic_year_id`:

- `evaluation` (`grading-service/migrations/V4__evaluation_and_grade_rework.sql:4-17`)
  keyed by `(tenant, homeroom, subject, academic_year, code)`.
- `report_type` (`grading-service/migrations/V5__report_batch_and_formula.sql:9-19`)
  keyed by `(academic_year, code)`.
- `report_card`, `grade`, `subject_report_score`, `report_subject_score` derive
  scope from those.
- `homeroom`, `enrollment`, `teaching_assignment` (academic-ops) are year-scoped.

There is no period/term/semester entity anywhere (verified by exhaustive search
across `.rs`/`.sql`/`.ts`/`.tsx` and `docs/`). The word "semester" appears only
as example report-type names ("Rapor Tengah Semester") and in two UI mockups.

The existing cross-database integration uses the **projection pattern**: the
academic year is owned by `academic-config-service` (source of truth) and
replicated as read-only projections in consumers — `known_academic_year`
(academic-ops) and `valid_year` (grading) — kept in sync via
`academic_year.created` / `academic_year.status_changed` events through a
transactional outbox. `valid_year` is used to gate grade entry on year
`Active` (added by `simplify-academic-year-status`). There are no foreign keys
across service databases; cross-service references are validated in the
application layer against these projections.

The web layer maintains a global academic scope
(`apps/web/src/components/providers/academic-scope-provider.tsx`) holding
`{yearId, curriculumId}` in `localStorage` (tenant-scoped key), defaulting to
the tenant's `Active` year + newest curriculum version, exposed via React
Context. This was introduced by `global-academic-scope` and removed per-page
year/curriculum pickers.

## Goals / Non-Goals

**Goals:**
- Introduce `academic_term` as a child of `academic_year` with its own 4-state
  lifecycle mirroring the year's.
- Guarantee every academic year always has at least one term (auto-seed on
  creation + migration backfill).
- Re-scope `evaluation` and `report_type` to `(year, term)` so period semantics
  are structural, not encoded in names/codes.
- Extend the global academic scope with a `termId` dimension so the whole
  console works in a single `(year, term, curriculum)` context.
- Keep the change scoped: homeroom/enrollment/teaching remain year-scoped;
  annual report aggregation is deferred.

**Non-Goals:**
- Re-scoping homeroom/enrollment/teaching_assignment to term.
- Year-scoped (annual, cross-term) report types.
- Per-tenant configurable default term name.
- Attendance module guards (module not built yet).
- Auto-activation of terms when a year goes `Active`.
- Full `tenant-audit-log` integration (term transitions use a local interim
  store, same as the year one).

## Decisions

### Decision 1: Entity name `academic_term`

The entity is `academic_term` (column `term_id`, FK `academic_term_id`, API path
`/academic-terms`, API nest `/academic-years/{id}/terms`, event producer
`academic_term`, event types `academic_term.*`).

**Rationale:** "term" is the standard SIS industry label (PowerSchool, Infinite
Campus), is neutral enough to hold "Semester 1", "Caturwulan 2", or "Triwulan
3", and avoids collision with the existing `TimetableEntry.period_number`
(meaning a timetable slot, unrelated to academic periods). "period" was rejected
for that collision risk; "segment" was rejected as non-conventional.

The *displayed* name ("Semester 1" etc.) lives in the `name` column and is a
label, not an invariant.

### Decision 2: `academic_term` schema and invariants

```
academic_term
  term_id           UUID PK
  academic_year_id  UUID NOT NULL  FK→academic_year ON DELETE CASCADE
  tenant_id         UUID NOT NULL
  name              VARCHAR(160) NOT NULL
  start_date        DATE NOT NULL
  end_date          DATE NOT NULL
  status            VARCHAR(32) NOT NULL DEFAULT 'Draft'
  created_at, updated_at TIMESTAMPTZ
  CHECK (start_date <= end_date)
  CHECK (status IN ('Draft','Active','Closed','Archived'))
  UNIQUE (tenant_id, academic_year_id, name)
```

Partial unique index (mirrors the year's one-`Active` rule):

```
CREATE UNIQUE INDEX academic_term_one_active_per_year_idx
  ON academic_term (academic_year_id) WHERE status = 'Active';
```

Term dates must fall within the parent year's dates and terms within a year must
not overlap. **Both are validated in the application layer** (see Decision 5)
because cross-table range checks cannot be expressed as plain `CHECK`
constraints and the codebase uses no triggers.

### Decision 3: Auto-seed default term on year creation

`create_academic_year` (`commands.rs:32`) is extended to insert, in the **same
transaction** that creates the year, a single child term with:
`name = DEFAULT_TERM_NAME` (`"Semester 1"`, a `const` in `domain.rs`),
`start_date`/`end_date` copied from the year, `status = Draft`. An
`academic_term.created` event is enqueued in the same outbox transaction.

**Rationale:** "Wajib ≥1 term per year" with a default removes a setup step for
the common case (most Indonesian schools use semesters) while keeping the name
editable and allowing additional terms. Using `"Semester 1"` (not the earlier
"Tahun Penuh" idea) matches the dominant convention; tenants not using
semesters simply rename it.

**Non-goal:** per-tenant configurable default name — a backend constant keeps
the MVP simple; it can be promoted to a tenant setting later without schema
change.

### Decision 4: Independent term lifecycle, bounded by parent

The term state machine mirrors the year's
(`Draft ⇄ Active ⇄ Closed → Archived`, with undo except out of `Archived`),
implemented by a `TermStatus` type reusing the same 4 variants and transition
matrix.

Parent-child coordination:

| Year transition | Term requirement |
|---|---|
| `→ Active` | **none** (year may be `Active` with all terms `Draft`) |
| `→ Closed` | rejected (`TERM_STILL_ACTIVE`) if any term is `Active` |
| `→ Archived` | all terms must be `Archived` (implied: they were `Closed` first) |
| `→ Draft` (undo) | allowed; terms are unaffected |

Term transitions are otherwise independent: a term can move `Draft → Active`,
`Active → Closed`, etc., on its own. Because year `→ Active` has no term
invariant, the operator sequence is: prepare year+terms (`Draft`), activate the
year, then activate a term when the period actually begins. The web layer
surfaces a warning when an `Active` year has no `Active` term.

**Rationale (no year→Active invariant):** operators should be able to commit to
a year (mark it `Active`) before any period has formally started. Evaluation
setup is allowed in `Draft`/`Active` terms (Decision 6), and grade entry is
additionally gated on term `Active`, so an `Active` year with only `Draft`
terms is a safe "preparing" state that simply blocks grade entry until a term
is activated.

**Rationale (year→Closed blocks on active terms):** closing a year while a
child term is still `Active` would leave an inconsistent projection state
(`valid_term.status = Active` under a `Closed` year). Forcing the operator to
close terms first makes the aggregation explicit and predictable.

### Decision 5: Range/overlap validation in the application layer (no triggers)

- `start_date >= year.start_date` and `end_date <= year.end_date`: checked in
  `create_academic_term` / `update_academic_term` after fetching the parent year
  (reusing the existing `ensure_year_exists` pattern).
- No overlap between terms in the same year: checked in the command layer by
  querying existing terms for the year; a partial unique index or `EXCLUDE`
  constraint is **not** added to avoid requiring the `btree_gist` extension and
  to keep error messages consistent with the codebase's `VALIDATION_ERROR`
  shape.

This mirrors how the codebase validates the one-`Active`-year invariant: a
partial unique index (DB safety net) **plus** `active_exists_except` (app-layer
check with a friendly error). The hybrid is applied to terms as well for the
one-`Active`-term rule, while date-range/overlap checks are app-only.

### Decision 6: Evaluation & report_type re-scoping; gates

`evaluation` and `report_type` gain `term_id UUID NOT NULL`. New uniqueness:

- `evaluation`: `(tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)`
- `report_type`: `(academic_year_id, term_id, code)`

`report_type` is **strictly term-scoped** (Model A): a report type belongs to
exactly one term, and `report_formula` may only reference evaluations from the
same term (validated in `add_report_formula`, error `EVALUATION_TERM_MISMATCH`).
Annual cross-term report aggregation is explicitly a non-goal.

Gates (grading-service, app-layer against the `valid_term` projection):

| Operation | Term status required | Error (HTTP) |
|---|---|---|
| Create/edit `evaluation` | `Draft` or `Active` | `TERM_NOT_EDITABLE` (409) |
| Record `grade` | `Active` | `TERM_NOT_ACTIVE` (409) |
| Add `report_formula` row | parent term `Draft`/`Active` + `EVALUATION_TERM_MISMATCH` if cross-term | 409 |

Grade entry keeps the existing year-`Active` gate and adds the term-`Active`
gate on top.

**Rationale (code uniqueness includes `term_id`):** a teacher naturally creates
"UH1" in Semester 1 and "UH1" again in Semester 2 — they are distinct
evaluations. Including `term_id` in the unique key allows that without forcing
contrived codes (`S1-UH1`). `report_formula` keys on `evaluation_id` (UUID), so
the M:N weighting is unaffected.

### Decision 7: Events and projections

New events (transactional outbox, same shape as the year events):

- `academic_term.created` — payload `{tenant_id, term_id, academic_year_id, name, start_date, end_date, status}`.
- `academic_term.status_changed` — payload `{tenant_id, term_id, academic_year_id, previous_status, status, reason}`.

Consumers:
- `grading-service`: new `valid_term` projection (mirrors `valid_year`),
  upserted on both events; used for the evaluation/grade/formula gates.
- `academic-ops-service`: optional light `known_academic_term` projection (for
  future UI); homeroom/enrollment/teaching are unchanged and remain year-scoped.

Cross-database references (`evaluation.term_id`, `report_type.term_id`) have no
physical FK and are validated against `valid_term` in the application layer —
exactly the established pattern for `valid_year`.

### Decision 8: Global academic scope gains `termId`

`academic-scope-provider.tsx` gains a `termId` alongside `yearId`/`curriculumId`,
persisted in the same tenant-scoped `localStorage` key, exposed via Context.
A `useTerms(yearId)` query populates a new term `<Select>` in the header beside
the year picker.

Default resolution (when the year is selected/restored): the term with
`status = Active`; if none, the term whose `[start_date, end_date]` contains
today; if none, the first term. If the year has no `Active` term, the UI shows a
warning ("Tidak ada semester aktif — aktivkan semester untuk mulai input nilai").

Changing the year resets the term to the new year's default. The term dimension
is consumed by grade entry, the report board, and the evaluation/report-type
management screens.

### Decision 9: Term status audit (interim local store)

Term transitions write to a local `academic_term_status_transition` table with
the same shape as `academic_year_status_transition` (`id, term_id, tenant_id,
from_status, to_status, reason, actor_user_id, occurred_at`). When
`tenant-audit-log` lands, the write target moves to the audit log without
changing the transition command contract — identical to the year's stated plan.

### Decision 10: Term/report-type management UI restructure

The interim UI bundles everything into one `YearFormModal` with **fake tabs**
(`setActiveTab` + styled `<Button>`s) holding five sections: Info, Kebijakan
Nilai, Versi Kurikulum, Semester, Jenis Rapor (`years/page.tsx`). This is
restructured so management surfaces match where each entity actually lives:

- **Form edit tahun ajaran** → real shadcn `Tabs` (state-driven), three tabs:
  `Info`, `Kebijakan Nilai`, `Versi Kurikulum`, plus an explicit **Simpan**
  button (currently missing). The `Semester` and `Jenis Rapor` sections leave
  this modal.
- **New page `/academic/terms`** holds term management (the `Semester` list,
  create/edit/delete/transition). It joins the `academic-settings.tsx` shell as
  a sibling tab alongside Tahun Ajaran / Mata Pelajaran / Template Kelas.
- **Form edit semester** → real shadcn `Tabs`, two tabs: `Info`, `Jenis Rapor`.
  `ReportTypesSection` (already `term_id`-scoped in data —
  `disabled={!canManage || !termId}`) moves here from the year modal. This is a
  UI relocation only; the data contract is unchanged.

This also resolves the "Belum ada jenis rapor untuk tahun ini. Tambahkan dari
Pengaturan → Tahun Ajaran." copy, which is doubly wrong: report types are
term-scoped (not year-scoped), and they will be managed from the semester form,
not the year form.

**Scope note / spec tension:** `web-academic-config-management` describes term
management as "a section/sub-page of the **year** management area." A standalone
`/academic/terms` page within the academic-config shell satisfies the intent
("year management area" = the Pengaturan → Akademik group, not the year modal),
but the spec wording should be reconciled when this lands.

**Tab-component strategy (applies across the app, not just terms):** there are
three distinct "tab-like" patterns and they do not all map to a vanilla
state-driven `<Tabs>`:

| Pattern | Where | Maps to |
|---|---|---|
| Route-driven nav (1 tab = 1 page + URL) | `academic-settings.tsx`, `academic-ops-page.tsx` | `Tabs value={pathname}` with `TabsTrigger asChild` wrapping `<Link>`, **no `TabsContent`** (content is the routed page) |
| Modal form sections (local, no URL) | year edit, semester edit | canonical `Tabs value/onValueChange` |
| In-place state filter (local, no URL) | report-card status approval (`classroom/[classroomId]/page.tsx`) | canonical `Tabs`, count badge in each `TabsTrigger` |

The route-driven pattern must keep per-view URLs (deep-link, back button,
refresh), so it uses `TabsList`/`TabsTrigger` for appearance and active-state
only. *A11y caveat:* `asChild` makes the `<Link>` inherit `role="tab"`, which is
semantically weaker than `nav` + `aria-current="page"` for navigation; accepted
tradeoff to match the shadcn look. The route-driven and status-filter surfaces
reach beyond the term feature; they may land as a separate UI change rather than
inside `add-academic-term`.

## Risks / Trade-offs

- **[Risk] Report annual aggregation not supported** → Model A makes
  `report_type` strictly term-scoped; schools wanting an end-of-year report that
  combines Semester 1 + 2 cannot do it in this change. *Mitigation:* explicitly
  out of scope; a follow-up change can add a nullable `term_id` or a
  `scope_type` column on `report_type` without disturbing the MVP.
- **[Risk] Migration backfill assigns existing evaluations to the default term
  even if they were conceptually cross-period** → existing data has no period
  metadata, so all rows are assigned to the seeded default term. *Mitigation:*
  acceptable for the dev-stage dataset (the `V4`/`V5` migrations already reset
  grading data); operators can reassign via the UI afterward.
- **[Risk] Overlap/range validation has a TOCTOU window** → app-layer checks are
  not atomic across concurrent requests. *Mitigation:* the one-`Active`-term
  invariant is backed by a partial unique index (DB-enforced); for overlap, the
  window is narrow and the system is single-operator-per-tenant in practice;
  a DB `EXCLUDE` constraint can be added later if needed.
- **[Risk] Year `→ Active` with no active term confuses operators** → grade
  entry silently fails until a term is activated. *Mitigation:* the web warning
  banner makes the state explicit; the grade-entry page surfaces
  `TERM_NOT_ACTIVE` as a readable message.
- **[Trade-off] `report_type` uniqueness loses the year-only code uniqueness** →
  a code like "UTS" can now repeat across terms in the same year. This is
  intentional (codes are per-term labels) and enforced by the new
  `(year, term, code)` key.
- **[Coordination risk] `tenant-audit-log` lands with a different audit shape**
  → *Mitigation:* the interim store is isolated behind the command; only the
  write target changes when the audit log is ready.
- **[Bug, observed] `term_id` divergence between academic-config and grading**
  → The two backfills chose `term_id` independently: academic-config
  `V4__academic_term.sql` seeds the default term with `gen_random_uuid()` (the
  source of truth), while grading `V7__term_rework.sql` /
  `V8__valid_term_projection.sql` derive it as `md5(academic_year_id)::uuid`.
  For any year created **before** this feature (the backfill path), the two IDs
  never match. Verified in dev tenant `146b77b9…`: academic-config term
  `091a02f2…` (Active) vs grading `valid_term`/`evaluation`/`report_type` all
  carrying the ghost `9aa7758f…` (= `md5(year)`). Symptoms:
  - the web sends the **real** academic-config `term_id`; grading's `valid_term`
    lookup returns `None` → `TERM_NOT_EDITABLE` on a genuinely Active term;
  - report types exist but are stamped with the ghost `term_id`, so a query by
    the real term returns zero → the "Belum ada jenis rapor untuk tahun ini"
    message appears even though report types exist;
  - historical evaluations/grades point at a phantom term and become invisible
    once queried by the real `term_id`.
  Grading is internally consistent (everything is `md5(year)`), so the bug only
  surfaces once a real `term_id` crosses the service boundary. Terms created
  **via the API** are unaffected because `academic_term.created` carries the
  real ID. *Root cause:* grading **fabricates** a `term_id` instead of treating
  it as data owned by academic-config and delivered via the event/projection.
  *Mitigation:* see "Term ID reconciliation" in the Migration Plan.

## Migration Plan

1. **academic-config-service first:**
   - `V4__academic_term.sql`: create `academic_term`, partial unique index,
     `academic_term_status_transition`; seed one `"Semester 1"` term per
     existing year (idempotent, status copied from the year).
   - Ship domain/repo/command/http + `create_academic_year` seed extension and
     the year `→ Closed` guard.
2. **grading-service:**
   - `V7__term_rework.sql`: add `term_id` (nullable) to `evaluation`/
     `report_type`; backfill from the year's default term; set `NOT NULL`;
     drop old unique constraints; add term-scoped uniqueness. Dev-reset
     acceptable.
   - `V8__valid_term_projection.sql`: `valid_term` projection.
   - Ship event consumer + evaluation/grade/formula gates.
3. **academic-ops-service (optional):** `V5__known_term` projection + consumer.
4. **Web:** scope provider + header selector + term management UI + warnings.
5. **Docs:** ERDs, state machine, API, events, component diagram.
6. **Rollback:** the term table and columns are additive; rolling back means
   redeploying the prior backend version and (optionally) dropping the new
   table/columns. Backfilled `term_id` values are valid and harmless to the old
   code, which ignores them.

### Term ID reconciliation (existing data heal)

The original plan let academic-config (`gen_random_uuid()`) and grading
(`md5(year)`) pick `term_id` independently, which diverges for backfilled years
(see the "term_id divergence" risk). The fix has two parts:

1. **Forward fix (permanent):** grading MUST stop fabricating `term_id`.
   - Remove every `md5(academic_year_id)::uuid` derivation from grading
     (`V7`/`V8` backfill and the `commands.rs`/`queries.rs` fallback
     `SELECT … FROM valid_term … LIMIT 1` → `unwrap_or_else(Uuid::new_v4)`).
   - A `term_id` enters grading **only** through the `academic_term.created` /
     `academic_term.status_changed` projection. The fallback when the client
     omits `term_id` MUST resolve a real projected term (deterministic
     selection, see open question) rather than invent one.
2. **One-time heal (existing rows):** a coordinated, ordered operation — **not**
   a startup migration (refinery runs before the RabbitMQ replay finishes, so a
   migration-time remap would silently no-op):
   - **A.** academic-config republishes `academic_term.created` for all existing
     terms (re-enqueue to the outbox; one-shot CLI/startup task).
   - **B.** grading consumes them → `valid_term` gains rows with the **real**
     `term_id` (the upsert is `ON CONFLICT (term_id)`, so the ghost
     `md5(year)` rows are left untouched alongside the new real rows).
   - **C.** a grading reconcile step (CLI `akademiq`, run **after** replay)
     remaps using the real `valid_term` as the `year → real term_id` map:
     `UPDATE evaluation/report_type SET term_id = real WHERE term_id = md5(year)`
     and `DELETE FROM valid_term WHERE term_id = md5(year)` to drop the ghosts.
     Must be idempotent and exit non-zero when nothing changed.

   This respects the projection-based boundary (grading never queries
   `academic_config_db`; the real ID arrives via event) and avoids the
   refinery-vs-RabbitMQ race.

## Open Questions

- **Reconcile tie-break for multi-term years.** Step C maps `year → real
  term_id` from `valid_term`, which is unambiguous only when a year has exactly
  one term (the seeded default). Once a year has multiple terms, mapping a
  legacy `md5(year)` row to a single real term needs an explicit rule (e.g.
  "the default term named `Semester 1`" or "the oldest term"). Current data is
  1-term-per-year so it is safe today; pick a rule before any year gains a
  second term. Same rule applies to the omitted-`term_id` fallback in grading.

- Should `academic-ops-service` get a `known_academic_term` projection now, or
  defer until a UI actually needs it? Current lean: add the table + consumer
  (cheap, consistent) but no UI.
- ~~Should the term management live as a sub-page of the year edit form, or as a
  sibling page?~~ **Resolved (Decision 10):** standalone `/academic/terms` page
  in the academic-config shell; report types move to the semester edit form.
  Reconcile the `web-academic-config-management` spec wording ("sub-page of the
  year area") with this when the change lands.
- Promote `DEFAULT_TERM_NAME` to a per-tenant setting in a later change? Defer.
