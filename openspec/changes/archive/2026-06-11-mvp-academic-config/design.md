# Design — Academic Config Service

## Context

First link in the chain to "create a report card". Owns *year-scoped academic
structure*. Mirrors the proven `iam-service` skeleton so the team adds a
service without inventing new patterns.

## Key decisions

### 1. Service boundary: config vs operations

Academic Config owns **definitions that are stable for a year** (year,
curriculum, subjects, grading rules, class templates). It does **not** own
students, teachers, homerooms, or enrollments — those are operational data and
belong to phase 3's academic-ops service. The seam is the `academic_year.created`
event: ops cannot create a homeroom for a year that config has not created.

```
academic-config-service              academic-ops-service (phase 3)
  academic_year ──── academic_year.created ───▶ homeroom (FK academic_year_id)
  subject       ──── (read via API/event) ────▶ teaching_assignment (subject_id)
  grading_policy ─── (read by grading svc) ───▶ report card pass/fail rules
```

Subjects and grading policy are referenced by later services **by id**. We do
not duplicate them; later services store the foreign id and read the catalog
when they need the human-readable name (or cache it on the event). This keeps
config the single source of truth.

### 2. Academic-year status machine

We implement the lifecycle from
`09_states/AcademiQ_State_Academic_Year_Lifecycle.md`, but only the transitions
phases 2–3 need are *enforced* now:

```
Planning → Configuration → Active → Locked → Finalizing → Closed → Archived
```

For phase 2 the meaningful gate is **Active**: ops (phase 3) only enrolls
students into an `Active` year, and grading (later) only records grades while
the year is `Active`. The later states (`Locked`, `Finalizing`, `Closed`) are
stored and transition-validated but their downstream effects land with the
grading/promotion phases. Transitions are validated server-side; illegal jumps
return 409 `INVALID_STATE_TRANSITION`. A tenant may have at most one `Active`
year at a time — enforced with a partial unique index.

### 3. Subscription gating via event projection

Rather than a synchronous call to Billing on every write, the service consumes
`subscription.activated` and maintains a small local projection
(`tenant_subscription_state`: `tenant_id`, `status`, `valid_until`). Year
creation checks this projection. This keeps config independent of Billing's
uptime and matches the event-first direction in `04_event_standards.md`.
The entitlement middleware (`academic_config` feature) is the second gate and
covers the plan-tier dimension; the projection covers the active/expired
dimension.

### 4. Grading policy is per-year, single row

`grading_policy` is 1:1 with `academic_year` (the ERD shows `o{` but a year
runs one policy in MVP). We model it as upsert (`PUT`) keyed by
`academic_year_id`, returning the current policy. `grading_scale` is a small
enum string (`"0-100"`, `"A-E"`) validated against a fixed allowlist;
`minimum_passing_score` is a float in `[0,100]`. The grading service later
reads this to decide pass/fail when generating a report card.

### 5. Class templates are advisory

`class_template` (grade_level, default_capacity) seeds phase-3 homeroom
creation defaults. It is not wired to any automation in phase 2 — it is plain
CRUD that the ops UI reads when proposing default homerooms. Keeping it dumb
now avoids coupling config to ops.

## Data model (refinery `V1__init.sql`)

| Table | Key columns | Notes |
|-------|-------------|-------|
| `academic_year` | `academic_year_id` PK, `tenant_id`, `name`, `start_date`, `end_date`, `status` | partial unique `(tenant_id) WHERE status='Active'` |
| `curriculum_version` | `curriculum_version_id` PK, `academic_year_id` FK, `name`, `description` | |
| `subject` | `subject_id` PK, `curriculum_version_id` FK, `name`, `passing_grade` | |
| `grading_policy` | `policy_id` PK, `academic_year_id` FK unique, `minimum_passing_score`, `grading_scale` | upsert by year |
| `class_template` | `template_id` PK, `academic_year_id` FK, `grade_level`, `default_capacity` | |
| `tenant_subscription_state` | `tenant_id` PK, `status`, `valid_until` | projection from `subscription.activated` |

Indexes: `academic_year(tenant_id, status)`, `curriculum_version(academic_year_id)`,
`subject(curriculum_version_id)`, `class_template(academic_year_id)`.

## Alternatives considered

- **Fold config into a single "academic" service with ops** — rejected: the
  ERDs, component diagrams, and roadmap all separate them; merging would make
  the report-card chain harder to reason about and test in slices.
- **Synchronous Billing check on each write** — rejected: couples config to
  Billing availability; the event projection is cheap and already idiomatic.
- **Generic key/value grading policy** — rejected: over-engineered; a fixed
  scale enum + min score covers every MVP grading rule the report card needs.

## Risks

- **Event ordering**: if `subscription.activated` is delayed, a freshly
  registered tenant might be briefly unable to create a year. Mitigation:
  the e2e waits for the projection; the UI surfaces a clear "subscription
  activating" state rather than a raw 403.
- **Year/subject referenced cross-service by id**: later services must treat
  config ids as opaque and tolerate renames. Documented in the API contract.
