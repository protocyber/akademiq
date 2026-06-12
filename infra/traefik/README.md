# AcademiQ — Traefik dev routing

> **Environment-specific. Not required to run AcademiQ.**
>
> Everything in this directory documents **one maintainer's** local dev setup.
> The host names (`akademiq.dev.sby.test`, `akademiq.10.201.0.25.nip.io`), the
> LAN IP (`10.201.0.25`), and the host ports are all specific to that machine.
>
> AcademiQ is open source. You do **not** need Traefik, this domain, or this IP
> to develop. You can run the stack on `localhost` with no reverse proxy, use
> your own domain/ports, or use a different proxy (Caddy, nginx, ...). This
> folder is a working reference for how the maintainer fronts the web app and
> the backend APIs behind a single HTTPS origin — adapt freely.

## What this provides

A single public origin serves both the web app and the backend APIs:

| Path                          | Routed to                | Priority |
|-------------------------------|--------------------------|----------|
| `/api/v1/iam/*`               | iam-service `:8081`      | 100      |
| `/api/v1/billing/*`           | billing-service `:8082`  | 100      |
| `/api/v1/academic-config/*`   | academic-config `:8083`  | 100      |
| `/api/v1/academic-ops/*`      | academic-ops `:8084`     | 100      |
| `/api/v1/grading/*`           | grading-service `:8086`  | 100      |
| everything else               | Next.js web app `:3009`  | 1        |

Host: `akademiq.dev.sby.test` (and `akademiq.10.201.0.25.nip.io`). HTTP is
redirected to HTTPS via the shared `redirect-https` middleware.

Because path routing happens at the proxy, the web client uses absolute
**same-origin** base URLs (`NEXT_PUBLIC_*_BASE_URL=https://akademiq.dev.sby.test`)
and needs **no Next.js rewrite/proxy**.

## Files

- `akademiq.dynamic.yaml` — the akademiq-only Traefik file-provider fragment
  (routers + services). **Reference-only** for shared definitions: it references
  the `redirect-https@file` middleware and the default TLS store but does not
  define them.

## How it is wired into the live Traefik

> **Traefik has no nginx/apache-style `include` directive.** The shared
> `services.yaml` does **not** reference this file. Instead, Traefik's file
> provider runs in **directory mode** (`--providers.file.directory=/etc/traefik`
> with `--providers.file.watch=true`) and **auto-merges every `*.yaml` file** in
> that directory. So "including" this fragment just means making it appear inside
> `/etc/traefik` — Traefik merges it with `services.yaml`/`tls.yaml` into one
> config. Cross-file references work because of that merge (this fragment can
> reference `redirect-https@file` and the default TLS store defined in
> `services.yaml`).

The live Traefik instance is owned by the shared infra repo
`surabaya-dev/traefik` (deployed via Portainer). To make this fragment visible to
Traefik **without putting any akademiq config in the `surabaya-dev` repo**, the
file is bind-mounted into `/etc/traefik` via the **Portainer stack definition**
(Web editor) — not via the committed `surabaya-dev` compose. Add this line to the
`traefik` service `volumes:` in Portainer, then redeploy the stack:

```yaml
- /home/fitrah/projects/akademiq/infra/traefik/akademiq.dynamic.yaml:/etc/traefik/akademiq.dynamic.yaml:ro
```

Notes:
- The host path must exist on the Docker host running Traefik (same machine,
  `10.201.0.25`). A single-file bind mount requires the file to already exist at
  start, otherwise Docker creates an empty directory in its place.
- Keeping the mount in Portainer (not in the `surabaya-dev` repo) is deliberate:
  the akademiq routing config lives **only in this repo**. The tradeoff is an
  invisible dependency — the live Traefik silently depends on this file — which
  is why it is documented here and in the parent `AGENTS.md`.

Shared, cross-project definitions stay in
`surabaya-dev/traefik/dynamic/services.yaml`:

- `redirect-https` middleware (HTTP→HTTPS),
- the `tls` store and the `dev.sby.test.crt` / `dev.sby.test.key` certificates
  (mounted at `/etc/traefik/certs`).

**Certificates are never committed here.** The `.key` is a secret; the cert
files live only in the shared repo's gitignored `certs/`.

After editing this fragment or the shared compose, redeploy the Traefik stack
in Portainer and confirm routes resolve (e.g. `https://akademiq.dev.sby.test`
loads the app and `https://akademiq.dev.sby.test/api/v1/iam/healthz` returns the
IAM health JSON).

## Adding a new backend service

When a new backend service lands under `apps/backend/services/<name>-service`,
add its mapping here so it is reachable through the same origin:

1. Pick its `<SERVICE>_PORT` and keep `apps/backend/.env.example` in sync.
2. Add an `akademiq-<name>-https` router with
   `PathPrefix(\`/api/v1/<name>\`)` and `priority: 100`.
3. Add a matching `akademiq-<name>` service `loadBalancer` entry pointing at
   `http://10.201.0.25:<SERVICE_PORT>` (adapt host/IP for your environment).

This keeps the proxy mapping in lockstep with the service set. Agents and
developers must update this fragment as part of adding a backend service.
