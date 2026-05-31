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
