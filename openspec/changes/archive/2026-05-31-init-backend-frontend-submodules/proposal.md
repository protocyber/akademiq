## Why

The `protocyber/akademiq` repository today only holds documentation — there is no
backend or frontend code yet. The architecture spec (`docs/internal/06_container_architecture/`,
`docs/internal/13_engineering_standards/01_repo_structure.md`) calls for a Rust/Axum backend
monorepo and a Next.js web frontend, both of which need their own git history,
release cadence, and CI before any service work can start. Vendoring those two
codebases as git submodules under this docs repo gives contributors a single
checkout to read the spec and work on the code without entangling histories.

## What Changes

- Create two new private GitHub repos under the `protocyber` org:
  - `protocyber/akademiq-backend` — Rust/Axum monorepo (will host `services/` and `libs/` per `13_engineering_standards/01_repo_structure.md`).
  - `protocyber/akademiq-web` — Next.js web application (the `WEB` container in `06_container_architecture/AcademiQ_Container_Diagram.md`).
- Initialise each new repo with only a `README.md` and a sensible `.gitignore`. No Cargo workspace, no `create-next-app` scaffold, no Makefile targets — those land in follow-up changes.
- Add both repos as git submodules of this parent repo:
  - `apps/backend` → `git@github.com:protocyber/akademiq-backend.git`
  - `apps/web`     → `git@github.com:protocyber/akademiq-web.git`
- Track `main` on both submodules in `.gitmodules` (`branch = main`) so `git submodule update --remote` follows upstream.
- Update root `README.md` and `AGENTS.md` to:
  - Document the new `apps/backend` and `apps/web` mount paths.
  - Replace the "repo contains only documentation" wording with the new submodule layout.
  - Add a short "Working with submodules" section (clone with `--recurse-submodules`, `git submodule update --init --recursive`, SSH key requirement).
- Refactor `docs/internal/13_engineering_standards/01_repo_structure.md` so its tree is rooted at `/apps/backend/...` instead of `/backend/...`, keeping its scope to the backend's internal layout and adding a one-line cross-reference to `apps/web` as a separate submodule.
- Add a top-level `.gitignore` rule (if needed) so submodule working trees are not double-tracked.

Non-goals (explicit, to keep this change small):

- No Cargo workspace, no service stubs, no `common-*` crates inside `apps/backend`.
- No Next.js app, no auth boilerplate, no Tailwind/Zod inside `apps/web`.
- No CI workflows in either submodule.
- No structural rewrite of any other `docs/internal/` file beyond updating path-style references that point at `/backend/...`. Diagrams, prose, and per-service docs are not edited in this change.

## Capabilities

### New Capabilities

- `repo-layout`: Defines the parent repo's submodule contract — which submodules exist, where they are mounted, what URL form `.gitmodules` uses, which branch each tracks, and the contributor workflow for cloning and updating them.

### Modified Capabilities

<!-- None. No existing specs in openspec/specs/ are affected; this is the first concrete capability. -->

## Impact

- **Affected files in this repo**:
  - New: `.gitmodules`, `apps/backend/` (submodule pointer), `apps/web/` (submodule pointer).
  - Modified: `README.md` (mention submodules + clone instructions), `AGENTS.md` ("Repo state" section, path-style references, new "Submodules" section), `docs/internal/13_engineering_standards/01_repo_structure.md` (tree rooted at `/apps/backend`).
- **External**: Two new private GitHub repos under `protocyber/` with one initial commit each (`README.md` + `.gitignore`).
- **Contributor workflow**: Existing clones must run `git submodule update --init --recursive` after pulling. New clones should use `git clone --recurse-submodules`. SSH access to `protocyber/akademiq-backend` and `protocyber/akademiq-web` becomes a prerequisite.
- **CI**: None today; future CI in this repo will need `submodules: recursive` on checkout actions.
- **Docs**: `docs/internal/13_engineering_standards/01_repo_structure.md` is rewritten to use `/apps/backend/...` paths; no other `docs/internal/` file is structurally edited (path-style `/backend/` references in surrounding files, if any, are aligned in pass-through edits during the same task and verified with `rg`).
- **Downstream changes unblocked**: Cargo workspace scaffold, first service (likely `iam-service`), Next.js frontend scaffold, shared CI templates.
