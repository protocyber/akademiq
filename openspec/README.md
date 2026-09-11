# OpenSpec (frozen)

This directory is **read-only historical reference**. The repo's active
planning system is [Superpowers](https://github.com/obra/superpowers); see
"Planning workflow" in the repo root [`AGENTS.md`](../AGENTS.md).

Do **not** create new OpenSpec changes, run `openspec` CLI commands, or add
files under `openspec/changes/`. New design specs and implementation plans go
under `docs/superpowers/`.

## What's still useful here

- `openspec/specs/` — capability contracts the current code honours. Read
  these when you need to understand what a service or UI area is supposed to
  do; treat `docs/internal/` as the tie-breaker if the two disagree.
- `openspec/changes/archive/` — a record of how each shipped change was
  proposed, designed, and broken into tasks. Useful history, not a live
  worklist.
