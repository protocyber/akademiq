## 1. Preconditions

- [ ] 1.1 Confirm `gh auth status` is authenticated as a user with repo-creation rights on the `protocyber` GitHub org
- [ ] 1.2 Confirm `git --version` is `>= 2.34` (for `git submodule add -b` and reliable `--recurse-submodules` behaviour) and `ssh -T git@github.com` succeeds
- [ ] 1.3 Confirm the parent repo working tree is clean (`git status` shows no uncommitted changes outside the openspec change directory) and we are on a feature branch (not `main`)
- [ ] 1.4 Confirm neither `protocyber/akademiq-backend` nor `protocyber/akademiq-frontend` already exists on GitHub (`gh repo view protocyber/akademiq-backend` and `gh repo view protocyber/akademiq-frontend` both return "Not Found")

## 2. Create the backend repo

- [ ] 2.1 Create the GitHub repo: `gh repo create protocyber/akademiq-backend --private --description "AcademiQ backend monorepo (Rust/Axum). See protocyber/akademiq for architecture docs." --disable-issues=false --disable-wiki`
- [ ] 2.2 In a temp directory, `git init -b main` an empty working tree for the backend repo
- [ ] 2.3 Add an initial `README.md` to the backend repo with: project name, one-paragraph description, link to `https://github.com/protocyber/akademiq` and to `docs/internal/13_engineering_standards/01_repo_structure.md` for the in-repo layout, "no scaffold yet" note
- [ ] 2.4 Add a Rust-flavoured `.gitignore` to the backend repo (covers `/target`, `**/*.rs.bk`, `Cargo.lock` for libs only if/when relevant — leave commented out, `.env`, `.idea/`, `.vscode/`, OS noise)
- [ ] 2.5 Commit (`feat: initialize akademiq-backend with README and gitignore`) and push: `git remote add origin git@github.com:protocyber/akademiq-backend.git && git push -u origin main`
- [ ] 2.6 Verify the push: `gh repo view protocyber/akademiq-backend --json defaultBranchRef,visibility` returns `main` and `PRIVATE`

## 3. Create the frontend repo

- [ ] 3.1 Create the GitHub repo: `gh repo create protocyber/akademiq-frontend --private --description "AcademiQ web frontend (Next.js). See protocyber/akademiq for architecture docs." --disable-issues=false --disable-wiki`
- [ ] 3.2 In a temp directory, `git init -b main` an empty working tree for the frontend repo
- [ ] 3.3 Add an initial `README.md` to the frontend repo with: project name, one-paragraph description, link to `https://github.com/protocyber/akademiq` and to `docs/internal/06_container_architecture/AcademiQ_Container_Diagram.md` (the `WEB` container), "no scaffold yet" note
- [ ] 3.4 Add a Node/Next.js-flavoured `.gitignore` to the frontend repo (covers `node_modules/`, `.next/`, `out/`, `dist/`, `coverage/`, `.env*`, `.idea/`, `.vscode/`, OS noise)
- [ ] 3.5 Commit (`feat: initialize akademiq-frontend with README and gitignore`) and push: `git remote add origin git@github.com:protocyber/akademiq-frontend.git && git push -u origin main`
- [ ] 3.6 Verify the push: `gh repo view protocyber/akademiq-frontend --json defaultBranchRef,visibility` returns `main` and `PRIVATE`

## 4. Wire submodules into the parent repo

- [ ] 4.1 From the parent repo root, ensure `apps/` does not already exist as a tracked path
- [ ] 4.2 Add the backend submodule tracking `main`: `git submodule add -b main git@github.com:protocyber/akademiq-backend.git apps/backend`
- [ ] 4.3 Add the frontend submodule tracking `main`: `git submodule add -b main git@github.com:protocyber/akademiq-frontend.git apps/web`
- [ ] 4.4 Open `.gitmodules` and verify both entries have `path`, `url`, and `branch = main`. Hand-add `branch = main` if `git submodule add -b` did not persist it
- [ ] 4.5 Run `git submodule status` and confirm two entries appear, both at the upstream `main` SHA
- [ ] 4.6 Run `git submodule update --remote --merge` once and confirm it is a no-op (working trees already at upstream `main`)

## 5. Update parent repo documentation

- [ ] 5.1 Update root `README.md`: replace the "repository currently contains documentation only" wording (both Indonesian and English sections) with a description of the new layout. Add a "Quick start" section listing `git clone --recurse-submodules git@github.com:protocyber/akademiq.git` and, for existing clones, `git submodule update --init --recursive`. Mention SSH access requirement
- [ ] 5.2 Update `AGENTS.md` "Repo state (read first)": replace the "only documentation" claim with the actual state — backend at `apps/backend` (submodule), web at `apps/web` (submodule), docs unchanged
- [ ] 5.3 Add a new "Submodules" section to `AGENTS.md` listing the two submodules, their target repos, mount paths, branch tracking, and the SSH prerequisite. Cross-reference `13_engineering_standards/01_repo_structure.md` for in-backend layout
- [ ] 5.4 Verify nothing under `docs/internal/` was modified by this change (`git diff --name-only main -- docs/internal/` returns empty)

## 6. Validate, commit, push, PR

- [ ] 6.1 Run `openspec validate init-backend-frontend-submodules --strict` and resolve any reported issues
- [ ] 6.2 Re-clone the parent repo into a fresh temp directory using `git clone --recurse-submodules` against the feature branch and confirm `apps/backend/README.md` and `apps/web/README.md` are populated
- [ ] 6.3 Stage `.gitmodules`, `apps/backend`, `apps/web`, `README.md`, `AGENTS.md`, and the openspec change directory; do not stage anything else
- [ ] 6.4 Commit with a message describing the addition of the two submodules and the doc updates (no AI/agent attributions per `AGENTS.md`)
- [ ] 6.5 Push the feature branch and open a PR with `gh pr create`. PR description must include the migration step (`git submodule update --init --recursive`) for existing clones and confirm no `docs/internal/` changes
- [ ] 6.6 After PR review and merge, run `openspec archive init-backend-frontend-submodules` (handled by `/opsx-archive`)

## 7. Rollback (only if needed)

- [ ] 7.1 If the change must be rolled back before merge: `git submodule deinit -f apps/backend apps/web`, `git rm -f apps/backend apps/web`, `rm -rf .git/modules/apps`, revert edits to `.gitmodules`, `README.md`, `AGENTS.md`
- [ ] 7.2 If both new GitHub repos are still empty/untouched, optionally archive or delete them: `gh repo delete protocyber/akademiq-backend --yes` and `gh repo delete protocyber/akademiq-frontend --yes` (requires explicit user confirmation per `AGENTS.md` git safety rules)
