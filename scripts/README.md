# Parent repo scripts

Operator/developer scripts yang live di parent repo `scripts/`. Bukan
bagian backend submodule — jalankan langsung dari root repo.

## Daftar script

| Script | Tujuan |
|---|---|
| `confirm.sh` | Prompt konfirmasi untuk target Makefile SLOW/expensive (build, test, clean) |
| `db-switch.sh` | Switch konteks DB backend (local Postgres ↔ dev Supabase), reset RabbitMQ |
| `db-sync.sh` | Dump prod Supabase → restore ke local Postgres (schema-per-service, dengan backup) |
| `doctor.sh` | Cek tooling yang dibutuhkan + hints install (`make doctor`) |
| `manage-gcloud-vm.sh` | Manajemen GCP VM prod (start/stop/resize) |
| `migrate-gcloud-disk.sh` | Migrasi GCP VM ke disk standard 30GB (Free Tier) |
| `purge.sh` | DESTRUCTIVE: hentikan service, hapus Docker volumes + build artefak |
| `rabbitmq-purge.sh` | Wipe semua data local RabbitMQ (full reset, pencegah cross-DB pollution) |
| `supabase-sync.sh` | *(deprecated — akan dihapus; gunakan `db-sync.sh`)* Dump prod Supabase → restore ke dev |
| `backfill_evaluation_weights.sql` | Backfill bobot evaluasi 100% + recompute rapor (tenant-scoped) |

---

## backfill_evaluation_weights.sql

Tenant-scoped maintenance SQL untuk grading-service. Mengisi
`report_formula` weight=100 untuk evaluasi tanpa bobot (hanya subject
dengan tepat 1 evaluasi), lalu recompute `subject_report_score` (live)
+ `report_subject_score` (frozen) + summary JSON.

- **Scope:** hanya tenant TPQ BAITUR ROCHMAN (hardcoded `tenant_id`)
- **Idempotent:** aman dijalankan ulang (`ON CONFLICT` di semua stage)
- **Dry-run default:** rollback + print ringkasan; commit hanya jika
  `-v DRY_RUN=false`
- **Tenant guard:** verifikasi `school_name` sebelum eksekusi

### Prasyarat

Connection string harus route ke schema `grading` via
`options=-c%20search_path%3Dgrading`. Ambil credential dari
`apps/backend/.env.dev-supabase` (DEV) atau `.env.prod` (PROD) —
**jangan hardcode password di command line atau commit ke git**.

### Eksekusi (DEV DB)

Ambil `PGPASSWORD`, `host`, `user` dari `apps/backend/.env.dev-supabase`
(field `GRADING_DATABASE_URL`), lalu:

```bash
# Dry-run (preview, rollback semua changes):
PGPASSWORD='<dari .env.dev-supabase>' \
psql "host=aws-1-ap-southeast-1.pooler.supabase.com port=5432 \
  dbname=postgres user=postgres.mpjztngvlzfpyofgofyw \
  sslmode=require options=-c%20search_path%3Dgrading" \
  -v DRY_RUN=true \
  -f scripts/backfill_evaluation_weights.sql

# Live run (commit):
PGPASSWORD='<dari .env.dev-supabase>' \
psql "host=aws-1-ap-southeast-1.pooler.supabase.com port=5432 \
  dbname=postgres user=postgres.mpjztngvlzfpyofgofyw \
  sslmode=require options=-c%20search_path%3Dgrading" \
  -v DRY_RUN=false \
  -f scripts/backfill_evaluation_weights.sql
```

Untuk PROD, ganti `host`/`user`/`PGPASSWORD` sesuai DB target.
`tenant_id` tetap hardcoded di script (TPQ BAITUR ROCHMAN).

### Output yang diharapkan (DEV, data saat ini)

| Metrik | Sebelum | Sesudah |
|---|---|---|
| `report_formula` rows | 14 | 74 |
| `subject_report_score` rows | 30 | 834 |
| Draft cards summaries | 1 subject | 13 subjects |

### Verifikasi

Script otomatis menjalankan query read-only setelah transaction untuk
validasi post-state (`formula_rows`, `live_score_rows`, `draft_cards`,
summary per card).

### Catatan

- Script tidak membuat report card baru — untuk homeroom tanpa Draft
  cards, user generate rapor via UI/API setelah backfill
- Subject dengan 2+ evaluasi di-skip (butuh konfigurasi formula manual)
- Replikasi presisi `recompute_subject_live_scores_batch` dari
  `grading-service/src/commands.rs` dan `derive_report_summary` dari
  `grading-service/src/domain.rs`
