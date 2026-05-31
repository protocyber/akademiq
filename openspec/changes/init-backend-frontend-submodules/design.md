## Context

`protocyber/akademiq` currently holds only documentation. The architecture spec
under `docs/internal/` describes a Rust/Axum backend monorepo and a Next.js web
frontend that will be built. We want a single parent checkout that gives a
contributor (or AI agent) the spec plus the code, without merging histories.

Constraints from `AGENTS.md` and `docs/internal/13_engineering_standards/`:

- The backend monorepo layout (`/backend/services/...`, `/backend/libs/...`)
  is fixed by `01_repo_structure.md`. That layout lives *inside* the backend
  submodule.
- The frontend is a Next.js app — the `WEB` container in
  `06_container_architecture/AcademiQ_Container_Diagram.md`.
- All three repos are private under the `protocyber` GitHub org. SSH is the
  contributor access channel.
- No CI exists in this repo today; whatever we add must not break the docs-only
  workflow people are using right now.

Stakeholders: backend engineers, frontend engineers, future CI, AI agents
following `AGENTS.md`.

## Goals / Non-Goals

**Goals:**

- Ship a deterministic mount layout (`apps/backend`, `apps/web`) that matches
  the user's chosen scheme.
- Make `git clone --recurse-submodules` and `git submodule update --init
  --recursive` the only steps a contributor needs.
- Track `main` on both submodules so doc work in this parent repo can pull in
  upstream changes without manual SHA bumps when desired.
- Keep this change reversible: removing the submodules and reverting the docs
  must restore the docs-only state.

**Non-Goals:**

- Cargo workspace, service crates, `common-*` libs, Makefile targets, or any
  Rust source inside `apps/backend`.
- Next.js scaffold, Tailwind, auth UI, or any TypeScript inside `apps/web`.
- CI workflows in either repo (parent or submodules).
- Choosing or wiring linters, formatters, or pre-commit hooks.
- Touching `docs/internal/13_engineering_standards/01_repo_structure.md` —
  that doc describes the backend's *internal* layout and stays correct.

## Decisions

### Decision 1: Two separate repos, mounted as git submodules

Backend and frontend live in `protocyber/akademiq-backend` and
`protocyber/akademiq-frontend`. They are added to this parent repo as git
submodules at `apps/backend` and `apps/web`.

**Rationale:** Independent histories, independent CI later, and clean
ownership. The user explicitly chose submodules over subtree or no-vendoring.

**Alternatives considered:**

- Git subtree — embeds full history in the parent. Heavier checkout, harder
  to push back upstream.
- No vendoring — keep three sibling clones. Loses the "one parent checkout"
  property the docs already encourage.
- Single combined `akademiq-app` repo with a `backend/` and `frontend/` tree —
  rejected because backend (Rust) and frontend (Next.js) have very different
  CI and release cadences and we want to avoid coupling them.

### Decision 2: Mount paths `apps/backend` and `apps/web`

The user picked these over `/backend` + `/frontend` and `/services/...`.

**Rationale:** `apps/` is a familiar layout for mixed-language repos and keeps
room for future siblings (e.g., `apps/mobile`, `apps/admin`) without renaming.
The internal backend layout (`backend/services/...`) still applies — it is
now `apps/backend/services/...` from the parent view, which matches
`13_engineering_standards/01_repo_structure.md` once you read its `/backend`
prefix as the submodule root.

**Note:** No doc updates are needed inside
`docs/internal/13_engineering_standards/01_repo_structure.md` because that
file is scoped to "inside the backend repo" — its tree starts at `/backend`.

### Decision 3: SSH URLs, private repos

`.gitmodules` uses `git@github.com:protocyber/akademiq-backend.git` and
`git@github.com:protocyber/akademiq-frontend.git`.

**Rationale:** Both repos are private; SSH is the chosen contributor channel.
Relative URLs were considered but the user picked explicit SSH URLs, which
makes it obvious where each submodule points without having to know the
parent's origin.

**Trade-off:** Anyone cloning over HTTPS (e.g., a hypothetical CI without SSH
keys) will need either an SSH key or a `git config url."https://".insteadOf`
rewrite. Documented in `AGENTS.md` and root `README.md`.

### Decision 4: Track `main` on both submodules

`.gitmodules` sets `branch = main` on each submodule entry, so
`git submodule update --remote` follows the upstream `main`.

**Rationale:** Both submodules will start essentially empty. Most early
churn will be in the submodule's own `main`. Tracking `main` keeps the parent
repo's pinned SHA easy to advance when needed.

**Trade-off:** A fast-moving `main` upstream can produce noisy "submodule
updated" commits in the parent. Acceptable given how early we are.

### Decision 5: Submodule contents — README + .gitignore only

The user picked the smallest scope. Each new repo gets:

- `README.md` — one-paragraph description, link back to the parent docs repo,
  link to the relevant section of `docs/internal/`.
- `.gitignore` — language-appropriate (Rust for backend, Node/Next.js for
  frontend) so an agent that later runs `cargo init` or `pnpm create next-app`
  doesn't immediately have to fix a missing ignore file.

**Rationale:** Defers Cargo workspace and Next.js scaffolding to dedicated
follow-up changes that can be reviewed on their own merits.

### Decision 6: Use `gh` CLI to create the GitHub repos

`gh repo create protocyber/akademiq-backend --private` (and same for
frontend), then push the initial `README.md` + `.gitignore` commit before
running `git submodule add`.

**Rationale:** Reproducible from a script, no manual GitHub UI clicks.
Requires `gh auth status` to be authenticated — checked as a precondition in
`tasks.md`.

**Alternative considered:** Create the repos via GitHub API directly with
`curl`. Rejected — `gh` is already the standard in this repo's workflow and
handles auth nicely.

## Risks / Trade-offs

- **Risk: Existing clones break after this change** → Mitigation: Update root
  `README.md` and `AGENTS.md` with the `git submodule update --init
  --recursive` step. Print a one-line note in the PR description.
- **Risk: SSH-only URLs block HTTPS contributors / CI** → Mitigation:
  Document the SSH requirement in `README.md`. If HTTPS becomes a real need,
  switch to relative URLs in a follow-up (one-line `.gitmodules` change).
- **Risk: Submodules drift out of sync with parent** → Mitigation: Track
  `main` so `git submodule update --remote` is safe. The parent commits a
  pinned SHA only when a contributor explicitly bumps it.
- **Risk: AGENTS.md "Repo state (read first)" section becomes stale** → Must
  be updated in the same change. Listed as a task.
- **Risk: `apps/` path conflicts with later decisions** → Low. No existing
  paths use `apps/`. Renaming a submodule is one `git mv` + `.gitmodules`
  edit if we ever need to.
- **Trade-off: Empty submodules look pointless** → Accepted. The point is to
  lock in the layout and URLs first, then scaffold in dedicated reviewable
  changes.

## Migration Plan

1. Verify `gh auth status` is authenticated as a `protocyber` org member with
   repo-creation rights.
2. Create the two GitHub repos (private), push initial commits to each
   `main`.
3. From this parent repo on a feature branch:
   - `git submodule add -b main git@github.com:protocyber/akademiq-backend.git apps/backend`
   - `git submodule add -b main git@github.com:protocyber/akademiq-frontend.git apps/web`
4. Update `README.md` and `AGENTS.md`.
5. Open a PR. Reviewers clone the branch with `--recurse-submodules` to
   verify both pointers resolve.

**Rollback:**

- In the parent repo: `git submodule deinit -f apps/backend apps/web`,
  `git rm -f apps/backend apps/web`, `rm -rf .git/modules/apps/backend
  .git/modules/apps/web`, revert `.gitmodules`/`README.md`/`AGENTS.md`.
- The two new GitHub repos can be archived or deleted via `gh repo delete`
  if nothing else has been pushed there yet.

## Open Questions

- None blocking. Future considerations (not part of this change): branch
  protection rules on the new submodule repos, CODEOWNERS, default labels.
  Tracked separately.
