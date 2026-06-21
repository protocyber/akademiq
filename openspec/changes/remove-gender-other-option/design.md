## Context

The gender field exists in two entities: students (required, CHECK-constrained)
and teachers (optional, unconstrained). The "other" option was included
originally but the product now requires only male/female.

### Current state across layers

```
Layer              male  female  other   Notes
──────────────────────────────────────────────────────────────────
Frontend schema    ✅    ✅      ✅      z.enum(["male","female","other"])
Student form UI    ✅    ✅      ✅      <SelectItem value="other">Lainnya
Teacher form UI    ✅    ✅      ✅      same
Backend validate   ✅    ✅      ✅      accepts "other"
Student DB CHECK   ✅    ✅      ✅      IN ('male','female','other')
Teacher DB         ✅    ✅      ✅      VARCHAR(16), no CHECK
Dashboard query    ✅    ✅      ❌      only counts male/female (other excluded)
Excel import       ✅    ✅      ✅      lowercases but doesn't translate ID labels
```

### Data migration concern

The student table has `gender VARCHAR(16) NOT NULL` with a CHECK constraint.
If any production row has `gender = 'other'`, tightening the CHECK to
`IN ('male','female')` will fail. Options:

1. **Audit first**: query for `SELECT count(*) FROM student WHERE gender =
   'other'`. If zero, the migration is safe.
2. **If rows exist**: the product owner must decide how to remediate
   (default to 'male', require manual fix, or keep 'other' as legacy).

Given this is early-stage (dev/stage data), the likelihood of existing
'other' rows is low. The migration should include a pre-check that fails
with a clear message if 'other' rows exist, rather than silently
converting them.

## Goals / Non-Goals

**Goals:**
- Remove "Lainnya" from all gender selects in the web UI.
- Backend rejects `"other"` with `VALIDATION_ERROR`.
- DB CHECK constraint tightened to `male`/`female` only.

**Non-Goals:**
- Adding a "prefer not to say" option (not requested).
- Changing the dashboard breakdown query (already correct).
- Translating Indonesian labels in Excel import (that's a Cluster E concern).

## Decisions

### Decision 1: Tighten everywhere — frontend, backend, DB

Remove `"other"` at all three layers in one change. This is the simplest and
most consistent approach. No backward-compatibility shim — any client sending
`"other"` gets a validation error.

*Alternative rejected:* deprecate gradually (accept but warn). Rejected —
over-engineering for an early-stage product with no known "other" data.

### Decision 2: Migration with pre-check

The refinery migration:
1. Checks if any `student` row has `gender = 'other'`. If yes, the migration
   fails with a clear error message directing the operator to remediate.
2. If no 'other' rows, drops the existing CHECK and adds the new one
   `gender IN ('male', 'female')`.

Teacher table has no CHECK, so no migration needed there. But the backend
validation for teachers also drops `"other"`.

*Alternative rejected:* silently `UPDATE student SET gender = 'male' WHERE
gender = 'other'` before tightening. Rejected — silent data mutation is
dangerous and the product owner should decide.

## Risks / Trade-offs

- **[Risk] Existing 'other' rows block migration** → pre-check catches this;
  operator remediates manually. Low probability (early stage).
- **[Risk] Excel templates with "Lainnya" in cells** → import will fail with
  a validation error. This is correct behavior post-change. The template
  instructions (Cluster E) should be updated to only list male/female.

## Migration Plan

1. **Audit**: run `SELECT count(*) FROM student WHERE gender = 'other'` on
   the target environment.
2. **Backend**: add migration (with pre-check), update validation. Deploy.
3. **Web**: remove "Lainnya" from selects, update schema. Deploy.
4. **Verify**: create student/teacher with male/female succeeds; "other" is
   not offered and is rejected if sent via API.

## Open Questions

- If existing 'other' rows are found, how should they be remediated? Default
  to 'male', or require the school to update each record? Lean: require
  manual update (the count is likely zero or very small).
- Should the teacher table also get a CHECK constraint for consistency? Lean:
  yes — add `gender IN ('male','female')` to the teacher table in the same
  migration (currently it's unconstrained VARCHAR).
