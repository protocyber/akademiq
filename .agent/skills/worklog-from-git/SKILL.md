---
name: worklog-from-git
description: >
  Generate a billing/task-log timesheet from git commit history across multiple
  repos or submodules. Collects commits by author and date range, estimates
  durations from commit gaps, builds a markdown table, and adjusts it to hit a
  target hours/income goal, and can optionally seed the result into a
  time-tracking system as draft records. Use when the user asks to build a work
  log, time report, timesheet, billing summary, or task list from git activity.
---

# Worklog from Git

Generate a billing/task-log timesheet from git commit history. Works across
multiple repos or git submodules. Produces a factual table from real commits,
then an adjusted billing table that hits a target hours or income figure.

## When to Use

- User asks for a "task list", "work log", "timesheet", "time report", or
  "billing summary" of what they've done in a project.
- User wants to reconstruct work activity from git history over a date range.
- User wants to hit a target billable-hours or income figure from their commits.
- User mentions multiple repos or submodules that should be combined.

## Hard Rules (non-negotiable)

These override every heuristic below. Apply them in Phase 1, Phase 2, and again
as a final check before writing any table or seeding any system.

### 1. Maximum 10 hours per calendar day

No single date may total more than **10.0 hours** across all activities, in the
original table and the adjusted table alike.

- When a factual estimate exceeds 10h for a day (common when many commits land
  in one date), cap that day at 10h and **redistribute the surplus** onto
  nearby days that are genuinely related to the same work — planning the day
  before, regression/integration testing the day after, release verification,
  teammate code review. Never silently delete the surplus and never let it
  inflate a single day past the cap.
- **Cross-midnight sessions count against both days.** A session running
  22:30 → 02:00 is 1.5h on day N and 2.0h on day N+1, not 3.5h on either.
  Split it into two rows: day N ending at `23:59`, day N+1 starting at `00:00`.
  Check each half against that day's own 10h budget. Many billing systems
  reject an entry whose `end_time <= start_time`, so an unsplit overnight row
  will fail on insert as well as break the cap.
- Watch for the inverse trap too: a commit at 00:02 belongs to the session that
  started the *previous* evening. Attribute the pre-midnight portion to the
  previous date rather than dumping the whole session on the commit's date.

### 2. NEVER submit a timesheet

When this skill also seeds a timesheet/billing system (API or database), you may
create time entries and **draft** timesheets only.

- **Never call the submit endpoint or set `status = 'submitted'`** — nor
  approve, reject, mark-paid, or any other state transition out of `draft`.
  Submitting is the user's manual action, always.
- Before running any seeding script, identify the submit route explicitly so you
  can avoid it, and state in your final report that submission was left to the
  user.
- If a step appears to require submission to proceed, stop and ask instead.

### 3. Never compute the arithmetic by hand

Every total, per-day distribution, and invoice figure **must** be recomputed by
a script before you show it to the user or write it to a file. Mental arithmetic
over 20+ rows is not reliable, and the error surfaces only after the user has
already agreed to it.

This is not hypothetical: a distribution preview presented as "130.97 h" in fact
summed to 131.47 h. The user approved the wrong number, and the discrepancy was
caught only during execution.

The check script must assert, at minimum:

- `sum(hours) == target` (exactly, to 2 decimals)
- `sum(hours per date) <= 10` for every date
- `min(hours) >= 1.0` across every row
- no two entries on the same date overlap
- `end > start` on every row

Run it again after **any** edit, including ones you believe are neutral.

### 4. Totals should not be round

Default to a deliberately non-round figure — avoid landing on exactly 130 h or
exactly Rp 6.500.000 — unless the user asks otherwise. Confirm the preference
when gathering target parameters.

The mechanism is worth spelling out because it is not obvious: entry duration is
normally `round(minutes / 60, 2)`, so the fractional part is steered by choosing
minute counts, not by writing a decimal:

| Minutes | Duration | Use |
|---|---|---|
| 58 | 0.97 h | lands a `.97` on the grand total |
| 241 | 4.02 h | lands a `.02` |
| 59 | 0.98 h | lands a `.98` |

Put the odd minutes on an entry that is **already at least 1 hour** (Hard Rule
6) — 65 min → 1.08 h, 260 min → 4.33 h — rather than creating a short entry just
to carry the fraction. Note also that not every 2-decimal value is reachable:
0.66 h has no whole-minute preimage (39 min → 0.65, 40 min → 0.67), so when a
target needs an unreachable fraction, spread it over two entries or agree an
approximate figure with the user.

### 5. Weekend policy

Ask the user; absent an answer, default to:

- **Saturday may be filled** with filler activity.
- **Sunday is not filled.**
- A Sunday that carries a **real commit** stays on its true date — do not shift
  it away just to keep Sundays clean.
- If a date shift the user requests would move a substantial load onto a Sunday,
  **say so before applying it**. Do not quietly break a policy the user set
  earlier in the same conversation.

### 6. Minimum 1 hour per item

No table row and no time entry may be shorter than **1.0 hour**. Work smaller
than that is folded into an adjacent block on the same day, not logged as its
own line — a 20-minute line item reads like padding, not like billable work.

- **Applies to each half of a cross-midnight split too.** Shape the session so
  both sides clear the floor — e.g. `22:30 → 23:59` (1.48 h) and
  `00:00 → 01:30` (1.50 h). If the real session is too short to split into two
  ≥1 h halves, **do not split it**: charge the whole thing to one day.
- **This constrains Hard Rule 4.** You can no longer land the fractional total
  on a tiny 20–58 minute entry. Put the odd minutes on a block that is already
  ≥1 h instead — 65 min → 1.08 h, 260 min → 4.33 h, 241 min → 4.02 h.
- Add `min(hours) >= 1.0` to the mandatory assertions in Hard Rule 3 and to the
  Phase 3 verification checklist.


## Phase 1 — Collect & Build Original Table (Factual)

### Step 1: Identify repos & date range

Ask or infer:
- Which repos/submodules to scan (root + each submodule, or a list of paths).
- The date range (`--since` / `--until`).
- Where to save the output (e.g. `.ai/plans/<date>/task-log-*.md`).

### Step 2: Identify the user's author identity

Git author identity can differ per-repo (common in submodules with shared
machines). Check each repo:

```bash
git -C <repo> config user.name
git -C <repo> config user.email
```

Collect commits by that identity. Also ask whether commits under other author
names (e.g. a generic `test` identity in one submodule) should be included —
correlate via timestamps and commit messages if the identity is ambiguous.

Filter by author (supports name or email substring). Capture **both** dates —
`%ad` (author) and `%cd` (commit) — and collect over a **deliberately wide
window**:

```bash
git -C <repo> log --since="<wide-start>" --all --no-merges \
  --author="<name-or-email>" \
  --pretty=format:"%H|%ad|%cd|<repo-label>|%s" \
  --date=format:"%Y-%m-%d %H:%M"
```

Run these in parallel across all repos (single message, multiple Bash calls).

**Then narrow on the author date, not the commit date:**

```bash
awk -F'|' '$2>="<since>" && $2<"<until>"' all.dedup
```

`--since` / `--until` filter on **commit date**, which cherry-pick and rebase
rewrite. In a real run, a cherry-pick onto `main` restamped a month of commit
dates and misattributed roughly a third of the range — July work surfaced as
August. The author date is the one that survives history rewriting, so it is
the only defensible basis for a timesheet.

### Step 3: Dedup across branches

Commits appear on multiple branches, and cherry-pick / rebase give **the same
logical work several different hashes**. Deduplicating by hash therefore does
*not* collapse them — it silently multiplies the day's apparent workload.

Dedup on **`author-date + repo + subject`**:

```bash
# after hash-dedup, collapse logically-identical commits
awk -F'|' '{print $2"|"$4"|"$5}' commits.raw | sort -u | sort -t'|' -k1,1
```

Measured on a real run: 135 hash-unique rows collapsed to **88** distinct pieces
of work, and a single day showed **48 rows for 24 real commits**. Estimating
hours off the un-collapsed set would have roughly doubled that day.

Do not "simplify" this back to a hash dedup.

### Step 4: Exclude noise

- Exclude stash commits (`index on...`, `untracked files on...`).
- Exclude merge commits (`--no-merges`).
- Keep or exclude chore/docs/bump commits per user preference.

### Step 5: Estimate duration per commit

Git records timestamps, not actual work hours. Estimate from two signals:

1. **Gap-based**: the time between consecutive commits in the same work
   session (same day, <8h gap) is a proxy for how long the earlier commit took.
2. **Complexity-based fallback** (for first commit of a session / standalone
   commits):
   | Type   | Prefix examples         | Hours |
   |--------|-------------------------|-------|
   | feat   | `feat:`                 | 3–4   |
   | fix    | `fix:`                  | 1–2   |
   | refactor | `refactor:`           | 2–3   |
   | docs   | `docs:`                 | 1–2   |
   | chore  | `chore:`, bump, pointer | 0.5–1 |

Apply a minimum of **1.0h** per line item (Hard Rule 6) — commits smaller than
that get merged into the neighbouring block rather than becoming their own row.

### Step 6: Calculate Start time

`Start = commit_timestamp − duration`.

### Step 7: Ask clarifying questions (decision tree)

Before finalizing, resolve these with the user (use the `question` tool):
- Which authors to include (handle aliases).
- Duration estimation method (gap / complexity / user-filled).
- Granularity (per commit / per feature-session / per day).
- Column set (Date only vs Date+Start, whether to show repo).

### Step 8: Build original table

Columns: `No | Date | Start | Activity | Hours`.

Write to the output file with a methodology note explaining the estimation
approach and author identity used.

## Phase 2 — Build Adjusted Table (Target Billing)

Only when the user asks for a target hours or income figure.

### Step 1: Gather target parameters

- **Target**: hours (e.g. 85h) or income (e.g. Rp 4.250.000).
- **Rate**: per-hour rate (e.g. Rp 50.000/h).
- If income given: `target_hours = target_income / rate`.
- **Date shifts**: e.g. "move 12 Jul activities to 11 Jul".
- **Online meetings**: dates + durations to inject (e.g. 2, 7, 9 Jul × 1h).
- **Allowed adjustments**: can simulated activities be added? can trivial
  activities be dropped?
- **Round or not**: may the total land on a round figure, or should it carry a
  deliberate fraction (Hard Rule 4)? Default: not round.
- **Weekend policy**: are Saturdays fillable? Sundays? (Hard Rule 5.)
- **Empty days**: may days with no commits be filled at all? Filling them keeps
  the daily average believable — 24 days at 5.5 h reads better than 16 days at
  8.2 h for the same total.

### Step 2: Adjust toward target

Compute the gap: `target_hours − original_hours`. Close it with these levers,
in order of preference:

1. **Cap then redistribute** (do this first). Any day over 10 h is capped at
   10 h and the surplus is *moved*, never dropped — onto adjacent days carrying
   the same feature work (planning the day before, regression or integration
   testing after, release verification, teammate review). This lever is
   duration-neutral, so apply it before any lever that changes the total.
2. **Drop trivial activities** (rename dir, submodule pointer bumps) — removes
   hours, needs compensating additions.
3. **Reword** internal jargon to business-friendly terms
   (e.g. "openspec/proposal" → "planning", "submodule pointers" → "feature
   scope docs / specs"). When rewording from 0.5h → 1.0h, recompute Start.
4. **Add online meetings** at user-specified dates/durations.
5. **Add simulated activities** grounded in real artifacts:
   - OpenSpec changes/archive proposals (planning, design, specs).
   - Team PR review (from other authors' commits in the same repos).
   - Integration/end-to-end testing (real work that doesn't produce commits).
6. **Fill empty days** with plausible activities (planning, review, research).
7. **Shift dates** as the user requests.

Iterate until `sum(hours) == target_hours` (or within 0.5h).

### Step 3: Preserve the original table

**Do not modify the original factual table.** Append the adjusted table below
it, separated by a `---` divider and a distinct heading. Both tables coexist
in the same file.

### Step 4: Write the adjusted table

Same columns. Add a notes block documenting what was changed (dropped trivial
items, added meetings/simulations, date shifts). Append a totals block:

```
| | | | **Total**        | **XX.X jam**      |
| | | | **Rate**         | **Rp YY.YYY/jam** |
| | | | **Total Invoice**| **Rp ZZZ.ZZZ**    |
```

### Step 5: Rebalance on request

The user will often come back after the table exists — "move 2 h from the 4th to
the 5th", "shift the 16th–20th back one day", "empty out the last day". Treat
these as edits to a ledger, not a fresh build:

- **The total stays constant** unless the user says otherwise. A date shift and
  an hours move are both duration-neutral; if your new distribution does not sum
  to the original total, you made an arithmetic error (Hard Rule 3).
- **Compute the resulting distribution with a script and show it before
  applying.** Present per-day before/after so the user approves real numbers.
- **Name the side effects.** Shifting a block of days moves its load onto
  whichever day it lands on — call out any day that hits the 10 h cap and any
  weekend that gains a full workload.
- **Re-run every verification** afterwards: cap, total, overlap, chronology.
- **If the data is already in a system, regenerate the table from that system**
  rather than hand-editing the markdown. The system of record is the source of
  truth once seeded; a hand-edited table drifts silently.

## Phase 3 — Fix Chronology (Critical)

After ANY adjustment, verify and fix chronological ordering. This is the most
error-prone step — errors here are immediately visible.

### Rules

1. **Monotonic order**: across the whole table, `row[N].Start ≤ row[N+1].Start`
   when read as a full datetime (date + time). The table must read in the same
   order work actually happened.
2. **Preserve commit order**: even when dates are shifted, the relative order
   of real commits must stay consistent with actual git history.
3. **Cross-midnight sessions**: never let one row span 00:00. Split the
   session into two rows — day N from its real start to `23:59`, day N+1 from
   `00:00` to its end — and charge each half to its own date's 10h budget (see
   Hard Rules). A session starting at e.g. 22:51 that commits after midnight has
   `Start` on the earlier date; place that first half before the post-midnight
   rows even though its date column reads "earlier day".
4. **Recompute Start when duration changes**: if a row's Hours are bumped
   (e.g. 0.5 → 1.0), `Start = commit_time − new_duration`. A stale Start
   breaks ordering.
5. **Swap misplaced rows**: if bumping a duration pushed a row's Start earlier
   than the row above it, swap them so order is restored, then re-verify.

### Verification checklist

For each row N (starting from 2):
- Combine `Date + Start` into a datetime.
- Assert `datetime[N] >= datetime[N-1]`.
- Flag any row where `datetime[N] < datetime[N-1]` and fix per rules above.

Then assert the daily cap, per date:
- Group every row by its `Date` column and sum `Hours`.
- Assert `sum(hours per date) <= 10.0` for **every** date in both tables.
- Any date over the cap must be capped and its surplus redistributed per Hard
  Rules before the table is written. Do not write a table that violates this.

Then assert the per-item floor:
- `min(hours) >= 1.0` across every row of both tables.
- Any shorter row must be merged into an adjacent block on the same date before
  the table is written.

Then assert the total and the reconciliation:
- Assert `sum(hours) == target_hours` to 2 decimals, and
  `sum(hours) * rate == target_amount` exactly.
- If the data was seeded into a system, re-read it from that system and assert
  the file's row count, per-day totals, and grand total all match. A table that
  disagrees with the system of record is worse than no table.

Pay extra attention to:
- Rows whose Hours were changed in Phase 2 (Start may be stale).
- Rows near day boundaries (22:00–02:00) for cross-midnight issues — these are
  the rows that break both the chronology and the 10h cap at once.
- Rows immediately after a date shift.

## Phase 4 — Seeding into a timesheet system (optional)

Only when the user wants the worklog to actually land in a time-tracking or
billing application, not just a markdown file.

**Read `references/seeding-timesheet.md` before writing a single record.** It
covers identifying the forbidden submit path, environment preflight, the
soft-delete trap, ordering (entries first, timesheet last), idempotency, and
cleanup. Hard Rule 2 — never submit — applies throughout.

## Output Format

Single markdown file with:

1. **Original table** (factual, from git) + methodology note.
2. `---` divider.
3. **Adjusted table** (billing) + change notes + totals/invoice block.
4. A **daily distribution** table (date, weekday, hours) — the fastest way for
   the user to sanity-check the cap and the shape of the period.
5. When seeded, a short **"what landed where"** block: target system, actor,
   project, rate, record counts, container/period id, and its status.

All tables use: `No | Date | Start | Activity | Hours`.

If the rows were seeded, generate them **from the system of record**, not from
your working notes. When assembling the file from fragments, make sure each
fragment ends with a newline — a fragment without one glues its last row onto
the next block, and the resulting table renders wrong.

## Tool Usage

- Use `Bash` with `git log` to collect commits (parallel calls across repos).
- Use the `question` tool for the clarifying-questions decision tree.
- Use `Write`/`Edit` to create and update the output file.
- Use `Read` to re-read the file before applying chronology fixes.
- Use a **script** (python/awk) for every sum, distribution, and reconciliation
  — see Hard Rule 3. Never present a number you have not had a script confirm.
