# repo-layout Specification

## Purpose

Defines the parent `akademiq` repository's submodule mount layout, the upstream
target repositories, contributor onboarding documentation, and the path-style
references used throughout the repo's documentation.

## Requirements

### Requirement: Parent repo SHALL declare backend and web submodules at fixed mount paths

The parent `akademiq` repository MUST declare exactly two git submodules in
its top-level `.gitmodules` file: one mounted at `apps/backend` pointing to
the backend code repo, and one mounted at `apps/web` pointing to the web
frontend code repo. No other submodules SHALL be declared by this change.

#### Scenario: Submodule entries are present

- **WHEN** a contributor inspects `.gitmodules` at the repo root after this change is applied
- **THEN** the file contains a `[submodule "apps/backend"]` section and a `[submodule "apps/web"]` section, and no other submodule sections

#### Scenario: Mount paths are unchanged

- **WHEN** a contributor runs `git config -f .gitmodules --get-regexp path`
- **THEN** the only paths returned are `apps/backend` and `apps/web`

### Requirement: Submodule URLs SHALL use SSH on GitHub under the protocyber org

Each submodule entry in `.gitmodules` MUST point at a private GitHub
repository under the `protocyber` organisation using the SSH URL form
`git@github.com:protocyber/<repo>.git`. HTTPS URLs SHALL NOT be used for
submodule entries in this change.

#### Scenario: Backend submodule URL

- **WHEN** a contributor reads the `url` value of the `apps/backend` submodule entry in `.gitmodules`
- **THEN** the value is exactly `git@github.com:protocyber/akademiq-backend.git`

#### Scenario: Frontend submodule URL

- **WHEN** a contributor reads the `url` value of the `apps/web` submodule entry in `.gitmodules`
- **THEN** the value is exactly `git@github.com:protocyber/akademiq-web.git`

### Requirement: Submodule entries SHALL track the upstream main branch

Both submodule entries in `.gitmodules` MUST set `branch = main` so that
`git submodule update --remote` follows the upstream `main` branch on each
submodule.

#### Scenario: Branch tracking is configured

- **WHEN** a contributor runs `git config -f .gitmodules --get submodule.apps/backend.branch` and `git config -f .gitmodules --get submodule.apps/web.branch`
- **THEN** both commands print `main`

#### Scenario: Remote update follows main

- **WHEN** a contributor on a clean checkout runs `git submodule update --remote --merge` and the upstream `main` of either submodule has advanced
- **THEN** the working tree of that submodule is updated to the upstream `main` HEAD without manual SHA editing

### Requirement: Initial submodule contents SHALL be limited to README and gitignore

Each newly created submodule repository MUST contain only a `README.md` and
a `.gitignore` at the time this change is merged. The repositories
`protocyber/akademiq-backend` and `protocyber/akademiq-web` SHALL NOT
contain any source files, build configuration, CI workflows, or scaffolded
applications as part of this change.

#### Scenario: Backend submodule is empty of code

- **WHEN** a contributor lists the working tree of `apps/backend` after a fresh `git submodule update --init`
- **THEN** the only tracked files are `README.md` and `.gitignore`

#### Scenario: Frontend submodule is empty of code

- **WHEN** a contributor lists the working tree of `apps/web` after a fresh `git submodule update --init`
- **THEN** the only tracked files are `README.md` and `.gitignore`

### Requirement: Contributor onboarding documentation SHALL describe the submodule workflow

The parent repo's root `README.md` and `AGENTS.md` MUST document the
submodule layout (mount paths and target repos), the SSH access
prerequisite, and the commands required to populate submodules on a fresh
or existing checkout.

#### Scenario: README documents submodules

- **WHEN** a new contributor reads `README.md`
- **THEN** they find the `apps/backend` and `apps/web` mount paths, the two target GitHub repos, and the commands `git clone --recurse-submodules <repo>` (for fresh clones) and `git submodule update --init --recursive` (for existing clones)

#### Scenario: AGENTS.md reflects new repo state

- **WHEN** an AI agent or contributor reads `AGENTS.md`
- **THEN** the "Repo state" section reflects that backend and web code now live in submodules at `apps/backend` and `apps/web`, and a "Submodules" section explains the workflow and SSH requirement

### Requirement: Path-style references in repo docs SHALL match the parent mount layout

Every path-style reference to the backend monorepo in this repo's `AGENTS.md`, `README.md`, and files under `docs/internal/` MUST use a path rooted at `/apps/backend` rather than `/backend`. The internal layout under that root (e.g., `services/<name>-service`, `libs/common-{auth,db,logging,errors}`) MUST be preserved unchanged. Descriptive prose using "backend" or "frontend" as nouns (e.g., "backend services", "frontend Zod") is NOT a path-style reference and SHALL remain unchanged.

#### Scenario: Engineering standards repo structure tree is re-rooted

- **WHEN** a contributor reads `docs/internal/13_engineering_standards/01_repo_structure.md`
- **THEN** the tree begins with `/apps/backend` and lists `services/...` and `libs/...` underneath, with no occurrence of a top-level `/backend` directory in the tree

#### Scenario: AGENTS.md monorepo bullet matches mount paths

- **WHEN** a contributor reads the "Target tech stack" section in `AGENTS.md`
- **THEN** the monorepo layout bullet uses `/apps/backend/services/<name>-service` and `/apps/backend/libs/common-{auth,db,logging,errors}`

#### Scenario: No stale top-level path references remain

- **WHEN** a reviewer runs `rg -n '(^|[ \t\(])/backend(/|[\s\)\.,;])' AGENTS.md README.md docs/`
- **THEN** the command returns no matches
