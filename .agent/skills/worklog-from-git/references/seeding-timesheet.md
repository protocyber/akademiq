# Seeding a worklog into a timesheet system

Companion to `worklog-from-git`. Read this **before writing a single record**
into any time-tracking, billing, or timesheet application.

Everything here is written generically — endpoint paths, table names, and ids
differ per system. Discover them first; do not guess.

---

## Rule 0 — map the forbidden paths before you map the useful ones

Before any write, enumerate the state transitions the system exposes and write
down which ones you must not touch. Typically:

| Allowed | Forbidden |
|---|---|
| create time entry | **submit** timesheet |
| update / delete your own draft entry | approve / reject |
| create **draft** timesheet | mark paid / bulk mark paid |
| read, preview, report | anything that leaves `draft` |

Submission is the user's manual act. Say so explicitly in your final report so
they know the last step is theirs. If a step looks like it *requires* submitting
to proceed, stop and ask — do not submit to unblock yourself.

## 1. Preflight the environment

**Check which database the running service actually points at**, by reading its
config — not by assuming, and not from memory of an earlier session. The user
may have repointed it between turns.

**Paired clones must match.** When one service owns identity (users) and another
owns the domain (employees), their databases must be clones of the *same*
environment. A production domain clone against a staging identity clone leaves a
chunk of records with no counterpart — it looks exactly like a bug and wastes an
hour before you notice.

## 2. Back up before writing

Dump every database you are about to touch, and note where the dumps live. Cheap
insurance, and it lets you answer "can we undo this?" with yes.

## 3. Preflight the master data — and always select the soft-delete column

The single most expensive mistake of the originating session: a project looked
present and correctly configured, so 39 inserts were attempted and all 39 failed
with "project not found". The row was **soft-deleted** — the first query simply
had not selected `deleted_at`.

Query master data with the soft-delete column visible, every time. Then verify:

- the target project/container exists **and is not soft-deleted**
- the actor is **assigned/a member** of it (many systems reject entries against
  a project you are not assigned to)
- a **rate is in effect on the entry dates**, not merely on today
- the actor's record **type** qualifies (some systems only rate certain types)
- the actor holds the **create/read/update permissions** the routes require
- the target date range is **empty**, so you are extending rather than colliding

## 4. Order of operations: entries first, container last

Create all the time entries, *then* create the draft timesheet that groups them.

Two reasons, both learned the hard way:

- Creating the container first means every subsequent entry is auto-attached to
  it, and correcting a mistake now means fighting the container's totals.
- If a container covering those dates is already in a locked state (submitted /
  approved / paid), entry creation is rejected outright. Discovering that after
  you have built the container is worse than discovering it before.

Creating the container last also gives you a free check: preview it first and
confirm the entry count, hours, and amount match your table exactly before
committing.

## 5. Prefer the API over direct SQL

Write through the application's own endpoints so the server computes derived
fields — duration from start/end, amount from duration x rate, container totals,
rate snapshots. Direct SQL bypasses all of it and leaves totals inconsistent.

Use SQL for **reading and verification** only.

## 6. Constraints these systems commonly enforce

- **`end_time > start_time`.** A single entry therefore cannot cross midnight.
  Split an overnight session into two entries — day N ending `23:59`, day N+1
  starting `00:00` — and charge each half to its own day's cap.
- **Entry date must fall inside the container's period** once attached.
- **A locked container rejects edits** to its entries.
- **Duration is rounded**, usually to 2 decimals from minutes. This is what lets
  you steer the fractional total (see Hard Rule 4 in `SKILL.md`).
- **Membership and rate are checked at create time**, and the rate is normally
  snapshotted onto the row — later rate changes do not retro-apply.

## 7. Make the seeding script idempotent

Key each record on something stable and natural — `(date, start_time, end_time)`
works well. Read the existing records first, skip the ones that already match,
and report `created / skipped / failed` counts. A rerun after a partial failure
should then be safe rather than duplicating.

Fail loudly: if a record you intended to update is not found, abort rather than
guessing. That is the signal that the data already moved.

## 8. Paginate from the response metadata, never from page length

List endpoints silently cap the page size and may ignore your parameter name
entirely. One endpoint here accepted `page_size` but clamped every request to
`limit: 20` — asking for 500 returned 20.

Worse, the obvious loop is wrong. "Stop when a page comes back shorter than
requested" never triggers when the server clamps every page to its own limit, so
a naive loop stops one page early and silently drops the tail. That happened
here: 40 of 41 records were fetched, and the invisible record could have made an
idempotency guard fire on stale data.

Do this instead:

- Read the **response metadata** (`total`, `total_pages`, `limit`) and drive the
  loop from it. Do not infer the end from the size of a page.
- After the loop, **assert `len(fetched) == total`**. Abort if it does not match.
- Unwrap the payload carefully: the records may be nested (`data.entries`), not
  a bare list. Iterating a dict silently yields its *keys* and looks like a
  short, successful result.
- Keep the database as the source of truth for verification. API reads are for
  finding record ids; correctness claims should be backed by a direct query.

## 9. Keep the blast radius minimal on helper scripts

Project helper scripts often bundle several steps. If you only need one of them —
resetting a single password, say — run that one statement rather than the whole
script, especially when another step rewrites unrelated rows.

Tell the user which step you skipped and why. Do improve the script itself if it
was missing something durable (adding a user to its list), just do not run its
destructive parts for a need you do not have.

## 10. Clean up

Stop any service you started in the background once seeding is done. Leaving them
up holds the ports and blocks the user's normal dev workflow — which is exactly
how the originating session ended up with a "port already in use" report.

## 11. Rebalancing after the data is already seeded

When the user asks to move hours or shift dates after seeding:

- Apply the change through the **update** endpoint, one record at a time, so the
  server recomputes duration, amount, and container totals.
- Verify the date stays inside the container's period, and that the container is
  still in an editable state.
- Re-run every verification afterwards.
- Then **regenerate the markdown table from the system**, never by hand-editing.

## 12. Verification queries

Run all of these, and show the results:

```sql
-- no day over the cap (expect zero rows)
SELECT entry_date, SUM(duration_hours) FROM <entries>
WHERE <actor> = :actor AND <soft_delete> IS NULL
  AND entry_date BETWEEN :from AND :to
GROUP BY 1 HAVING SUM(duration_hours) > 10;

-- total hours and amount match the target exactly
SELECT COUNT(*), SUM(duration_hours), SUM(amount) FROM <entries>
WHERE <actor> = :actor AND <soft_delete> IS NULL
  AND entry_date BETWEEN :from AND :to;

-- no entry crosses midnight (expect 0)
SELECT COUNT(*) FROM <entries>
WHERE <actor> = :actor AND <soft_delete> IS NULL AND end_time <= start_time;

-- the container is still a draft
SELECT period_start, period_end, status, total_hours, total_amount, submitted_at
FROM <containers> WHERE <actor> = :actor;
```

The last one is the one that matters most: **status must still be draft and the
submitted-at timestamp must still be null.** Report it verbatim.
