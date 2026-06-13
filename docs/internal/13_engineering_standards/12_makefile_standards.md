# Makefile Standards

Required targets:

make dev       # run service locally
make migrate   # run DB migrations
make test      # run tests
make build     # build Docker image
make up        # start compose stack
make down      # stop compose stack

## Cost guard for SLOW targets

Targets that take minutes or destroy artefacts — `build`, `seed`, `test`,
`test-e2e`, `test-web`, `clean` — must:

- Be tagged `(SLOW)` in their `## ` help description.
- Guard their first recipe line with `scripts/confirm.sh "<target>" "<cost>"`,
  which prints a warning and asks before proceeding.

`scripts/confirm.sh` auto-proceeds (no prompt) when stdin is not a TTY, when
`CI` is set, or with `YES=1` — so CI and scripted runs never hang. Parent-repo
targets that delegate to a submodule pass `YES=1` to the sub-make to avoid a
double prompt. The daily targets (`dev`, `up`, `down`, `migrate`)
stay friction-free.

See the "Make commands — when to run what" table in
`11_devops_local_setup.md` for when each target is appropriate.