# Handoff: add-academic-term vs. in-flight changes

This note answers: **what do I do with `rbac-read-and-menu-restructure` and
`tenant-audit-log` while/after landing `add-academic-term`?**

Short answer: **finish them first** (they unblock clean integration), then apply
the small extension tasks below. You do **not** need to wait to *start*
`add-academic-term` — the core can proceed — but the coordination tasks at the
end of `add-academic-term/tasks.md` (§15) depend on these two being applied.

---

## 1. `rbac-read-and-menu-restructure` — status 15/19

**What it is:** adds five `*.read` permissions, enforces them on GET endpoints
across iam/academic-config/grading, and restructures the sidebar into a grouped,
access-aware menu.

**Current state:**
- Backend permission seed + grants + GET enforcement: **done** (tasks 1–3).
- Web grouped sidebar + visibility helper: **done** (tasks 4–5).
- **Still open:** 3.4 (per-service integration tests), 5.4 (visibility test),
  6.1 (confirm `secure-published-report-card` merged), 6.3 (full `make test`).

### What you must do with it

**Finish it before `add-academic-term` ships.** The term feature leans on the
read-permission layer it establishes:

| `add-academic-term` need | Provided by `rbac-read-and-menu-restructure` |
|---|---|
| Term GET endpoints gated on `academic.config.read` | The `academic.config.read` permission + `require_permission` pattern (tasks 2.1, 3.2) |
| Term write endpoints gated on `academic.config.write` | Already exists; reused as-is |
| Menu entry for term management visible to readers | The grouped sidebar + visibility helper (tasks 4.1, 5.1) |

**Concrete todos for you (in order):**

1. **Close the open test tasks** so the regression net is real before adding new
   endpoints:
   - [ ] 3.4 — integration tests asserting each built-in role reads its areas and a role lacking the read gets 403.
   - [ ] 5.4 — web test asserting menu items hide/show for admin/teacher/parent/ops-only.
   - [ ] 6.3 — `make test` across both submodules + web lint/typecheck.
2. **Resolve the dependency on `secure-published-report-card`** (task 6.1):
   - [ ] Confirm `secure-published-report-card` is merged; if not, merge/coordinate first, otherwise the student/parent `report.read` path 403s.
3. **Confirm the `academic_ops` feature_code** (task 6.2 is already checked; just keep it consistent when `add-academic-term` adds the ops projection — no feature gate is needed for terms, they ride on academic-config).
4. **Archive it** (`openspec archive`) once 1–2 are green.

### What `add-academic-term` adds back to it

When you implement `add-academic-term` §15.1, you will:

- [ ] Add the new term GET endpoints to the `academic.config.read` enforcement (a one-liner `require_permission` per handler, same as the existing year/curriculum handlers).
- [ ] Add a menu entry for term management under `Pengaturan → Akademik → Semester/Term` in the grouped sidebar; its visibility follows the existing `academic_config + academic.config.read` mapping (task 5.2) — **no new permission code is needed**.

These are additive and do not reopen `rbac-read-and-menu-restructure`.

---

## 2. `tenant-audit-log` — status 0/26 (not started)

**What it is:** consumes `tenant_user.*` events into an append-only `audit_log`
store with a read API + admin UI, gated on a new `audit.view` permission. Scope
is explicitly **IAM user-management only**.

**Current state:** untouched. Depends on `rbac-custom-roles-multirole` (already
archived) for the permission layer.

### What you must do with it

**You have a choice. Two viable orderings:**

#### Option A (recommended): ship `add-academic-term` first, using its interim local store, then let `tenant-audit-log` subsume it

This matches the precedent already set by `simplify-academic-year-status`:
academic-year transitions write to a local `academic_year_status_transition`
table as an **interim** store, and `tenant-audit-log`'s stated plan is to move
the write target to `audit_log` later.

- [ ] Proceed with `add-academic-term` now; term transitions write to the local
      `academic_term_status_transition` table (mirrors the year one).
- [ ] When you start `tenant-audit-log`, **extend its scope** to also consume
      `academic_year.*` and `academic_term.*` events (currently it only binds
      `tenant_user.*`). Add these to:
  - [ ] Task 3.1 — RabbitMQ binding: add `academic_year.*`, `academic_term.*`
        alongside `tenant_user.*`.
  - [ ] Task 3.2 — insert one `audit_log` row per event (idempotent on
        `event_id`); the `details` JSONB naturally holds the transition payload
        including `reason`.
  - [ ] Task 5.1 — tests for the new event types.
- [ ] Decide (open question in `simplify-academic-year-status/design.md`):
      retain or drop the local `*_status_transition` tables after migration.
      Lean: **retain** them as a fast operational view; the `audit_log` becomes
      the system-of-record trail.

**Why this ordering is better:** `tenant-audit-log` is 0/26 and IAM-scoped;
`add-academic-term` is ready to go and unblocks the product. Don't block the
product feature on an audit refactor.

#### Option B: start `tenant-audit-log` first, generalize it, then build `add-academic-term` on top

Only worth it if you specifically want the audit trail to be the *only* store
from day one (no interim tables).

- [ ] Do Option A's `tenant-audit-log` extension tasks **before** implementing
      `add-academic-term` §3.4 (term transitions).
- [ ] Skip the `academic_term_status_transition` table entirely in
      `add-academic-term` §2.1; write transitions directly to `audit_log` via
      the consumer.
- [ ] Cost: `add-academic-term` is blocked behind 26+ tasks of audit work.

### Recommendation

**Option A.** The interim-table pattern is already in production for academic
years, so terms just follow suit. `tenant-audit-log` then becomes a
**generalization** task: widen its consumer from `tenant_user.*` to the broader
`*.*` event space (or at least `tenant_user.* + academic_year.* +
academic_term.*`). This is a clean, additive change to its scope.

### Concrete todos for you (if Option A)

1. **Do nothing to `tenant-audit-log` right now** — it does not block
   `add-academic-term`.
2. When you eventually start it:
   - [ ] Update its `proposal.md` "Out of scope" bullet (currently says
         "auditing non-user-management actions (billing, academic config,
         grading)") to reflect the decision to include academic-year and
         academic-term transitions.
   - [ ] Add `academic_year.*` and `academic_term.*` to the consumer binding
         (tasks 3.1/3.2) and tests (5.1).
   - [ ] Document the relationship between the local `*_status_transition`
         tables and `audit_log` in its design (retain-vs-migrate decision).

---

## Summary table

| Change | Do what | When | Blocks `add-academic-term`? |
|---|---|---|---|
| `rbac-read-and-menu-restructure` | **Finish + archive** (tests 3.4/5.4, dep 6.1, make test 6.3) | Before shipping term endpoints | Yes — term GETs need `academic.config.read` enforcement |
| `tenant-audit-log` | **Defer / generalize later** to consume `academic_year.*` + `academic_term.*` | After `add-academic-term` (Option A) | No — interim local store covers it |

**Bottom line:** finish `rbac-read-and-menu-restructure` now (it's 79% done and
unblocks clean term endpoints); leave `tenant-audit-log` for later and widen its
scope when you build it.
