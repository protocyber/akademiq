# Manual-test hub

Serves the manual test documents in `docs/manual-tests/` and keeps every
tester's progress on the server, **per user and per document**. Sign in as the
same user on a laptop, a phone or another browser and you continue where you
stopped — no tester codes or resume links. Open tabs of the same user update
live (server-sent events); changes made offline are queued in the browser and
sent when the connection returns.

Runs as one container (`oven/bun:1-alpine`, no dependencies) on the shared
`proxy` network; Traefik routes `akademiq-testing.oracle.fitrah.web.id` to it
(`~/traefik/dynamic/akademiq.yml` on the oracle dev VM).

## Quick start

```bash
cd scripts/test-hub
make init                                     # hub.yaml from hub.example.yaml
make user-add U=fitrah NAME="Fitrah" ROLE=admin   # prompts for a password
make user-add U=rina NAME="Rina (QA)"             # tester (default role)
make up                                       # start; prints the URL
```

From the repo root the same commands are `make hub-up`, `make hub-user-add …`,
`make hub-passwd U=…`, `make hub-users`, `make hub-status`, `make hub-logs`,
`make hub-down`.

## Configuration: `hub.yaml`

Compose-style YAML, gitignored. `${VAR}` / `${VAR:-default}` are filled from
the environment and from a `.env` file next to `hub.yaml`; `$$` is a literal
`$`. The server re-reads the file when it changes, so adding a user or changing
a password needs no restart.

```yaml
server:
  title: ${HUB_TITLE:-AkademiQ Test Hub}
  port: 8090
  public_url: https://akademiq-testing.oracle.fitrah.web.id
  timezone: Asia/Jakarta

docs:
  dir: docs/manual-tests      # relative to the repository root

users:
  fitrah:
    name: "Fitrah"
    role: admin               # admin | tester
    password_hash: "$argon2id$v=19$..."
  rina:
    name: "Rina (QA)"
    role: tester
    password_hash: "$argon2id$v=19$..."
    disabled: true            # optional: blocks sign-in, keeps progress
```

Passwords are stored only as argon2id hashes, written by `make user-add` /
`make passwd` (or `make hash` to print one for hand editing). A plain
`password:` key is ignored with a warning. Changing a password signs out every
session of that user. `make check` validates the file.

Roles:

- **tester** — runs documents and sees their own progress; the index shows
  everyone's progress summary.
- **admin** — also opens any user's progress read-only (sidebar "Lihat
  progres") and can reset it.

## Using the runner

- Mark each step **Pass / Fail / Blocked / Skipped** (unmarked = Untested);
  marking Fail jumps to the note. Notes save as you type.
- Sidebar: overall ring, per-phase progress, filters (All / Untested /
  Issues = Fail + Blocked / Notes), "Langkah berikutnya", "Laporan" (Markdown report with failures
  first), "Reset progres".
- Keyboard: `j`/`k` move, `Space` next open step, `p` `f` `b` `s` set status,
  `u` clear, `n` note, `x` collapse, `?` help.

## How it works

| Piece | Where |
|---|---|
| Server (Bun, no deps) | `server.ts` — routes, sessions, progress store, SSE |
| Config loader | `config.ts` |
| User management CLI | `cli.ts` (run through `make`, inside a throwaway Bun container) |
| Frontend | `public/` — `index.*` list, `runner.*` test runner, `login.html` |
| Container | `compose.yml` — mounts the code, `hub.yaml` and `docs/manual-tests` read-only |
| Progress | volume `akademiq-test-hub_state`: `progress/<user>/<slug>.json`, `session.key` |

Progress is a set of per-step records (`status`, `note`, timestamp) plus
recorded values. Clients send small operations; the server applies them under
a per-file lock, so two devices editing different steps never overwrite each
other and the last write wins for the same field. Sessions are signed cookies
(HMAC with `session.key`, 30 days, HttpOnly, Secure behind HTTPS) bound to the
user's password hash. Five failed sign-ins from one address add an
exponential delay.

`make backup` writes `backup-<timestamp>.tar.gz` with every user's progress.
