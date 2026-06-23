# Eksplorasi: apakah ada pola yang merusak desain event-driven?

> Catatan untuk session terpisah. Lanjutan dari diskusi `add-term-evaluation-templates`
> dan `fix-non-admin-access-and-dialog` (2026-06-22/2026-06-23).
> Tujuan session ini: **explore-only** — petakan apakah codebase saat ini sudah
> melanggar prinsip "projection-based service communication", bukan implementasi.

## Latar belakang diskusi (kenapa topik ini muncul)

Saat merancang fitur evaluasi, muncul permintaan: "block pembuatan teaching
assignment kalau term itu belum punya report type". Ini ditolak dari desain
karena akan memaksa **academic-ops-service** mengetahui state milik
**grading-service** secara sinkron — melanggar prinsip di `AGENTS.md`:

> "projection-based service communication"
> services tidak saling panggil sinkron; mereka membaca projeksi lokal yang
> diisi lewat event.

Solusi yang dipilih: **self-healing + nudge**, karena grading-service sudah
memegang KEDUA sisi data (projeksi `teaching_authz` + tabel `evaluation`),
sehingga "penugasan mana yang belum punya evaluasi" bisa dihitung lokal tanpa
lintas-service.

## Prinsip yang ingin dijaga

```
BENAR (event-driven, projeksi):
  service A  --emit event-->  outbox/RabbitMQ  --consume-->  service B
                                                              └─ tulis projeksi lokal
  service B baca kebutuhannya dari projeksi lokal (read-model) miliknya sendiri.

SALAH (coupling sinkron):
  service A  --HTTP call saat request-->  service B   (blocking, runtime coupling)
  service A baca tabel milik service B langsung (shared DB / cross-db query)
```

Aturan turunan dari `AGENTS.md` + `apps/backend/CONVENTIONS.md`:
- Komunikasi antar-service via projeksi, bukan call sinkron.
- Event: `domain.action.past`, envelope `{event_id, event_type, occurred_at, payload}`.
- Pakai outbox pattern untuk publish.
- Jangan percaya `tenant_id` dari client; resolve dari JWT.
- Setiap service punya DB sendiri (`*_db`); tidak ada cross-db join.

## Contoh pola BENAR yang sudah ada (baseline referensi)

- `teacher.assigned`: academic-ops `assign_teaching` (commands.rs:986) emit ke
  outbox → grading consume (events.rs:126) → `upsert_teaching_authz` ke projeksi
  lokal `teaching_authz`. Grading lalu otorisasi evaluasi/nilai dari projeksi itu,
  bukan dengan memanggil academic-ops.
- `teacher.account_linked` / `teacher.account_unlinked`: pola serupa (IDs only).
- grading punya projeksi `valid_term`, `valid_year`, `enrolled_student`,
  `tenant_subscription_state` — semuanya read-model lokal.

## Hipotesis area yang PERLU diselidiki (kandidat pelanggaran)

Belum diverifikasi — ini daftar tempat untuk dicek di session berikutnya:

1. **Frontend sebagai "orchestrator" lintas-service.**
   Pola yang sudah terlihat di diskusi bug: halaman web memanggil banyak endpoint
   service berbeda lalu menyatukan/lookup di client-side (mis. `/grading/entry`
   dulu gabungkan teachers (academic-ops) + users (iam) + assignments). Ini bukan
   pelanggaran backend event-driven, tapi gejala "data yang seharusnya satu
   read-model dipaksa digabung di client". Cek: berapa banyak halaman melakukan
   client-side join lintas-service?

2. **Apakah ada service yang HTTP-call service lain saat melayani request?**
   Grep lintas service untuk pemanggilan HTTP keluar (reqwest/hyper client) di
   jalur request handler — bukan di seeding/CLI. Kandidat: billing ↔ iam,
   academic-ops ↔ academic-config.

3. **Apakah ada cross-db / shared-table assumption?**
   Cek apakah ada service yang baca tabel milik DB service lain (harusnya tiap
   service hanya akses `*_db` miliknya). Cek string koneksi & query.

4. **Projeksi yang stale / tidak punya event sumber.**
   `teaching_authz` diisi `teacher.assigned`. Tapi kalau assignment DIHAPUS di
   academic-ops, adakah event `teacher.unassigned` yang membersihkan projeksi
   grading? Kalau tidak ada, projeksi bisa stale → otorisasi salah. Cek
   `bulk-delete` teaching assignment: apakah emit event penghapusan?

5. **Konsistensi nama/atribut yang diduplikasi.**
   `teacher.full_name`, `email` ada di academic-ops. Kalau berubah, adakah event
   yang mempropagasi ke service lain yang menyimpan salinan? Atau setiap konsumen
   simpan ID saja (lebih aman)? `teacher.assigned` saat ini IDs-only — bagus.
   Cek apakah ada projeksi lain yang menyalin nama lalu jadi sumber stale.

6. **Arah event balik (grading → academic-ops).**
   Saat ini belum ada. Kalau fitur masa depan (mis. block assignment, atau status
   "report type sudah ada") butuh academic-ops tahu state grading, godaannya
   bikin HTTP sync. Catat sebagai titik rawan; solusi benar = event
   `report_type.created/deleted` + projeksi di academic-ops.

## Pertanyaan kunci untuk session eksplorasi

- Apakah ada handler request (bukan CLI/seed) yang memanggil service lain via HTTP?
- Apakah semua mutation lintas-service-relevant punya event + outbox, termasuk
  jalur DELETE/bulk-delete?
- Apakah ada projeksi tanpa event pembersih (hanya upsert, tak ada delete)?
- Apakah frontend memikul tanggung jawab join yang seharusnya jadi read-model
  backend? (kandidat untuk endpoint/projeksi baru per fitur)
- Apakah ada cross-db access?

## Metode yang disarankan (explore-only, jangan implementasi)

- Subagent "explore" untuk grep tiap service: outbound HTTP client di jalur http
  handler; daftar event yang di-emit vs yang di-consume (cari asimetri: di-consume
  tapi tak pernah di-emit, atau mutation tanpa event).
- Petakan setiap tabel projeksi → event sumbernya → apakah ada
  insert/update/delete lengkap.
- Inventaris halaman web yang memanggil >1 service lalu join di client.
- Hasil akhir: daftar konkret "pola yang menyimpang" + rekomendasi
  (event baru / projeksi / endpoint khusus per fitur), TANPA menulis kode.

## Keputusan desain terkait (sudah diambil, konteks)

- Fitur evaluasi: TANPA hard-block assignment. Materialisasi self-healing
  (auto via `teacher.assigned` + backfill manual + nudge), semua dihitung lokal
  di grading. Lihat `openspec/changes/add-term-evaluation-templates/design.md`
  (D3, D4) dan proposal terkait.
