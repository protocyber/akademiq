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
make migrate   # jalankan migrasi backend (membuat iam_db & billing_db)
make seed      # opsional: muat tiga plan + dua tenant demo
make dev       # primary: mprocs (backend + web bersamaan)
```

Demo flow setelah `make dev` siap:

1. Buka `http://localhost:3000/register`, isi nama sekolah, pilih plan,
   buat akun admin, submit.
2. Setelah submit, halaman akan otomatis masuk ke `/dashboard`.
3. Logout → `/login` → masuk lagi dengan kredensial yang sama.
4. Pergi ke `/settings/modules`, toggle modul yang termasuk dalam plan
   Anda. Modul yang tidak termasuk muncul dalam keadaan disabled dengan
   hint untuk upgrade plan.

Akun demo dari `make seed`:

| Tenant       | Plan     | Email admin                       |
|--------------|----------|-----------------------------------|
| Demo Starter | Starter  | `admin@demo-starter.akademiq.dev` |
| Demo Premium | Premium  | `admin@demo-premium.akademiq.dev` |

Password demo akun ada di `apps/backend/services/billing-service/src/bin/seed.rs`.

Alternatif `make dev`:

- `make dev-tmux` — fallback tanpa mprocs (perlu tmux)
- `make dev-parallel` — fallback terakhir tanpa tooling tambahan
  (`make -j2`, log digabung)

### Perintah `make` — kapan dipakai

| Perintah | Kapan dipakai | Biaya |
|---|---|---|
| `make dev` | Loop harian — tiap perubahan kode (cargo-watch di host, infra di Docker) | ~13 dtk/edit, 0.4 dtk no-op |
| `make up` / `make down` | Nyalakan/matikan Postgres + RabbitMQ | detik |
| `make migrate` | Setelah menambah migrasi | cepat |
| `make seed` | Sekali, untuk memuat data demo | **SLOW** — beberapa menit (cold) |
| `make build` | Jarang; hanya untuk menguji **image deploy** rilis (CI yang build → GHCR) | **SLOW** — ~8 mnt cold / ~75 dtk per-service |
| `make test` | Sebelum PR (suite penuh). Cek cepat: `cargo test` di `apps/backend` | **SLOW** — menit |
| `make test-e2e` | Sebelum PR yang menyentuh alur lintas-service | **SLOW** — menit |
| `make test-web` | Vitest + Playwright (web) | **SLOW** — menit |
| `make clean` | Jarang; build berikutnya jadi cold rebuild penuh | **SLOW** build berikutnya — hapus ~9.5 GB |
| `make purge` | Hapus volume + artefak | destruktif (minta konfirmasi) |

> Target **SLOW** memberi peringatan dan minta konfirmasi sebelum jalan; otomatis
> dilewati di CI / non-TTY / dengan `YES=1` (mis. `YES=1 make build`).
> `make rebuild` sudah dihapus — pakai `make dev`.

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
make migrate   # run backend migrations (creates iam_db & billing_db)
make seed      # optional: load three plans + two demo tenants
make dev       # primary: mprocs (backend + web together)
```

Demo flow once `make dev` is up:

1. Open `http://localhost:3000/register`, fill in the school name, pick
   a plan, create the admin account, submit.
2. On submit you land on `/dashboard` already authenticated.
3. Log out → `/login` → log back in with the same credentials.
4. Navigate to `/settings/modules` and toggle modules entitled by your
   plan. Non-entitled modules render disabled with an "Upgrade plan"
   hint.

Demo accounts loaded by `make seed`:

| Tenant       | Plan     | Admin email                       |
|--------------|----------|-----------------------------------|
| Demo Starter | Starter  | `admin@demo-starter.akademiq.dev` |
| Demo Premium | Premium  | `admin@demo-premium.akademiq.dev` |

Demo passwords live in `apps/backend/services/billing-service/src/bin/seed.rs`.

Alternatives to `make dev`:

- `make dev-tmux` — fallback for machines without mprocs (needs tmux)
- `make dev-parallel` — last-resort fallback with no extra tooling
  (`make -j2`, logs interleave)

### Make commands — when to run what

| Command | When to run | Cost |
|---|---|---|
| `make dev` | Daily loop — every code change (host cargo-watch, infra in Docker) | ~13s/edit, 0.4s no-op |
| `make up` / `make down` | Start/stop Postgres + RabbitMQ | seconds |
| `make migrate` | After adding a migration | fast |
| `make seed` | Once, to load demo data | **SLOW** — minutes (cold) |
| `make build` | Rarely; only to test the release **deploy images** (CI builds these → GHCR) | **SLOW** — ~8 min cold / ~75s per-service change |
| `make test` | Before a PR (full suites). Quick check: `cargo test` in `apps/backend` | **SLOW** — minutes |
| `make test-e2e` | Before a PR touching cross-service flows | **SLOW** — minutes |
| `make test-web` | Web Vitest + Playwright | **SLOW** — minutes |
| `make clean` | Rarely; forces a full cold rebuild next | **SLOW** next build — deletes ~9.5 GB |
| `make purge` | Nuke volumes + artefacts | destructive (confirms) |

> **SLOW** targets warn and ask before running; auto-skipped in CI / non-TTY /
> with `YES=1` (e.g. `YES=1 make build`). `make rebuild` was removed — use
> `make dev`.

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
