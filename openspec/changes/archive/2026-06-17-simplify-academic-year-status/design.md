## Context

The academic-year status model today is a 7-state, strictly forward-only state
machine defined in
`apps/backend/services/academic-config-service/src/domain.rs:7-42`:

```
Planning → Configuration → Active → Locked → Finalizing → Closed → Archived
```

This design originated in a single architecture-scaffold commit
(`971629c`) and is stricter than the documented implementation intent
(`16_implementation_phases.md:83` says `draft → active`). Two intermediate
states (`Locked`, `Finalizing`) have no real side effects in code: the
grading-service event handler only reacts to `Closed`/`Archived`
(`grading-service/src/events.rs:156-170`), and no guard in the system keys off
`Locked` or `Finalizing`. The forward-only rule recently blocked recovery from
an accidental `Active → Locked` click with no API path to undo it.

Consumers of `academic_year.status_changed`:
- `academic-ops-service` upserts `known_academic_year.status` (idempotent) and
  uses it to gate homeroom creation on `Active`.
- `grading-service` upserts `valid_year.status` (idempotent) and archives
  published report cards when status is `Closed` or `Archived`.

Both consumers are already idempotent on status upsert, which makes undo safe
at the projection level.

## Goals / Non-Goals

**Goals:**
- Collapse the lifecycle to 4 meaningful states: `Draft`, `Active`, `Closed`,
  `Archived`.
- Allow undo for any transition that has not yet reached `Archived`.
- Make `Closed` operationally meaningful: homeroom creation and new grade entry
  are blocked; report cards stay `Published` and accessible.
- Reserve `Archived` as the single irreversible, destructive transition (report
  cards archived).
- Require an auditable `reason` on every transition.
- Provide a confirmation UX tights enough to prevent accidental irreversible
  changes.

**Non-Goals:**
- Full integration with the in-progress `tenant-audit-log` change. This change
  only specs the audit hook and stores `reason` locally; real audit-log wiring
  lands with that change.
- Attendance guards on `Closed` years — the attendance module is not yet
  implemented.
- Changing the one-`Active`-year-per-tenant invariant (preserved as-is).
- Changing homeroom, enrollment, or report-card workflows beyond the status
  trigger.

## Decisions

### Decision 1: 4-state model with bidirectional undo except out of `Archived`

```
   Draft  ⇄  Active  ⇄  Closed  ──▶  Archived (final)
```

Transition matrix:

```
         │ to Draft │ to Active │ to Closed │ to Archived │
─────────┼──────────┼───────────┼───────────┼─────────────┤
Draft    │    —     │    ✓      │    ✗      │     ✗       │
Active   │    ✓     │    —      │    ✓      │     ✗       │
Closed   │    ✓     │    ✓      │    —      │     ✓       │
Archived │    ✗     │    ✗      │    ✗      │     —       │
```

`Draft → Closed`, `Draft → Archived`, and `Active → Archived` remain illegal
(one-step skips across the destructive boundary are not allowed; a year must go
through `Closed` before `Archived`). No-op transitions (same status) are
rejected as `INVALID_STATE_TRANSITION`.

**Rationale:** Keeping `Draft → Closed` illegal mirrors the original intent
that closing a year implies it was once running. Requiring `Closed` as the
gateway to `Archived` preserves a safe undo window before the destructive
archive step.

**Alternatives considered:**
- Free rollback including `Archived → Closed`: rejected — `Archived` archives
  published report cards, which is not trivially reversible.
- Flat `Draft ⇄ Active ⇄ Closed ⇄ Archived` (allow skip `Draft → Closed`):
  rejected — adds complexity without clear value.

### Decision 2: Legacy state remapping during migration

```
Planning, Configuration  → Draft
Locked, Finalizing       → Active
Active, Closed, Archived → unchanged
```

**Rationale:** `Locked`/`Finalizing` were operational-only states with no
persisted side effects, so mapping them to `Active` is safe — those years were
still effectively in session. `Planning`/`Configuration` both mean "not yet
running" and collapse cleanly into `Draft`.

The migration runs a single `UPDATE` per remapped value inside a transaction
and is idempotent (re-running on already-remapped values is a no-op because the
old values no longer exist).

### Decision 3: Report-card archival fires only on `→ Archived`

The grading-service handler today archives published report cards on both
`Closed` and `Archived`. This change respecifies it to fire **only** on
`→ Archived`.

**Rationale:** With undo from `Closed → Active` allowed, archiving at `Closed`
would make that undo non-restorative (report cards would already be archived).
Restricting archival to the irreversible `Archived` transition keeps `Closed`
fully reversible and makes `Archived` the single destructive point.

**Consequence:** Consumers must treat `Closed` as "operations halted, data
intact" and `Archived` as "data swept into historical storage."

### Decision 4: New grade-entry guard in grading-service keyed on `valid_year`

Today grade editability is driven by report-card status (`Draft`/`null` =
editable, `Published` = locked) and is independent of year status. To make
`Closed` operationally meaningful, grading-service gains a guard: recording a
new grade is rejected when `valid_year.status != 'Active'` for the evaluation's
year.

**Rationale:** The `valid_year` projection already exists and is maintained by
the `academic_year.status_changed` consumer, so no new projection is needed.
The guard is checked in the grade-record command alongside existing
authorization and report-card-status checks.

**Alternatives considered:**
- Key the guard on report-card status only (status quo): rejected because then
  `Closed` would not block grade entry, making it semantically identical to
  `Active` and defeating the simplification.
- Add the guard in academic-ops instead: rejected — grade entry is a
  grading-service concern; ops has no grade domain.

### Decision 5: `reason` required on every transition

The PATCH `/academic-years/{id}/status` request gains a required `reason`
string (min 10 chars, trimmed). The command stores it in a lightweight local
`academic_year_status_transition` log (id, year_id, tenant_id, from_status,
to_status, reason, actor_user_id, occurred_at) and includes it in the
`academic_year.status_changed` payload.

**Rationale:** Undo-able transitions increase the risk of silent churn; a
mandatory reason gives operators and auditors a paper trail. The local log is
an interim store; when `tenant-audit-log` lands, the write target switches to
it without changing the command contract.

**Alternatives considered:**
- Optional `reason`: rejected — operators would skip it, defeating the audit
  goal.
- Require `reason` only for backward transitions: rejected — forward
  transitions to `Archived` are the most destructive and most deserve a reason.

### Decision 6: Confirmation UX — type-to-confirm + cooldown

The web status-change flow uses a confirmation dialog with three tiers:

| Transition | Confirmation |
|---|---|
| Forward to `Active` or `Closed` | AlertDialog with impact summary + reason field |
| Backward (`Active → Draft`, `Closed → Active`, `Closed → Draft`) | Type-to-confirm (type the target status) + 5s cooldown before the submit button enables + reason field |
| Forward to `Archived` | Type-to-confirm (`ARCHIVED`) + 5s cooldown + extra prominent "irreversible / report cards will be archived" warning + reason field |

**Rationale:** Backward and `→ Archived` transitions carry the highest
operational risk; the type-to-confirm + cooldown pattern (modeled on
destructive cloud-console actions) makes accidents unlikely without making the
common forward path cumbersome.

**Alternatives considered:**
- Simple OK/Cancel for all transitions: rejected as too easy to misclick,
  especially given the original incident.
- Mandatory second approver for `→ Archived`: rejected as out of scope for now;
  can be added later if needed.

### Decision 7: Event payload gains `reason`

`academic_year.status_changed` gains `reason` alongside `previous_status` and
`status`. Consumers ignore unknown fields, so this is backward-compatible.

## Risks / Trade-offs

- **[Risk] Event handler assumptions break on backward events** → Any consumer
  that implicitly assumes status only moves forward could misbehave on undo.
  *Mitigation:* both current consumers are pure upserts keyed on the latest
  status and only trigger side effects on specific values (`Closed`/`Archived`
  for archival). After this change the archival trigger is narrowed to
  `Archived` only, which is never a target of an undo. Document the
  forward-assumption caveat in the event contract for future consumers.
- **[Risk] Migration remaps live data incorrectly** → If a tenant genuinely
  relied on `Locked`/`Finalizing` semantics, mapping them to `Active` could
  reopen operations they expected closed. *Mitigation:* these states had no
  enforced side effects in code, so the practical impact is nil; the migration
  is announced in release notes and is reversible by re-issue if needed.
- **[Risk] Undo hides operator mistakes from audit** → Without persistence,
  repeated undo/redo churn is invisible. *Mitigation:* mandatory `reason` plus
  the local transition log captures every attempt; full audit integration
  follows with `tenant-audit-log`.
- **[Risk] Grade-entry guard rejects in-flight teacher work** → A year moved
  to `Closed` while teachers are mid-entry will start failing their saves.
  *Mitigation:* the tights confirmation UX plus `reason` makes accidental
  closure unlikely; undo to `Active` restores entry immediately.
- **[Trade-off] `Closed` no longer auto-archives report cards** → Tenants used
  to (hypothetically) seeing cards archived at `Closed` must now archive
  explicitly. This is intentional and aligns with the undo model.

## Migration Plan

1. **Backend deploy (academic-config-service first):**
   - Ship migration `V<n>` that (a) remaps legacy `status` values per Decision 2
     and (b) creates `academic_year_status_transition` log table.
   - Ship updated `YearStatus` enum, `can_transition_to`, command, and HTTP
     handler (with `reason`).
2. **Deploy consumers (academic-ops, grading):**
   - academic-ops: default `unwrap_or("Draft")`.
   - grading: narrow archival trigger to `→ Archived`; add grade-entry guard.
3. **Web deploy:**
   - Updated Zod schema, transition map, `StatusConfirmDialog`, playwright.
4. **Docs:**
   - Rewrite state-machine, API, and event docs in the same release.
5. **Rollback:** The migration is additive (new log table) plus a remapping
   UPDATE. Rollback is achieved by redeploying the prior backend version; the
   remapped status values are still valid strings and the old code accepted
   them (the old enum simply had more variants). A rollback migration to
   restore the original 7 values is not provided because the old variants
   carried no unique data.

## Open Questions

- Should the local `academic_year_status_transition` log be retained after
  `tenant-audit-log` integration, or migrated and dropped? Defer to that
  change.
- Is a second-approver policy needed for `→ Archived` in production tenants
  with many students? Defer until observed in practice.
