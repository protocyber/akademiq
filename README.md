# akademiq

AcademiQ adalah platform SaaS multi-tenant untuk manajemen sekolah — mencakup
identitas pengguna, tenant & langganan (billing), konfigurasi dan operasional
akademik, kehadiran, penilaian, serta kenaikan dan kelulusan.

Repo ini adalah parent repo: berisi dokumentasi arsitektur dan dua git
submodule yang menyimpan kode aplikasi.

## Struktur

| Path           | Repo                                              | Isi                                |
|----------------|---------------------------------------------------|------------------------------------|
| `apps/backend` | `git@github.com:protocyber/akademiq-backend.git`  | Backend monorepo (Rust + Axum)     |
| `apps/web`     | `git@github.com:protocyber/akademiq-web.git`      | Web frontend (Next.js)             |
| `docs/`        | tidak ada submodule                               | Spesifikasi arsitektur dan produk  |

## Memulai

Submodule dilayani lewat SSH ke organisasi `protocyber` di GitHub. Pastikan
kunci SSH Anda terdaftar dan memiliki akses ke kedua repo private tersebut.

```bash
# Clone baru (sekaligus mengisi semua submodule)
git clone --recurse-submodules git@github.com:protocyber/akademiq.git

# Clone yang sudah ada (mengisi submodule yang masih kosong)
git submodule update --init --recursive

# Tarik perubahan upstream pada satu submodule
git submodule update --remote --merge apps/backend
git submodule update --remote --merge apps/web
```

## Quick start (pengembangan lokal)

Prasyarat:

- Docker Desktop ≥ 4.24 (atau Docker Engine + plugin compose ≥ 2.22)
- Node 20 LTS via [nvm](https://github.com/nvm-sh/nvm); `nvm use` mengambil
  versi dari `apps/web/.nvmrc`
- `corepack enable` (sekali saja; ikut Node ≥ 16.13) — pnpm dipinned di
  `apps/web/package.json`
- Opsional: `brew install mprocs tmux` untuk pengalaman terbaik (mprocs
  jadi orchestrator utama, tmux jadi fallback)

Setelah submodule diisi, salin tiga `.env` dan jalankan:

```bash
cp .env.example .env
cp apps/backend/.env.example apps/backend/.env
cp apps/web/.env.example apps/web/.env

make doctor    # periksa tooling, beri petunjuk instalasi jika ada yang kurang
make dev       # primary: mprocs (backend + web bersamaan)
```

Alternatif `make dev`:

- `make dev-tmux` — fallback tanpa mprocs (perlu tmux)
- `make dev-parallel` — fallback terakhir tanpa tooling tambahan
  (`make -j2`, log digabung)

Target lain: `make up` / `make down` untuk infra backend (Postgres + RabbitMQ),
`make build` / `make test` mendelegasikan ke kedua submodule.

Setiap submodule juga bisa dijalankan mandiri (`cd apps/backend && make dev`,
`cd apps/web && make dev`) tanpa parent repo. Detail per-app ada di README
masing-masing submodule.

## Dokumentasi

- `docs/internal/` — spesifikasi arsitektur dan rekayasa, disusun dalam 13 level
  bernomor dari proses bisnis hingga standar engineering. Mulai dari
  [`docs/internal/README.md`](docs/internal/README.md).
- `docs/product/` — panduan pengguna akhir (admin sekolah, guru, wali kelas,
  siswa, orang tua, billing, FAQ).
- `docs/marketing/` — brosur, presentasi, materi situs web.

## Kontribusi

Lihat [`AGENTS.md`](AGENTS.md) untuk konvensi repo, aturan penamaan
Tenant & Subscription (Billing) Service, target tech stack, kontrak API/event,
serta aturan git/commit. Berlaku untuk kontributor manusia maupun AI agent.

---

# akademiq (English)

AcademiQ is a multi-tenant SaaS platform for school management — covering
identity, tenant & subscription billing, academic configuration and operations,
attendance, grading, and promotion.

This repository is a parent repo: it holds the architecture documentation and
two git submodules that contain the application code.

## Layout

| Path           | Repo                                              | Contents                           |
|----------------|---------------------------------------------------|------------------------------------|
| `apps/backend` | `git@github.com:protocyber/akademiq-backend.git`  | Backend monorepo (Rust + Axum)     |
| `apps/web`     | `git@github.com:protocyber/akademiq-web.git`      | Web frontend (Next.js)             |
| `docs/`        | not a submodule                                   | Architecture and product specs     |

## Quick start

Submodules are served over SSH from the `protocyber` GitHub organisation.
Make sure your SSH key is registered and has access to both private repos.

```bash
# Fresh clone (populates submodules in one step)
git clone --recurse-submodules git@github.com:protocyber/akademiq.git

# Existing clone (populate empty submodules)
git submodule update --init --recursive

# Pull upstream changes for one submodule
git submodule update --remote --merge apps/backend
git submodule update --remote --merge apps/web
```

## Local development

Prerequisites:

- Docker Desktop ≥ 4.24 (or Docker Engine + compose plugin ≥ 2.22)
- Node 20 LTS via [nvm](https://github.com/nvm-sh/nvm); `nvm use` picks up
  the version from `apps/web/.nvmrc`
- `corepack enable` (one-time; bundled with Node ≥ 16.13) — pnpm is pinned
  in `apps/web/package.json`
- Optional: `brew install mprocs tmux` for the best experience (mprocs is
  the primary orchestrator, tmux is the fallback)

After submodules are populated, copy the three `.env` files and start:

```bash
cp .env.example .env
cp apps/backend/.env.example apps/backend/.env
cp apps/web/.env.example apps/web/.env

make doctor    # checks tooling and prints install hints if anything's missing
make dev       # primary: mprocs (backend + web together)
```

Alternatives to `make dev`:

- `make dev-tmux` — fallback for machines without mprocs (needs tmux)
- `make dev-parallel` — last-resort fallback with no extra tooling
  (`make -j2`, logs interleave)

Other targets: `make up` / `make down` manage the backend infra
(Postgres + RabbitMQ); `make build` / `make test` delegate into both
submodules.

Each submodule is also independently runnable
(`cd apps/backend && make dev`, `cd apps/web && make dev`) without the parent
repo. Per-app details live in the submodule READMEs.

## Documentation

- `docs/internal/` — architecture and engineering specs, organised in 13
  numbered levels from business process to engineering standards. Start at
  [`docs/internal/README.md`](docs/internal/README.md).
- `docs/product/` — end-user guides (school admin, teacher, homeroom teacher,
  student, parent, billing, FAQ).
- `docs/marketing/` — brochures, presentations, website copy.

## Contributing

See [`AGENTS.md`](AGENTS.md) for repo conventions, the Tenant & Subscription
(Billing) Service naming rule, target tech stack, API/event contracts, and
git/commit rules. Applies to both human contributors and AI agents.
